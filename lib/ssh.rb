#!/usr/bin/env ruby
# encoding: UTF-8

# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

require 'rubygems'

require 'security.rb'
include SecurityGroup

#
# ssh module
#
module Ssh
   def connect(name, oConfig)
      oForjAccount = ForjAccount.new(oConfig)

      oForjAccount.ac_load()

      aProcesses = []

      # Defines how to manage Maestro and forges
      # create a maestro box. Identify a forge instance, delete it,...
      aProcesses << File.join($LIB_PATH, 'forj', 'ForjCore.rb')

      # Defines how cli will control FORJ features
      # boot/down/ssh/...
      aProcesses << File.join($LIB_PATH, 'forj', 'ForjCli.rb')

      oCloud = ForjCloud.new(oForjAccount, oConfig[:account_name], aProcesses)

      oForge = oCloud.Get(:forge, name)

      if oForge[:servers].count > 0
        if oConfig[:box_ssh]
          box_ssh = oConfig[:box_ssh]

          oServer = nil
          regex =  Regexp.new('%s\.%s$' % [box_ssh, name])

          oForge[:servers].each { |server|
            oName = server[:name]
            next if (regex =~ oName) == nil
            oServer = server
            break
          }

          if oServer != nil
            #Property for :forge
            oConfig.set(:instance_name, name)
            #Property for :ssh
            oConfig.set(:forge_server, oServer[:id])

            oCloud.Create(:ssh)
          else
            Logger.debug("server '%s.%s' was not found" % [oConfig[:box_ssh], name] )
            Logger.high_level_msg("server '%s.%s' was not found" % [oConfig[:box_ssh], name] )
          end

        else
          #Ask the user to get server(s) to create ssh connection
          serverList = []
          index = 0
          sDefault = nil
          oForge[:servers].each{ |server|
            serverList[index] = server[:name]
            sDefault = server[:name] if server[:name].include? "maestro"
            index = index + 1
          }

          say("Select box for ssh connection %s" % ((sDefault.nil?)? "" : "Default: " + "|%s|\n" % sDefault))
          value = choose { | q |
            q.choices(*serverList)
            q.default = sDefault if not sDefault.nil?
          }

          oServerNumber = serverList.index(value)

          #Property for :forge
          oConfig.set(:instance_name, name)
          #Property for :ssh
          oConfig.set(:forge_server, oForge[:servers][oServerNumber][:id])

          oCloud.Create(:ssh)

        end
      else
        Logger.high_level_msg("No server(s) found for instance name '%s' \n" % name )
      end

   end
end
