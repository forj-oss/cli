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

#
# compute module
#
module Compute
  def delete_forge(oFC, name)
    instances = oFC.oCompute.servers.all(:name => name)
    iCount = 0
    instances.each do|instance|
      # make sure we don't delete another forge because fog filters
      # the name in a "like syntax" way
      Logging.debug("Removing '%s'" % [instance.id])
      oFC.oCompute.servers.get(instance.id).destroy
      iCount += 1
    end
	Logging.message("Forge: %s - %d servers removed" % [name, iCount])
  end
end
