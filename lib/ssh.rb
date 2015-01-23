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

# ~ require 'rubygems'
require 'lorj'
require 'highline/import'
require 'cloud_connection.rb'

# ~ require 'security.rb'
# ~ include SecurityGroup

#
# ssh module
#
module Forj
  # This module provides the behavior to create a ssh connection
  module Ssh
    def self.connect(name, oConfig)
      o_cloud = Forj::CloudConnection.connect(oConfig)

      PrcLib.state(format("Getting information about forge '%s'", name))

      o_forge = o_cloud.Get(:forge, name)

      if o_forge[:servers].count > 0
        if oConfig[:box_ssh]
          o_server = validate_server_name(name)

          if !o_server.nil?
            ssh_connection(oConfig, o_cloud, name, o_server[:id])
          else
            PrcLib.debug("server '%s.%s' was not found",
                         oConfig[:box_ssh], name)
            PrcLib.high_level_msg("server '%s.%s' was not found.\n",
                                  oConfig[:box_ssh], name)
          end
        else
          o_server_number = select_forge_server(o_forge)

          ssh_connection(
            oConfig,
            o_cloud,
            name,
            o_forge[:servers][o_server_number][:id]
          )
        end
      else
        PrcLib.high_level_msg("No server(s) found for instance name '%s' \n",
                              name)
      end
    end

    def self.select_forge_server(o_forge)
      # Ask the user to get server(s) to create ssh connection
      server_list = []
      index = 0
      s_default = nil
      o_forge[:servers].each do |server|
        server_list[index] = server[:name]
        s_default = server[:name] if server[:name].include? 'maestro'
        index += 1
      end

      say(format(
            'Select box for ssh connection %s',
            ((s_default.nil?) ? '' : format(
              'Default: ' + "|%s|\n", s_default
            ))
          )
      )
      value = choose do |q|
        q.choices(*server_list)
        q.default = s_default unless s_default.nil?
      end

      o_server_number = server_list.index(value)
      o_server_number
    end

    def self.ssh_connection(oConfig, o_cloud, name, server_id)
      # Property for :forge
      oConfig.set(:instance_name, name)
      # Property for :ssh
      oConfig.set(:forge_server, server_id)

      o_cloud.Create(:ssh)
    end

    def self.validate_server_name(name)
      box_ssh = oConfig[:box_ssh]

      o_server = nil
      regex =  Regexp.new(format('%s\.%s$', box_ssh, name))

      o_forge[:servers].each do |server|
        o_name = server[:name]
        next if (regex =~ o_name).nil?
        o_server = server
        break
      end

      o_server
    end
  end
end
