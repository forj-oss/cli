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
require_relative 'security.rb'
include SecurityGroup
#require_relative 'log.rb'
#include Logging
require_relative 'ssh.rb'
include Ssh
require_relative 'compute.rb'
include Compute

#
# Down module
#
module Down
  def down(oConfig, name)
    begin

      initial_msg = 'deleting forge "%s"' % [name]
      Logging.info(initial_msg)

      oFC=ForjConnection.new(oConfig)

      Compute.delete_forge(oFC, name)

      #~ router = Network.get_router(oFC, 'private-ext')
      #~ subnet = Network.get_subnet(oFC, name)
      #~ Network.delete_router_interface(subnet.id, router)
#~
      #~ Network.delete_subnet(oFC, subnet.id)
      #~ network = Network.get_network(oFC, name)
      #~ Network.delete_network(oFC, network.name)

    rescue SystemExit, Interrupt
      Logging.error('process interrupted by user')
    rescue Exception => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end
end
