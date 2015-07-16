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
    def self.connect(name, account)
      cloud = Forj::CloudConnection.connect(account)

      PrcLib.state(format("Getting information about forge '%s'", name))

      forge = cloud.get(:forge, name, :info => false)

      if forge[:servers].count > 0
        if account[:box_ssh]
          server = validate_server_name(name, account[:box_ssh], forge)

          return if server.nil?
        else
          server = select_forge_server(forge)
        end

        params = {}
        params[:server] = server
        params[:network_used] = select_network_used(forge, server,
                                                    account['maestro#'\
                                                            'network_name'])
        cloud.create(:ssh, params)
        return
      end
      PrcLib.high_level_msg("No server(s) found for instance name '%s' \n",
                            name)
    end

    # Determine the network used by the server, to find out the IP to connect to
    #
    # it search it in the the following list. First found wins:
    # - server metadata under 'network_name'
    # - server list of network if only one is found
    # - Consider network from setup.
    #
    # At this steps, a warning is displayed as no network for public IP was
    # found on the server and will recall this function from Maestro and retry.
    #
    def self.select_network_used(forge, server, default = nil)
      unless server[:meta_data, 'network_name'].nil?
        return server[:meta_data, 'network_name']
      end
      Lorj.debug(1, "'#{server[:name]}': No 'network_name' meta_data found")

      network_used = _select_network_used_from_pubip(server, default)
      return network_used unless network_used.nil?

      Lorj.debug(1, "'#{server[:name]}': No public network found")
      return default unless default.nil?

      if /maestro\./ =~ server[:name]
        fatal('No network has been found to determine the public IP. '\
              'You may need to setup your account to find one.')
      end

      return default if forge[:servers, 'maestro'].nil?

      PrcLib.warning('Unable to determine the network hosting a public IP for'\
                     " your server '#{server[:name]}'. Trying to get it from "\
                     "'maestro'")

      maestro = forge[:servers, 'maestro']
      select_network_used(forge, maestro)
    end

    def self._select_network_used_from_pubip(server, default)
      return nil if server[:pub_ip_addresses].nil?

      networks = server[:pub_ip_addresses].keys
      return networks[0] if networks.length == 1
      return nil if networks.length == 0

      puts 'Multiple network detected on this node. '\
           'Please choose the one to use.'
      choose do |q|
        q.choices(*list)
        q.default = default if default
      end
    end

    def self.select_forge_server(o_forge)
      # Ask the user to get server(s) to create ssh connection
      server_list = []
      servers = []
      s_default = nil

      o_forge[:servers].each do |server_type, server|
        server_list << server[:name]
        servers << server
        s_default = server[:name] if server_type == 'maestro'
      end

      say(format('Select box for ssh connection %s',
                 ((s_default.nil?) ? '' : "Default: #{s_default}")))
      value = choose do |q|
        q.choices(*server_list)
        q.default = s_default unless s_default.nil?
      end

      servers[server_list.index(value)]
    end

    def self.validate_server_name(name, box_ssh, o_forge)
      unless o_forge[:servers].key?(box_ssh)
        PrcLib.debug("server '%s.%s' was not found", box_ssh, name)
        PrcLib.high_level_msg("server '%s.%s' was not found.\n", box_ssh, name)
        return
      end

      o_forge[:servers][box_ssh]
    end
  end
end
