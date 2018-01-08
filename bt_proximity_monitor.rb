#!/usr/bin/ruby

# Copyright 2016,2017 hidenorly
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'optparse'
require 'date'
require 'timeout'

class NetUtils
	# "aa:bb:cc:dd:ee:ff hoge" -> {:macAddr=>aa:bb:cc:dd:ee:ff, :hostName=>"hoge"}
	def self.getDeviceInfo(aLine)
		result = nil
		pos = aLine.index(" ")
		if pos!=nil then
			mac = aLine[0..pos].strip
			hostName = aLine[pos+1..aLine.length].strip
			mac.tr!("-", ":") if mac.include?("-")
			if mac.count(":")==5 then
				result = {:macAddr => mac, :hostName=>hostName}
			end
		end
		return result
	end

	def self.loadTargetDevices(targetDevice)
		result = []
		if File.exist?(targetDevice) then
			File.open(targetDevice) do |file|
				file.each_line do |aLine|
					aLine.strip!
					aDeviceInfo = getDeviceInfo(aLine)
					if aDeviceInfo then
						result << aDeviceInfo
					end
				end
			end
		else
			result << {:macAddr=>targetDevice, :hostName=>nil} if targetDevice =~ /([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/
		end
		return result
	end
end

class ExecUtils
	def self.executeExternalCommand(exec_cmd, timeOutSec=10, execOutputCallback = method(:puts), execOutputCallbackArg=nil)
		pio = nil
		begin
			Timeout.timeout(timeOutSec) do
				pio = IO.popen(exec_cmd, STDERR=>[:child, STDOUT]).each do |exec_output|
					if execOutputCallbackArg then
						execOutputCallback.call(exec_output, execOutputCallbackArg)
					else
						execOutputCallback.call(exec_output)
					end
				end
			end
		rescue Timeout::Error => ex
#			puts "Time out error on execution : #{exec_cmd}"
			if pio then
				if pio.pid then
					Process.detach(pio.pid)
					Process.kill(9, pio.pid)
				end
			end
		rescue
#			puts "Error on execution : #{exec_cmd}"
			# do nothing
		ensure
			pio.close if pio
		end
	end
end

class BTProximity
	EXEC_CMD_GET_RSSI = "hcitool rssi "
	FILTER_RSSI = "RSSI return value"

	def self.getRSSI(macAddr)
		rssi = []
		rssi << nil
		def self._rssiSub(aLine, aRssi)
			aRssi[0] = aLine if aLine.include?(FILTER_RSSI)
		end
		ExecUtils.executeExternalCommand(EXEC_CMD_GET_RSSI+macAddr, 3, method(:_rssiSub), rssi)
		return rssi[0]
	end

	EXEC_CMD_CONNECT1 = "rfcomm connect 0 "
	EXEC_CMD_CONNECT2 = " 1 2> /dev/null >/dev/null &"

	def self.connectByRfComm(macAddr)
		puts "try to connect #{macAddr}"
		system(EXEC_CMD_CONNECT1+macAddr+EXEC_CMD_CONNECT2)
		sleep 3
	end

	EXEC_CMD_L2PING = "l2ping -t 1 -c 1 -f "
	FILTER_L2PING = "Can't connect"
	FILTER_L2PING2 = "% loss"
	FILTER_L2PING0LOSS = " 0% loss"
	FILTER_L2PING100LOSS = "100% loss"

	$deviceStatusCache={}
	def self.checkL2Ping(macAddr)
		sleep 1
		result = []
		result << nil
		def self._l2pingSub(aLine, result)
			result[0] = aLine if aLine.include?(FILTER_L2PING) || aLine.include?(FILTER_L2PING2)
		end
		ExecUtils.executeExternalCommand(EXEC_CMD_L2PING+macAddr, 6, method(:_l2pingSub), result)

		connected = ($deviceStatusCache.has_key?(macAddr)) ? $deviceStatusCache[macAddr] : false
		if result[0] then
			res = result[0].to_s
			connected = false if res.include?(FILTER_L2PING) || res.include?(FILTER_L2PING100LOSS)
			connected = true if res.include?(FILTER_L2PING0LOSS)
		end
		$deviceStatusCache[macAddr] = connected

		return connected
	end

	DETECTION_TYPE1="rfcomm"
	DETECTION_TYPE2="l2ping"

	def self.getProximityDevices(devices, detectionType=DETECTION_TYPE1)
		connectedDevices = []
		devices.each do |aDevice|
			case detectionType
			when DETECTION_TYPE1
				if getRSSI(aDevice[:macAddr])==nil then
					# not connected
					connectByRfComm(aDevice[:macAddr])
				else
					connectedDevices << aDevice
				end
			when DETECTION_TYPE2
				connectedDevices << aDevice if checkL2Ping(aDevice[:macAddr])
			end
		end
		return connectedDevices
	end

	def self.checkProximity(devices, detectionType=DETECTION_TYPE1)
		connectedDevices = getProximityDevices(devices, detectionType)
		return !connectedDevices.empty?
	end
end

class HashUtils
	def self.deepCopy(a)
		if (a) then
			result = {}
			a.each do |k,v|
				v=deepCopy(v) if(v.kind_of?(Hash))
				result[k] = v
			end
			return result
		end
	end
end

class RuleEngine
	S_RULES_INIT = 0
	S_RULES_FOUND_NEW_SECTION = 1
	S_RULES_PARSE_ON_START = 2
	S_RULES_PARSE_ON_END = 3
	S_RULES_PARSE_ON_CONNECTED = 4
	S_RULES_PARSE_ON_DISCONNECTED = 5

	def self.parseRuleState(aLine)
		if aLine.start_with?("[") && aLine.end_with?("]") then
			return S_RULES_FOUND_NEW_SECTION
		elsif aLine.start_with?("#") then
			return S_RULES_PARSE_ON_START 		 if aLine.start_with?("#onStart")
			return S_RULES_PARSE_ON_END			 if aLine.start_with?("#onEnd")
			return S_RULES_PARSE_ON_CONNECTED 	 if aLine.start_with?("#onConnected")
			return S_RULES_PARSE_ON_DISCONNECTED if aLine.start_with?("#onDisconnected")
		end
		return nil
	end

	#[2016-12-31 16:30-23:30]
	#[16:30-23:30 Mon Tue Wed Thu Fri Sat Sun]
	def self.parseCondition(aLine)
		result = {:startTime=>nil, :endTime=>nil, :onDay=>nil, :Mon=>false, :Tue=>false, :Wed=>false, :Thu=>false, :Fri=>false, :Sat=>false, :Sun=>false, :randomMin=>0}
		aLine = aLine[1..aLine.length-2]
		values = aLine.split(" ")
		if values.length then
			values.each do |aVal|
				aVal.strip!
				aVal.downcase!
				if aVal =~ /([0-1][0-9]|[2][0-3]):[0-5][0-9]/ then
					# time
					times = aVal.split("-")
					if times.length == 2 then
						result[:startTime] = times[0]
						result[:endTime] = times[1]
					else
						result[:startTime] = result[:endTime] = times[0]
					end
				elsif aVal.start_with?("(random:") then
					aVal = aVal[8..aVal.length]
					result[:randomMin] = aVal.to_i ? aVal.to_i : 0
					if aVal.end_with?("min)") then
						result[:randomMin] *= 1
					elsif aVal.end_with?("hour)") then
						result[:randomMin] *= 60
					end
					result[:startTime] = getRandomizedHHMM(getMinutesFromHHMM(result[:startTime]), result[:randomMin]) if result[:startTime]
					result[:endTime] = getRandomizedHHMM(getMinutesFromHHMM(result[:endTime]), result[:randomMin]) if result[:endTime]
				else
					result[:onDay] = aVal if aVal =~ /[0-9]+\-[0-9]+\-[0-9]/ #aVal.include?("-")
					everyday = (aVal=="everyday") ? true : false
					result[:Mon] = true if aVal=="mon" || everyday
					result[:Tue] = true if aVal=="tue" || everyday
					result[:Wed] = true if aVal=="wed" || everyday
					result[:Thu] = true if aVal=="thu" || everyday
					result[:Fri] = true if aVal=="fri" || everyday
					result[:Sat] = true if aVal=="sat" || everyday
					result[:Sun] = true if aVal=="sun" || everyday
				end
			end
		end
		return result
	end

	def self.getTriggerFromRule(aRuleState, state, isNewHandler=false)
		case state
			when S_RULES_PARSE_ON_START
				return aRuleState[:start]
			when S_RULES_PARSE_ON_END
				return aRuleState[:end]
			when S_RULES_PARSE_ON_CONNECTED
				if isNewHandler then
					aConnected = {:condition=>nil, :count=>0, :executes=>[]}
					aRuleState[:connected] << aConnected
				end
				return aRuleState[:connected].last
			when S_RULES_PARSE_ON_DISCONNECTED
				if isNewHandler then
					aDisconnected = {:condition=>nil, :count=>0, :executes=>[]}
					aRuleState[:disconnected] << aDisconnected
				end
				return aRuleState[:disconnected].last
		end
		return nil
	end

	def self.loadRules(ruleFile)
		result = []
		if File.exist?(ruleFile) then
			state = S_RULES_INIT
			aRuleState = nil
			File.open(ruleFile) do |file|
				file.each_line do |aLine|
					aLine.strip!
					tmpState = parseRuleState(aLine)
					if tmpState then
						state = tmpState
						# found new section or new handler
						if tmpState == S_RULES_FOUND_NEW_SECTION then
							# found new section
							result << aRuleState if aRuleState!=nil
							aRuleState={
								:condition=>	parseCondition(aLine),
								:start=>		{:condition=>nil, :executes=>[]},
								:end=>			{:condition=>nil, :executes=>[]},
								:connected=>	[],
								:disconnected=>	[]
							}
						else
							# found new handler
							pos = aLine.index("if ")
							if pos!=nil then
								if aLine.end_with?("times") then
									condition = aLine[pos+3..aLine.length].to_i
								else
									condition = aLine[pos+3..aLine.length].strip
								end
								aTrigger = getTriggerFromRule(aRuleState, state, true)
								if aTrigger!=nil then
									aTrigger[:condition] = condition
								end
							end
						end
					else
						# in same handler
						aTrigger = getTriggerFromRule(aRuleState, state)
						if aTrigger!=nil then
							aTrigger[:executes] << aLine if !aLine.empty?
						end
					end
				end
				result << aRuleState if result.length>=0 && result[result.length]!=aRuleState
			end
		end
		return result
	end

	def self.getMinutesFromHHMM(timeHHMM)
		aTime = timeHHMM.split(":")
		if aTime.length == 2 then
			return aTime[0].to_i * 60 + aTime[1].to_i
		end

		return nil
	end

	def self.matchCheckTime?(date, aCondition)
		result = false

		if aCondition[:startTime] && aCondition[:endTime] then
			startTime = getMinutesFromHHMM(aCondition[:startTime])
			endTime = getMinutesFromHHMM(aCondition[:endTime])
			nowTime = getMinutesFromHHMM("#{date.hour}:#{date.min}")
			result = true if nowTime>=startTime && nowTime<=endTime
		elsif !aCondition[:startTime] && !aCondition[:endTime] then
			result = true
		end

		return result

	end

	def self.matchCheckDay?(date, aCondition)
		result = false

		if aCondition[:onDay] then
			day = aCondition[:onDay].split("-")

			result = true if day.length == 3 &&
				day[0].to_i == date.year &&
				day[1].to_i == date.month &&
				day[2].to_i == date.day
		end

		return result
	end

	def self.matchCheckWeek?(date, aCondition)
		result = false

		week = date.strftime("%a")
		result = true if (week=="Mon" && aCondition[:Mon]) ||
			(week=="Tue" && aCondition[:Tue]) ||
			(week=="Wed" && aCondition[:Wed]) ||
			(week=="Thu" && aCondition[:Thu]) ||
			(week=="Fri" && aCondition[:Fri]) ||
			(week=="Sat" && aCondition[:Sat]) ||
			(week=="Sun" && aCondition[:Sun])

		return result
	end


	def self.isCandidateMatchTime?(aCondition)
		result = false

		result = true if aCondition[:onDay]==nil && 
			!aCondition[:Mon] &&
			!aCondition[:Tue] &&
			!aCondition[:Wed] &&
			!aCondition[:Thu] &&
			!aCondition[:Fri] &&
			!aCondition[:Sat] &&
			!aCondition[:Sun] &&
			aCondition[:startTime]!=nil &&
			aCondition[:endTime]!=nil

		return result
	end

	def self.getRandomizedHHMM(minutes, randomMinutes)
		minutes = minutes - (randomMinutes/2).to_i + rand(randomMinutes)
		minutes = 0 if minutes < 0
		timeHHMM="#{(minutes / 60).to_s.rjust(2,"0")}:#{(minutes % 60).to_s.rjust(2,"0")}"

		return timeHHMM
	end

	def self.getNextRule(rules)
		nowTime = Time.now

		dayCandidates = []
		weekCandidates = []
		timeCandidates = []

		if rules then
			rules.each do |aRule|
				aCondition = aRule[:condition]
				if matchCheckDay?(nowTime, aCondition) then
					dayCandidates << aRule
				elsif matchCheckWeek?(nowTime, aCondition) then
					weekCandidates << aRule
				elsif isCandidateMatchTime?(aCondition) then
					timeCandidates << aRule
				end
			end
		end

		candidates = dayCandidates + weekCandidates + timeCandidates # priority order

		nextRule = nil
		candidates.each do |aCandidate|
			aCondition = aCandidate[:condition]
			if matchCheckTime?(nowTime, aCondition) then
				nextRule = aCandidate
				break
			end
		end

		return nextRule
	end

	def self.execOnRule(execs, defaultExecTimeOut)
		execs = execs[:executes]
		execs.each do |anExec|
			ExecUtils.executeExternalCommand(anExec, defaultExecTimeOut)
		end
	end

	$curWeek = nil
	def self.isDayChanged?
		week = Time.now.strftime("%a")
		result = (week!=$curWeek) ? true : false
		$curWeek = week
		return result
	end

	def self._handleCondition(targetRule, proximityDevices, defaultExecTimeOut)
		result = false

		targetRule.each do |aConnected|
			doIt = false
			if aConnected[:condition] then
				if aConnected[:condition].is_a?(Integer) then
					aConnected[:count] = aConnected[:count] + 1
					doIt=true if aConnected[:count]>=aConnected[:condition]
				else
					proximityDevices.each do |aDevice|
						conditions = aConnected[:condition].to_s.split("||")
						conditions = [ aConnected[:condition].to_s.downcase ] if !conditions.to_a.length
						conditions.each do |aCondition|
							aCondition = aCondition.to_s.downcase
							if "any" == aCondition ||
								aDevice[:macAddr].to_s.downcase == aCondition ||
								aDevice[:hostName].to_s.downcase == aCondition then
								doIt = true
								break
							end
						end
					end
				end
			else
				doIt=true
			end

			if doIt then
				#puts aConnected
				execOnRule(aConnected, defaultExecTimeOut)
				aConnected[:count]=0
				result = true
			end
		end

		return result
	end

	def self.startWatcher(devices, options)
		sleepPeriod = options[:period]
		defaultExecTimeOut = options[:defaultTimeout]
		rules = []
		loop do
			rules = loadRules(options[:ruleFile]) if isDayChanged?
			curRule = getNextRule(rules)
			if curRule then
				execOnRule(curRule[:start], defaultExecTimeOut)
				proximityStatus = nil
				begin
					proximityDevices = BTProximity.getProximityDevices(devices, options[:proximityDetection])
					curStatus = !proximityDevices.empty?
					if curStatus!=proximityStatus then
						targetRule = curStatus ? curRule[:connected] : curRule[:disconnected]
						if _handleCondition(targetRule, proximityDevices, defaultExecTimeOut) then
							proximityStatus = curStatus
						end
					else
						targetRule = !curStatus ? curRule[:connected] : curRule[:disconnected]
						targetRule.each do |aConnected|
							aConnected[:count]=0
						end
					end
					sleep(sleepPeriod)
					nextRule = getNextRule(rules)
				end while curRule == nextRule
				execOnRule(curRule[:end], defaultExecTimeOut)
			else
				sleep(sleepPeriod)
			end
		end
	end

end


options = {
	:ruleFile => "rules.cfg",
	:targetDevice => "devices.cfg",
	:period => 1,
	:defaultTimeout => 10,
	:proximityDetection => BTProximity::DETECTION_TYPE1
}

opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: Watch BT devices, Do on connected / disconnected"
	opts.on_head("BT Proximity Monitor Copyright 2016,2017 hidenorly")
	opts.version = "1.0.0"

	opts.on("-r", "--ruleFile=", "Set rule file (default:#{options[:ruleFile]})") do |ruleFile|
		options[:ruleFile] = ruleFile
	end

	opts.on("-t", "--targetDevice=", "Set target device file or mac addr") do |targetDevice|
		options[:targetDevice] = targetDevice
	end

	opts.on("-p", "--priod=", "Set sleep period (default:#{options[:period]})") do |period|
		options[:period] = period
	end

	opts.on("-o", "--defaultExecTimeOut=", "Set default execution timeout (default:#{options[:defaultTimeout]})") do |defaultTimeout|
		options[:defaultTimeout] = defaultTimeout
	end

	opts.on("-d", "--proximityDetection=", "Set proximity detection method \"rfcomm\" or \"l2ping\" (default:#{options[:proximityDetection]})") do |proximityDetection|
		options[:proximityDetection] = (proximityDetection.downcase!="rfcomm") ? "l2ping" : "rfcomm"
	end
end.parse!

devices = NetUtils.loadTargetDevices(options[:targetDevice])
RuleEngine.startWatcher(devices, options)

