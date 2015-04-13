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

require 'lorj_cloud'

module Forj
  # Provide cloud object
  module CloudConnection
    def self.connect(account)
      a_processes = []

      provider = account[:provider]

      # Defines how to manage Maestro and forges
      # Uses 'cloud' module process provided by 'lorj_cloud'
      a_processes << { :process_module => :cloud,
                       :controller_name => provider }

      # create a maestro box. Identify a forge instance, delete it,...
      a_processes << { :process_path => File.join(LIB_PATH, 'forj',
                                                  'ForjCore.rb') }

      # Defines how cli will control FORJ features
      # boot/down/ssh/...
      a_processes << { :process_path => File.join(LIB_PATH, 'forj',
                                                  'ForjCli.rb') }

      # Loading CloudCore embedding provider controller + its process.
      o_cloud = Lorj::Core.new(account, a_processes)

      o_cloud
    end
  end
end
