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
require 'require_relative'

require_relative 'network.rb'
include Network
require_relative 'yaml_parse.rb'
include YamlParse
require_relative 'security.rb'
include SecurityGroup

#
# Down module
#
module Down
  def down(name)
    begin

      puts 'deleting %s...' % [name]

      definitions = YamlParse::get_values('catalog.yaml')

      # get the subnet
      subnet = Network::get_subnet(name)

      # delete the router interface
      router = Network::get_router(definitions['redstone']['router'])
      Network.delete_router_interface(subnet.id, router)

      # delete subnet
      Network.delete_subnet(subnet.id)

      # delete security group
      # Network.delete_security_group(security_group.id)

      # delete network
      Network.delete_network(name)

    rescue SystemExit, Interrupt
      puts 'process interrupted by user'
    rescue Exception => e
      puts e
    end
  end
end
