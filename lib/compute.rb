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

require_relative 'connection.rb'
include Connection
require_relative 'log.rb'
include Logging

#
# compute module
#
module Compute
  def delete_forge(name)
    instances = Connection.compute.servers.all(:name => name)
    instances.each do|instance|
      # make sure we don't delete another forge because fog filters
      # the name in a "like syntax" way
      Connection.compute.servers.get(instance.id).destroy
    end
  end
end