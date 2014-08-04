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
require_relative 'log.rb'
include Logging
require_relative 'ssh.rb'
include Ssh
require_relative 'compute.rb'
include Compute

#
# Down module
#
module Down
  def down(name)
    begin

      initial_msg = 'deleting forge "%s"' % [name]
      Logging.info(initial_msg)
      puts (initial_msg)

      Compute.delete_forge(name)

      router = Network.get_router('private-ext')
      subnet = Network.get_subnet(name)
      Network.delete_router_interface(subnet.id, router)

      Network.delete_subnet(subnet.id)
      network = Network.get_network(name)
      Network.delete_network(network.name)

    rescue SystemExit, Interrupt
      puts 'process interrupted by user'
      Logging.error('process interrupted by user')
    rescue Exception => e
      Logging.error(e.message)
    end
  end
end
