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

require 'encryptor' # gem install encryptor
require 'base64'

# TODO: To move to a specific module driven by providers.
require 'hpcloud/version'
require 'hpcloud/config'
require 'hpcloud/accounts'
require 'hpcloud/connection'
include HP::Cloud

#
# Setup module call the hpcloud functions
#
module Setup
   def setup(oConfig, options )

      # TODO: Provide a way to re-edit all or partially elements set up by this function.
      begin
         Logging.fatal(1, 'No provider specified.') if not oConfig.exist?('provider')

         sProvider = oConfig.get('provider')
         sAccountName = sProvider # By default, the account name uses the same provider name.
         sAccountName = options[:account_name] if options[:account_name]

         if sProvider != 'hpcloud'
            Logging.fatal(1, "forj setup support only hpcloud. '%s' is currently not supported." % sProvider)
         end

         # setting up provider account - Required, while calling external provider tool, like hpcloud.
         setup_provider_account(oConfig, sAccountName)

         # Implementation of simple credential encoding for build.sh/maestro
         save_maestro_creds(oConfig, sAccountName)

         # DNS Setting for Gardener
         setup_dns(oConfig, sAccountName)

         # Check/create keypair
         keypair_setup(oConfig)

         # Checking cloud connection
         Logging.message("Checking cloud connection")
         oFC=ForjConnection.new(oConfig)

         Logging.message("Setup '%s' done. Thank you." % sAccountName)
        
      rescue RuntimeError => e
         Logging.fatal(1,e.message)
      rescue  => e
         Logging.fatal(1,"%s\n%s" % [e.message,e.backtrace.join("\n")])
      end
  end
end

def setup_tenant_name(oConfig, sAccountName)
   # Maestro uses fog/openstack to connect to the cloud. It needs Tenant name instead of tenant ID.
   # Getting it from Compute connection and set it
   
   oSSLError=SSLErrorMgt.new # Retry object
   Logging.debug("Getting tenants from hpcloud cli libraries")
   begin
      tenants = Connection.instance.tenants(sAccountName)
   rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
      Logging.fatal(1, 'Network: Unable to connect.')
   end   
   tenant_id = rhGet(oConfig.ExtraGet(:hpc_accounts, sAccountName, :credentials), :tenant_id)
   tenant_name = nil
   tenants.each { |elem| tenant_name = elem['name'] if elem['id'] == tenant_id }
   if tenant_name
      Logging.debug("Tenant ID '%s': '%s' found." % [tenant_id, tenant_name])
      hCompute = { :tenant_name => tenant_name }
      oConfig.ExtraSet(:forj_accounts, sAccountName, :compute, hCompute)
   else
      Logging.error("Unable to find the tenant Name for '%s' ID." % tenant_id)
   end
   oConfig.set('tenants', tenants)
end

def setup_provider_account(oConfig, sAccountName)
   # TODO: Support of multiple providers thanks to fog.
   # TODO: Replace this code by our own forj account setup, inspired/derived from hpcloud account::setup

   # delegate the initial configuration to hpcloud (unix_cli)
   if File.exists?(File.join($HPC_ACCOUNTS, 'hp')) and not File.exists?(File.join($HPC_ACCOUNTS, sAccountName)) and sAccountName != 'hp'
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

   # Loading HPCloud account setting in Config.
   hpc_account_file = File.join($HPC_ACCOUNTS, sAccountName)

   # Maestro compute use openstack. It requires meta tenant_name (not ID). Need to query HPC to get the Project Name from the ID.
   oConfig.ExtraLoad(hpc_account_file, :hpc_accounts, sAccountName)

   setup_tenant_name(oConfig, sAccountName)
end

def setup_dns(oConfig, sAccountName)
   sAsk = "Optionally, you can ask Maestro to manage a Domain name. It requires your DNS cloud service to be enabled.\nDo you want to configure it?"
   if agree(sAsk)
      # Get HPCloud account definition
      yHPC = oConfig.ExtraGet(:hpc_accounts, sAccountName)

      # Get Forj account definition
      yDNS = oConfig.ExtraGet(:forj_accounts, sAccountName, :dns)
      yDNS = {} if not yDNS
      
      # Getting tenants
      tenants = oConfig.get('tenants')

      # Question about DNS Tenant ID
      # In HPCloud : credentials/tenant_id
      aDNS_TenantIDs = []
      sDNS_TenantIDs = rhGet(yDNS, :tenant_id)
      sDNS_TenantIDs = rhGet(yHPC, :credentials, :tenant_id) if not sDNS_TenantIDs and rhExist?(yHPC, :credentials, :tenant_id) > 0

      Logging.message("Following are the list of know project attached to your credentials:")
      tenants.each do | elem | 
         aDNS_TenantIDs.push(elem['id'])
         if sDNS_TenantIDs and elem['id'] == sDNS_TenantIDs
            Logging.message("%s - %s" % [ANSI.bold+elem['id']+ANSI.reset, elem['name']])
         else
            Logging.message("%s - %s" % [elem['id'], elem['name']])
         end   
      end

      sOption = ' [%s]' % aDNS_TenantIDs.join(', ') if aDNS_TenantIDs.length() == 2
      sDNS_TenantID = ask('Enter DNS Tenant ID:%s' % sOption) do |q|
         q.default = sDNS_TenantIDs
         q.validate = /[\w\d]+/
      end
      yDNS[:tenant_id] = sDNS_TenantID.to_s

      # Question about DNS Service
      # In HPCloud : regions/dns
      if sDNS_TenantID == rhGet(yHPC, :credentials, :tenant_id)
         sDNS_Service = rhGet(yHPC, :regions, :dns)
      else   
         aDNS_Services = []
         aDNS_Services.push(rhGet(yDNS, :service)) if rhExist?(yDNS, :service) > 0
      
         sDNS_Service = ask("Enter DNS Service for the Tenant ID '%s' (ex: region-a.geo-1): " % sDNS_TenantID) do |q|
            q.validate = /[\w.-]+/
         end
      end
      yDNS[:service] = sDNS_Service.to_s

   else
      yDNS = {} # Any information about DNS setting is removed.
      Logging.message("Maestro won't manage any Domain.")
   end
   # Question about Domain name
   previousDomainName = rhGet(yDNS, :domain_name) if rhExist?(yDNS, :domain_name) > 0

   sDNS_DomainName = ask('Enter Domain name (puppet requirement) (ex: dev.forj.io):') do |q|
      q.default = previousDomainName if previousDomainName
      q.validate = /[\w._]+/
   end
   yDNS[:domain_name] = sDNS_DomainName.to_s

   oConfig.ExtraSet(:forj_accounts, sAccountName, :dns, yDNS)
   forjAccountFile = File.join($FORJ_ACCOUNTS_PATH, sAccountName)
   oConfig.ExtraSave(forjAccountFile, :forj_accounts, sAccountName)
end

def ensure_forj_dirs_exists()
  # Function to create FORJ paths if missing.

  # Defining Global variables
  $FORJ_DATA_PATH = File.expand_path(File.join('~', '.forj'))
  $FORJ_ACCOUNTS_PATH = File.join($FORJ_DATA_PATH, 'accounts') 
  $FORJ_KEYPAIRS_PATH = File.join($FORJ_DATA_PATH, 'keypairs')
  $FORJ_CREDS_PATH = File.expand_path(File.join('~', '.cache', 'forj'))

  # TODO: To move to an hpcloud object.
  $HPC_KEYPAIRS = File.expand_path(File.join('~', '.hpcloud', 'keypairs'))
  $HPC_ACCOUNTS = File.expand_path(File.join('~', '.hpcloud', 'accounts'))

  Helpers.ensure_dir_exists($FORJ_DATA_PATH)
  Helpers.ensure_dir_exists($FORJ_ACCOUNTS_PATH)
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


def save_maestro_creds(oConfig, sAccountName)
   # Check required global data
   if not $FORJ_CREDS_PATH
      Logging.fatal(1, "Internal error: '$FORJ_CREDS_PATH' missing.")
   end
   if not Helpers.dir_exists?($FORJ_CREDS_PATH)
      Logging.fatal(1, "Internal error: '%s' doesn't exist." % $FORJ_CREDS_PATH)
   end

   Logging.info("Completing hpcloud account '%s' information." % [sAccountName] )

   forjAccountFile = File.join($FORJ_ACCOUNTS_PATH, sAccountName)
   oConfig.ExtraLoad(forjAccountFile, :forj_accounts, sAccountName)

   forj_user = rhGet(oConfig.ExtraGet(:forj_accounts, sAccountName, :credentials), :os_user)

   hpcloud_os_user = ask('Enter hpcloud username: ') do |q|
      q.validate = /\w+/
      q.default = forj_user if forj_user
   end

   hpcloud_os_key = ask("Enter hpcloud password for '%s': " % hpcloud_os_user) do |q|
      q.echo = '*'
      q.validate = /.+/
   end

   # Checking key file used to encrypt/decrypt passwords
   key_file = File.join($FORJ_CREDS_PATH, '.key')
   if not File.exists?(key_file)
      # Need to create a random key.
      entr = { :key => rand(36**10).to_s(36), :salt => Time.now.to_i.to_s, :iv => OpenSSL::Cipher::Cipher.new('aes-256-cbc').random_iv}

      Logging.debug("Writing '%s' key file" % key_file)
      File.open(key_file, 'w') do |out|
         out.write(Base64::encode64(entr.to_yaml))
      end
   else
      Logging.debug("Loading '%s' key file" % key_file)
      encoded_key = IO.read(key_file)
      entr = YAML.load(Base64::decode64(encoded_key))
   end
   enc_hpcloud_os_key = Base64::strict_encode64(Encryptor.encrypt(:value => hpcloud_os_key, :key => entr[:key], :iv => entr[:iv], :salt => entr[:salt]))

   cloud_fog = File.join($FORJ_CREDS_PATH, sAccountName+'.g64')

   # Security fix: Remove old temp file with clear password.
   old_file = '%s/master.forj-13.5' % [$FORJ_CREDS_PATH]
   File.delete(old_file) if File.exists?(old_file)
   old_file = '%s/creds' % [$FORJ_CREDS_PATH]
   File.delete(old_file) if File.exists?(old_file)

   hpc_creds = oConfig.ExtraGet(:hpc_accounts, sAccountName, :credentials)

   forj_creds = { :os_user => hpcloud_os_user.to_s,
                  :os_enckey => enc_hpcloud_os_key
                }
   oConfig.ExtraSet(:forj_accounts, sAccountName, :credentials, forj_creds)
   oConfig.ExtraSave(forjAccountFile, :forj_accounts, sAccountName)

   IO.popen('gzip -c | base64 -w0 > %s' % [cloud_fog], 'r+') {|pipe|
      pipe.puts('HPCLOUD_OS_USER=%s' % [hpcloud_os_user] )
      pipe.puts('HPCLOUD_OS_KEY=%s' % [hpcloud_os_key] )
      pipe.puts('DNS_KEY=%s' % [hpc_creds[:account_id]] )
      pipe.puts('DNS_SECRET=%s' % [hpc_creds[:secret_key]])
      pipe.close_write
   }
   Logging.info("'%s' written." % cloud_fog)
end
