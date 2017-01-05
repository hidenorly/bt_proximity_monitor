#!/usr/bin/ruby

# Copyright 2016 hidenorly
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

# "aa:bb:cc:dd:ee:ff hoge" -> aa:bb:cc:dd:ee:ff
def getMacAddress(mac)
	pos = mac.index(" ")
	mac = mac[0..pos] if pos!=nil
	mac.tr!("-", ":") if mac.include?("-")
	if mac.count(":")==5 then
		return mac
	end
	return nil
end

def loadTargetDevices(targetDevice)
	result = []
	if File.exist?(targetDevice) then
		File.open(targetDevice) do |file|
			file.each_line do |aLine|
				aLine.strip!
				macAddr = getMacAddress(aLine)
				if macAddr then
					result << macAddr
				end
			end
		end
	else
		result << targetDevice if targetDevice =~ /([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/
	end
	return result
end

S_RULES_INIT = 0
S_RULES_FOUND_NEW_SECTION = 1
S_RULES_PARSE_ON_START = 2
S_RULES_PARSE_ON_END = 3
S_RULES_PARSE_ON_CONNECTED = 4
S_RULES_PARSE_ON_DISCONNECTED = 5

def parseRuleState(state, aLine)
	if aLine.start_with?("[") && aLine.end_with?("]") then
		return S_RULES_FOUND_NEW_SECTION
	elsif aLine.start_with?("#") then
		return S_RULES_PARSE_ON_START 		 if aLine.start_with?("#onStart")
		return S_RULES_PARSE_ON_END			 if aLine.start_with?("#onEnd")
		return S_RULES_PARSE_ON_CONNECTED 	 if aLine.start_with?("#onConnected")
		return S_RULES_PARSE_ON_DISCONNECTED if aLine.start_with?("#onDisconnected")
	end
	return state
end

#[2016-12-31 16:30-23:30]
#[16:30-23:30 Mon Tue Wed Thu Fri Sat Sun]
def parseCondition(aLine)
	result = {:startTime=>nil, :endTime=>nil, :onDay=>nil, :Mon=>false, :Tue=>false, :Wed=>false, :Thu=>false, :Fri=>false, :Sat=>false, :Sun=>false}
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

def loadRules(ruleFile)
	result = []
	if File.exist?(ruleFile) then
		state = S_RULES_INIT
		aRuleState = nil
		File.open(ruleFile) do |file|
			file.each_line do |aLine|
				aLine.strip!
				newState = parseRuleState(state, aLine)
				if newState!=state then
					state = newState
					case state
						when S_RULES_FOUND_NEW_SECTION
							result << aRuleState if aRuleState!=nil
							aRuleState={:condition=>parseCondition(aLine), :start=>[],:end=>[],:connected=>[],:disconnected=>[]}
					end
				else
					case newState
						when S_RULES_PARSE_ON_START
							aRuleState[:start] << aLine if !aLine.empty?
						when S_RULES_PARSE_ON_END
							aRuleState[:end] << aLine if !aLine.empty?
						when S_RULES_PARSE_ON_CONNECTED
							aRuleState[:connected] << aLine if !aLine.empty?
						when S_RULES_PARSE_ON_DISCONNECTED
							aRuleState[:disconnected] << aLine if !aLine.empty?
					end
				end
			end
			result << aRuleState if result.length>=0 && result[result.length]!=aRuleState
		end
	end
	return result
end

def getMinutesFromHHMM(timeHHMM)
	aTime = timeHHMM.split(":")
	if aTime.length == 2 then
		return aTime[0].to_i * 60 + aTime[1].to_i
	end

	return nil
end

def matchCheckTime(date, aCondition)
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

def matchCheckDay(date, aCondition)
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

def matchCheckWeek(date, aCondition)
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


def isCandidateMatchTime(aCondition)
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


def getNextRule(rules)
	nowTime = Time.now

	dayCandidates = []
	weekCandidates = []
	timeCandidates = []

	rules.each do |aRule|
		aCondition = aRule[:condition]
		if matchCheckDay(nowTime, aCondition) then
			dayCandidates << aRule
		elsif matchCheckWeek(nowTime, aCondition) then
			weekCandidates << aRule
		elsif isCandidateMatchTime(aCondition) then
			timeCandidates << aRule
		end
	end

	candidates = dayCandidates + weekCandidates + timeCandidates # priority order

	nextRule = nil
	candidates.each do |aCandidate|
		aCondition = aCandidate[:condition]
		if matchCheckTime(nowTime, aCondition) then
			nextRule = aCandidate
			break
		end
	end

	return nextRule
end

def executeExternalCommand(exec_cmd, timeOutSec=10, execOutputCallback = method(:puts), execOutputCallbackArg=nil)
	pio = nil
	begin
		Timeout.timeout(timeOutSec) do
			pio = IO.popen(exec_cmd, "r").each do |exec_output|
				if execOutputCallbackArg then
					execOutputCallback.call(exec_output, execOutputCallbackArg)
				else
					execOutputCallback.call(exec_output)
				end
			end
		end
	rescue Timeout::Error => ex
		puts "Time out error on execution : #{exec_cmd}"
		if pio then
			if pio.pid then
				Process.kill(9, pio.pid)
			end
		end
	rescue
		puts "Error on execution : #{exec_cmd}"
		# do nothing
	ensure
		pio.close if pio
	end
end

def execOnRule(execs, defaultExecTimeOut)
	execs.each do |anExec|
		executeExternalCommand(anExec, defaultExecTimeOut)
	end
end

EXEC_CMD_GET_RSSI = "hcitool rssi "
FILTER_RSSI = "RSSI return value"

def getRSSI(macAddr)
	rssi = []
	rssi << nil
	def _rssiSub(aLine, aRssi)
		aRssi[0] = aLine if aLine.include?(FILTER_RSSI)
	end
	executeExternalCommand(EXEC_CMD_GET_RSSI+macAddr, 3, method(:_rssiSub), rssi)
	return rssi[0]
end

EXEC_CMD_CONNECT1 = "rfcomm connect 0 "
EXEC_CMD_CONNECT2 = " 1 2> /dev/null >/dev/null &"

def connectByRfComm(macAddr)
	puts "try to connect #{macAddr}"
	system(EXEC_CMD_CONNECT1+macAddr+EXEC_CMD_CONNECT2)
	sleep 3
end


def checkProximity(devices)
	connected = false
	devices.each do |aDevice|
		if getRSSI(aDevice)==nil then
			# not connected
			connectByRfComm(aDevice)
		else
			connected = true
		end
	end
	return connected
end

def startWatcher(devices, rules, sleepPeriod, defaultExecTimeOut)
	proximityStatus = checkProximity(devices) # try twice
	loop do
		curRule = getNextRule(rules)
		if curRule then
			proximityStatus = checkProximity(devices)
			execOnRule(curRule[:start], defaultExecTimeOut)
			begin
				curStatus = checkProximity(devices)
				if curStatus!=proximityStatus then
					if curStatus then
						execOnRule(curRule[:connected], defaultExecTimeOut)
					else
						execOnRule(curRule[:disconnected], defaultExecTimeOut)
					end
					proximityStatus = curStatus
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

options = {
	:ruleFile => "rules.cfg",
	:targetDevice => "devices.cfg",
	:period => 1,
	:defaultTimeout => 10
}

opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: Watch BT devices, Do on connected / disconnected"
	opts.on_head("BT Proximity Monitor Copyright 2016 hidenorly")
	opts.version = "1.0.0"

	opts.on("-r", "--ruleFile=", "Set rule file (default:#{options[:ruleFile]}") do |ruleFile|
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
end.parse!

devices = loadTargetDevices(options[:targetDevice])
rules = loadRules(options[:ruleFile])

startWatcher(devices, rules, options[:period], options[:defaultTimeout])

