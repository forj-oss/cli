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
require 'highline/import'

require_relative 'yaml_parse.rb'
include YamlParse

#
# Setup module call the hpcloud functions
#
module Setup
  def setup
    # delegate the initial configuration to hpcloud (unix_cli)
    Kernel.system('hpcloud account:setup')
    setup_credentials
    save_cloud_fog
    #Kernel.system('hpcloud keypairs:add nova')
  end
end

def setup_credentials
  puts 'Enter hpcloud username: '
  hpcloud_os_user = ask('Enter hpcloud username: ')
  hpcloud_os_key = ask('Enter hpcloud password: ') { |q| q.echo = '*'}

  home = File.expand_path('~')
  creds = '%s/.cache/forj/creds' % [home]
  File.open(creds, 'w') {|file|
    file.write('HPCLOUD_OS_USER=%s' % [hpcloud_os_user])
    file.write("\n")
    file.write('HPCLOUD_OS_KEY=%s' % [hpcloud_os_key])
  }
end


def save_cloud_fog
  home = File.expand_path('~')

  cloud_fog = '%s/.cache/forj/master.forj-13.5' % [home]
  local_creds = '%s/.cache/forj/creds' % [home]

  creds = '%s/.hpcloud/accounts/hp' % [home]
  template = YAML.load_file(creds)
  local_template = YAML.load_file(local_creds)


  access_key = template[:credentials][:account_id]
  secret_key = template[:credentials][:secret_key]

  os_user = local_template['HPCLOUD_OS_USER']
  os_key = local_template['HPCLOUD_OS_KEY']

  File.open(cloud_fog, 'w') {|file|
    file.write('HPCLOUD_OS_USER=%s' % [os_user])
    file.write('HPCLOUD_OS_KEY=%s' % [os_key])
    file.write('DNS_KEY=%s' % [access_key])
    file.write('DNS_SECRET=%s' % [secret_key])
  }

  command = 'cat  %s | gzip -c | base64 -w0 > %s.g64' % [cloud_fog, cloud_fog]
  Kernel.system(command)
end