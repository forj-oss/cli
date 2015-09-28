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
    def self.get(options, key)
      @account = Lorj::Account.new(nil, Forj.file_version)
      if options[:account_name]
        get_account(options, key)
      else
        get_default(key)
      end
    end

    def self.get_account(options, key)
      if key
        Forj::Settings.account_get(@account, options[:account_name], key)
      else
        Forj::Settings.account_get_all(@account, options[:account_name])
      end
    end

    def self.get_default(key)
      if !key
        Forj::Settings.config_get_all(@account)
      else
        Forj::Settings.config_get(@account, key)
      end
    end
  end
end
