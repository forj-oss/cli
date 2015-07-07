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
require 'cloud_connection.rb'

# ~ require 'security.rb'
# ~ include SecurityGroup

#
# ssh module
#
module Forj
  # This module provides the behavior to create a ssh connection
  module Info
    def self.forge(name, account)
      o_cloud = Forj::CloudConnection.connect(account)

      PrcLib.state(format("Getting information about forge '%s'", name))

      o_forge = o_cloud.get(:forge, name, :info => true)

      if o_forge[:servers].count == 0
        PrcLib.high_level_msg("No server(s) found for instance name '%s' \n",
                              name)
      end
    end
  end
end
