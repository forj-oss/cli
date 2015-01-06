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

#
# Get module
#
module Forj
  # This module gets your account/default configuration
  module Get
    def self.get(options, o_config, key)
      if options[:account_name]
        get_account(options, o_config, key)
      else
        get_default(o_config, key)
      end
    end

    def self.get_account(options, o_config, key)
      if key
        Forj::Settings.account_get(o_config, options[:account_name], key)
      else
        Forj::Settings.account_get_all(o_config, options[:account_name])
      end
    end

    def self.get_default(o_config, key)
      if !key
        Forj::Settings.config_get_all(o_config)
      else
        Forj::Settings.config_get(o_config, key)
      end
    end
  end
end
