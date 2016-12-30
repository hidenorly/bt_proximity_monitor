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
		result << targetDevice if targetDevice =~ /([0-9a-f]{2}:){5}[0-9a-f]{2}/
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



options = {
	:ruleFile => "rules.cfg",
	:targetDevice => "devices.cfg"
}

opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: Watch BT devices, Do on connected / disconnected"
	opts.on_head("BT Proximity Monitor Copyright 2016 hidenorly")
	opts.version = "1.0.0"

	opts.on("-r", "--ruleFile=", "Set rule file") do |ruleFile|
		options[:ruleFile] = ruleFile
	end

	opts.on("-t", "--targetDevice=", "Set target device file or mac addr") do |targetDevice|
		options[:targetDevice] = targetDevice
	end
end.parse!

puts loadTargetDevices(options[:targetDevice])
puts loadRules(options[:ruleFile])