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

require 'highline/import'
require 'cloud_connection.rb'
#
# Destroy module
#
module Forj
  #  This module provides the behavior to destroy your forge's server(s)
  module Destroy
    def self.destroy(name, options)
      o_config = Lorj::Account.new(options[:config])
      o_config.set(
        :account_name,
        options[:account_name]
      ) if options[:account_name]
      o_cloud = Forj::CloudConnection.connect(o_config)

      o_forge = o_cloud.Get(:forge, name)

      if o_forge[:servers].count > 0
        destroy_server(o_cloud, o_forge, options, o_config)
      else
        PrcLib.high_level_msg("No server(s) found on forge instance '%s'.\n",
                              name)
      end
    end

    def self.destroy_server(o_cloud, o_forge, options, o_config)
      if options[:force]
        # Destroy all servers found
        o_cloud.Delete(:forge)
      else
        server_list = get_server_list(o_forge)

        o_server_number = get_server_index(server_list)

        if o_server_number >= 0 && o_server_number < o_forge[:servers].count
          # Destroy selected server
          o_config.set(:forge_server, o_forge[:servers][o_server_number][:id])
          o_cloud.Delete(:forge)
        end

        # Destroy all servers found
        o_cloud.Delete(:forge) if o_server_number ==  server_list.index('all')
        # esc
        PrcLib.high_level_msg("No server destroyed on your demand.\n",
                              name
                             ) if o_server_number ==  server_list.index('esc')
      end
    end

    def self.get_server_list(o_forge)
      # Ask the user to get server(s) to destroy
      server_list = []
      index = 0

      o_forge[:servers].each do |server|
        server_list[index] = server[:name]
        index += 1
      end

      server_list << 'all'
      server_list << 'esc'

      server_list
    end

    def self.get_server_index(server_list)
      say('Select the index of the server you want to destroy')
      value = choose do |q|
        q.choices(*server_list)
      end

      o_server_number = server_list.index(value)

      o_server_number
    end
  end
end
