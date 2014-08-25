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

      Logging.fatal(1, 'No provider specified.') if not sProvider

      sAccountName = sProvider # By default, the account name uses the same provider name.
      sAccountName = options[:account_name] if options[:account_name]

      if sProvider != 'hpcloud'
         Logging.fatal(1, "forj setup support only hpcloud. '%s' is currently not supported." % sProvider)
      end

      # TODO: Support of multiple providers thanks to fog.
      # TODO: Replace this code by our own forj account setup, inspired/derived from hpcloud account::setup

      # delegate the initial configuration to hpcloud (unix_cli)
      hpcloud_data=File.expand_path('~/.hpcloud/accounts')
      if File.exists?(File.join(hpcloud_data, 'hp')) and not File.exists?(File.join(hpcloud_data, sAccountName)) and sAccountName != 'hp'
         Logging.info("hpcloud: Copying 'hp' account setup to '%s'" % sAccountName)
         Kernel.system('hpcloud account:copy hp %s' % [sAccountName])
      end

      Logging.info("Configuring hpcloud account '%s'" % [sAccountName] )
      command = 'hpcloud account:setup %s' % [sAccountName]
      Logging.debug("Executing : '%s'" % command)
      case Kernel.system(command)
         when false
           Logging.fatal(1, "Unable to setup your hpcloud account")
         when nil
           Logging.fatal(1, "Unable to execute 'hpcloud' cli. Please check hpcloud installation.")
      end

      if not oConfig.yConfig['default'].has_key?('account')
         oConfig.LocalSet('account',sAccountName)
         oConfig.SaveConfig
      end

      # Implementation of simple credential encoding for build.sh/maestro
      save_maestro_creds(sAccountName)
      
      # Check/create keypair
      keypair_setup(oConfig)
      
    rescue RuntimeError => e
      Logging.fatal(1,e.message)
    rescue  => e
      Logging.fatal(1,"%s\n%s" % [e.message,e.backtrace.join("\n")])
    end
  end
end

def ensure_forj_dirs_exists()
  # Function to create FORJ paths if missing.

  # Defining Global variables
  $FORJ_DATA_PATH = File.expand_path(File.join('~', '.forj'))
  $FORJ_ACCOUNT_PATH = File.join($FORJ_DATA_PATH, 'account') # Not currently used...
  $FORJ_KEYPAIRS_PATH = File.join($FORJ_DATA_PATH, 'keypairs')
  $FORJ_CREDS_PATH = File.expand_path(File.join('~', '.cache', 'forj'))
  
  # TODO: To move to an hpcloud object.
  $HPC_KEYPAIRS = File.expand_path(File.join('~', '.hpcloud', 'keypairs'))

  Helpers.ensure_dir_exists($FORJ_DATA_PATH)
  Helpers.ensure_dir_exists($FORJ_ACCOUNT_PATH)
  Helpers.ensure_dir_exists($FORJ_KEYPAIRS_PATH)
  Helpers.ensure_dir_exists($FORJ_CREDS_PATH)
end
  
def keypair_setup(oConfig)

   key_path = oConfig.get('keypair_path')

   Logging.info("Configuring forj keypair '%s'" % [key_path] )

   if not File.exists?(key_path)
      # Need to create a key. ask if we need so.
      real_key_path = File.expand_path(ask("If your ssh keypair doesn't exist, forj will ask ssh-keygen to create one for you.\nPrivate key file path:") do |q|
         q.validate = /\w+/
         q.default = key_path
      end)
      if not File.exists?(real_key_path)
         Helpers.ensure_dir_exists(File.dirname(real_key_path))
         command = 'ssh-keygen -t rsa -f %s' % real_key_path
         Logging.debug("Executing '%s'" % command)
         system(command)
      end
      if not File.exists?(real_key_path)
         Logging.fatal(1, "'%s' not found. Unable to add your keypair to hpcloud. Create it yourself and provide it with -p option. Then retry." % [real_key_path])
      else
         if real_key_path != key_path and not oConfig.LocalDefaultExist?('keypair_path')
            Logging.debug("Saving forj keypair '%s' as default." % [real_key_path] )
            oConfig.LocalSet('keypair_path', real_key_path)
            oConfig.SaveConfig()
         end   
      end
   end
end


def save_maestro_creds(sAccountName)
  # Check required global data
  if not $FORJ_CREDS_PATH
     Logging.fatal(1, "Internal error: '$FORJ_CREDS_PATH' missing.")
  end
  if not Helpers.dir_exists?($FORJ_CREDS_PATH)
     Logging.fatal(1, "Internal error: '%s' doesn't exist." % $FORJ_CREDS_PATH)
  end

  Logging.info("Completing hpcloud account '%s' information." % [sAccountName] )

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

  cloud_fog = File.join($FORJ_CREDS_PATH, sAccountName+'.g64')

  # Security fix: Remove old temp file with clear password.
  old_file = '%s/master.forj-13.5' % [$FORJ_CREDS_PATH]
  File.delete(old_file) if File.exists?(old_file)
  old_file = '%s/creds' % [$FORJ_CREDS_PATH]
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
