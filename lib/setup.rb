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
require_relative 'helpers.rb'
include Helpers

#
# Setup module call the hpcloud functions
#
module Setup
  def setup(sProvider, oConfig, options )
    begin

      raise 'No provider specified.' if not sProvider

      sAccountName = sProvider # By default, the account name uses the same provider name.
      sAccountName = options[:account_name] if options[:account_name]

      if sProvider != 'hpcloud'
         raise "forj setup support only hpcloud. '%s' is currently not supported." % sProvider
      end

      # TODO: Support of multiple providers thanks to fog.
      # TODO: Replace this code by our own forj account setup, inspired/derived from hpcloud account::setup

      # delegate the initial configuration to hpcloud (unix_cli)
      hpcloud_data=File.expand_path('~/.hpcloud/accounts')
      if File.exists?(File.join(hpcloud_data, 'hp')) and not File.exists?(File.join(hpcloud_data, sAccountName)) and sAccountName != 'hp'
         Logging.info("hpcloud: Copying 'hp' account setup to '%s'" % sAccountName)
         Kernel.system('hpcloud account:copy hp %s' % [sAccountName])
      end

      case Kernel.system('hpcloud account:setup %s' % [sAccountName] )
         when false
           raise "Unable to setup your hpcloud account"
         when nil
           raise "Unable to execute 'hpcloud' cli. Please check hpcloud installation."
      end

      if not oConfig.yConfig['default'].has_key?('account')
         oConfig.LocalSet('account',sAccountName)
         oConfig.SaveConfig
      end

      # Implementation of simple credential encoding for build.sh/maestro
      save_maestro_creds(sAccountName)
    rescue RuntimeError => e
      Logging.fatal(1,e.message)
    rescue  => e
      Logging.fatal(1,"%s\n%s" % [e.message,e.backtrace.join("\n")])
    end
  end
end

def save_maestro_creds(sAccountName)

  # TODO Be able to load the previous username if the g64 file exists.
  hpcloud_os_user = ask('Enter hpcloud username: ') do |q|
    q.validate = /\w+/
    q.default = ''
  end

  hpcloud_os_key = ask('Enter hpcloud password: ') do |q|
    q.echo = '*'
    q.validate = /.+/
  end

  add_creds = {:credentials => {:hpcloud_os_user=> hpcloud_os_user, :hpcloud_os_key=> hpcloud_os_key}}

  sForjCache=File.expand_path('~/.cache/forj/')
  cloud_fog = '%s/%s.g64' % [sForjCache, sAccountName]


  Helpers.create_directory(sForjCache) if not File.directory?(sForjCache)

  # Security fix: Remove old temp file with clear password.
  old_file = '%s/master.forj-13.5' % [sForjCache]
  File.delete(old_file) if File.exists?(old_file)
  old_file = '%s/creds' % [sForjCache]
  File.delete(old_file) if File.exists?(old_file)

  hpcloud_creds = File.expand_path('~/.hpcloud/accounts/%s' % [sAccountName])
  creds = YAML.load_file(hpcloud_creds)

  access_key = creds[:credentials][:account_id]
  secret_key = creds[:credentials][:secret_key]

  os_user = add_creds[:credentials][:hpcloud_os_user]
  os_key = add_creds[:credentials][:hpcloud_os_key]

  IO.popen('gzip -c | base64 -w0 > %s' % [cloud_fog], 'r+') {|pipe|
    pipe.puts('HPCLOUD_OS_USER=%s' % [os_user] )
    pipe.puts('HPCLOUD_OS_KEY=%s' % [os_key] )
    pipe.puts('DNS_KEY=%s' % [access_key] )
    pipe.puts('DNS_SECRET=%s' % [secret_key])
    pipe.close_write
  }
  Logging.info("'%s' written." % cloud_fog)
end
