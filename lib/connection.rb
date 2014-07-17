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
require 'fog'
require 'require_relative'

require_relative 'yaml_parse.rb'
include YamlParse

#
# Connection module
#
module Connection
  def compute
    begin
      credentials = get_credentials
      Fog::Compute.new({
          :provider        => 'HP',
          :hp_access_key   => credentials['access_key'],
          :hp_secret_key   => credentials['secret_key'],
          :hp_auth_uri     => credentials['auth_uri'],
          :hp_tenant_id    => credentials['tenant_id'],
          :hp_avl_zone     => credentials['availability_zone'],
          :version         => 'v2'
      })
    rescue => e
      Logging.error(e.message)
    end
  end

  def network
    begin
      credentials = get_credentials
      Fog::HP::Network.new({
          :hp_access_key   => credentials['access_key'],
          :hp_secret_key   => credentials['secret_key'],
          :hp_auth_uri     => credentials['auth_uri'],
          :hp_tenant_id    => credentials['tenant_id'],
          :hp_avl_zone     => credentials['availability_zone']
      })
    rescue => e
      Logging.error(e.message)
    end
  end
end

def get_credentials
  home = File.expand_path('~')
  creds = '%s/.hpcloud/accounts/hp' % [home]
  template = YAML.load_file(creds)
  credentials = Hash.new

  begin
    credentials['access_key'] = template[:credentials][:account_id]
    credentials['secret_key'] = template[:credentials][:secret_key]
    credentials['auth_uri'] = template[:credentials][:auth_uri]
    credentials['tenant_id'] = template[:credentials][:tenant_id]
    credentials['availability_zone'] = template[:regions][:compute]
  rescue => e
    puts 'your credentials are not configured, delete the file %s and run forj setup again' % [creds]
    Logging.error(e.message)
  end
  credentials
end
