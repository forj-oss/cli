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
      account = Lorj::Account.new(options[:config])

      # Loading account at account layer
      unless account.ac_load options[:account_name]
        PrcLib.fatal(1, "Invalid account '%s'. Use `forj show account` "\
                        'to get the list of valid accounts.',
                     options[:account_name])
      end

      o_cloud = Forj::CloudConnection.connect(account)

      o_forge = o_cloud.get(:forge, name)

      if o_forge[:servers].count > 0
        destroy_server(o_cloud, o_forge, options)
      else
        PrcLib.high_level_msg("No server(s) found on forge instance '%s'.\n",
                              name)
      end
    end

    def self.destroy_server(o_cloud, o_forge, options)
      if options[:force]
        # Destroy all servers found
        o_cloud.delete(:forge)
      else
        server_list, servers_id = get_server_list(o_forge)

        server_name = choose_server(server_list)

        case server_name
        when 'abort'
          PrcLib.high_level_msg("No server destroyed on your demand.\n", name)
          return
        when 'all'
          # Destroy all servers found
          o_cloud.delete(:forge)
          return
        else
          # Destroy selected server
          found = server_name.match(/ - (.*)$/)
          if found
            o_cloud.delete(:forge, :forge_server => found[1])
          else
            o_cloud.delete(:forge, :forge_server => servers_id[server_name][0])
          end
        end
      end
    end

    def self.get_server_list(forge)
      # Ask the user to get server(s) to destroy
      server_list = []
      servers_id = {}

      forge[:servers].each do |_type, server|
        server_name = server[:name]
        if servers_id.key?(server_name)
          servers_id[server_name] << server[:id]
        else
          servers_id[server_name] = [server[:id]]
        end
      end

      servers_id.each do |name, servers|
        if servers.length > 1
          servers.each { |id| server_list << name + ' - ' + id }
        else
          server_list << name
        end
      end

      server_list << 'all'
      server_list << 'abort'

      [server_list, servers_id]
    end

    def self.choose_server(server_list)
      say('Please, choose what you want to destroy')
      value = choose do |q|
        q.choices(*server_list)
      end

      value
    end
  end
end
