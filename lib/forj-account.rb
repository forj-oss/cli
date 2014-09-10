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
require 'highline/import'

require 'yaml_parse.rb'
include YamlParse
require 'helpers.rb'
include Helpers

require 'encryptor' # gem install encryptor
require 'base64'

# TODO: To move to a specific module driven by providers.
require 'hpcloud/version'
require 'hpcloud/config'
require 'hpcloud/accounts'
require 'hpcloud/connection'
include HP::Cloud

class ForjAccounts
   # Class to query FORJ Accounts list.
   def initialize()
   end

   def dump()
      aAccounts=[]
      Dir.foreach($FORJ_ACCOUNTS_PATH) { |x| aAccounts << x if not x.match(/^\..?$/) }
      aAccounts
   end
end

class ForjAccount

   attr_reader :sAccountName
   attr_reader :hAccountData

   # This object manage data located in oConfig[:hpc_accounts/AccountName]

   def initialize(oConfig)
      # Initialize object
      @oConfig = oConfig

      if @oConfig.get('account_name')
         @sAccountName = @oConfig.get('account_name')
      else
         @sAccountName = 'hpcloud'
      end
      @sAccountFile = File.join($FORJ_ACCOUNTS_PATH, @sAccountName)

      sProvider = 'hpcloud'
      sProvider = @oConfig.get(:provider) if @oConfig.get(:provider)

      @hAccountData = {}
      rhSet(@hAccountData, @sAccountName, [:account, :name]) if rhExist?(@hAccountData, [:account, :name]) != 2
      rhSet(@hAccountData, sProvider, [:account, :provider]) if rhExist?(@hAccountData, [:account, :provider]) != 2
   end

   # oForjAccount data get are retrieved from the account file under section described in defaults.yaml (:account_section_mapping), as soon as this mapping exists.
   # If not found, get the data from the local configuration file. Usually ~/.forj/config.yaml
   # If not found, get the data from defaults.yaml
   # otherwise, use the get default parameter as value. Default is nil.
   def get(key, default = nil)
      return nil if not key

      section = rhGet(@oConfig.getAppDefault(:account_section_mapping, key), :section)
      yInterm = nil
      yInterm = rhGet(@hAccountData, section) if section
      @oConfig.get(key, yInterm , default )
   end

   def exist?(key)
      return nil if not key

      section = rhGet(@oConfig.getAppDefault(:account_section_mapping, key), :section)
      yInterm = nil
      yInterm = rhGet(@hAccountData, section) if section
      @oConfig.exist?(key, yInterm)

   end

   def set(key, value)
      return nil if not key

      section = rhGet(@oConfig.getAppDefault(:account_section_mapping, key), :section)
      return nil if not section
      rhSet(@hAccountData, value, section, key)
   end

   def del(key)
      return nil if not key

      section = rhGet(@oConfig.getAppDefault(:account_section_mapping, key), :section)
      return nil if not section
      rhSet(@hAccountData, nil, section, key)
   end

   def getAccountData(section, key, default=nil)
      return rhGet(@hAccountData, section, key) if rhExist?(@hAccountData, section, key) == 2
      default
   end

   def ac_load(sAccountName = @sAccountName)
      # Load Account Information

      if sAccountName != @sAccountName
         @sAccountName = sAccountName
         @sAccountFile = File.join($FORJ_ACCOUNTS_PATH, @sAccountName)
      end

      if File.exists?(@sAccountFile)
         @hAccountData = @oConfig.ExtraLoad(@sAccountFile, :forj_accounts, @sAccountName)
         sProvider = @oConfig.get(:provider, nil, 'hpcloud')
         rhSet(@hAccountData, @sAccountName, :account, :name) if rhExist?(@hAccountData, :account, :name) != 2
         rhSet(@hAccountData, sProvider, :account, :provider) if rhExist?(@hAccountData, :account, :provider) != 2
         provider_load()
         return @hAccountData
      end
      nil
   end

   def dump()
      { :forj_account => @hAccountData, :hpc_account => provider_load() }
   end

   def ac_save()
      @oConfig.ExtraSet(:forj_accounts, @sAccountName, nil, @hAccountData)
      @oConfig.ExtraSave(@sAccountFile, :forj_accounts, @sAccountName)

      if not @oConfig.LocalDefaultExist?('account_name')
         @oConfig.LocalSet('account_name',@sAccountName)
         @oConfig.SaveConfig
      end
   end

   def setup()
      # Full setup to make it work.

      # setting up provider account - Required, while calling external provider tool, like hpcloud.
      self.setup_provider_account()

      # Implementation of simple credential encoding for build.sh/maestro
      self.setup_maestro_creds()

      # DNS Setting for Gardener
      self.setup_dns()

      # Check/create keypair
      self.keypair_setup()

      # Checking cloud connection
      Logging.message("Checking cloud connection")
      ForjConnection.new(@oConfig)

      Logging.message("Setup '%s' done. Thank you." % @sAccountName)
   end

   def setup_provider_account()
      # TODO: Support of multiple providers thanks to fog.
      # TODO: Replace this code by our own forj account setup, inspired/derived from hpcloud account::setup

      # delegate the initial configuration to hpcloud (unix_cli)
      if File.exists?(File.join($HPC_ACCOUNTS, 'hp')) and not File.exists?(File.join($HPC_ACCOUNTS, @sAccountName)) and @sAccountName != 'hp'
         Logging.info("hpcloud: Copying 'hp' account setup to '%s'" % @sAccountName)
         Kernel.system('hpcloud account:copy hp %s' % [@sAccountName])
      end

      Logging.info("Configuring hpcloud account '%s'" % [@sAccountName] )
      command = 'hpcloud account:setup %s' % [@sAccountName]
      Logging.debug("Executing : '%s'" % command)
      case Kernel.system(command)
         when false
           Logging.fatal(1, "Unable to setup your '%s' account" % [@sAccountName])
         when nil
           Logging.fatal(1, "Unable to execute 'hpcloud' cli. Please check hpcloud installation.")
      end

      provider_load() # To ensure latest provider data are loaded

      setup_tenant_name()
   end

   def provider_load()
      # TODO: Should be provider agnostic
      # Loading HPCloud account setting in Config.
      hpc_account_file = File.join($HPC_ACCOUNTS, @sAccountName)

      # Maestro compute use openstack. It requires meta tenant_name (not ID). Need to query HPC to get the Project Name from the ID.
      @oConfig.ExtraLoad(hpc_account_file, :hpc_accounts, @sAccountName)
   end

   # Maestro uses fog/openstack to connect to the cloud. It needs Tenant name instead of tenant ID.
   # Getting it from Compute connection and set it
   def setup_tenant_name()
      oSSLError=SSLErrorMgt.new # Retry object
      Logging.debug("Getting tenants from hpcloud cli libraries")
      begin
         tenants = Connection.instance.tenants(@sAccountName)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
         Logging.fatal(1, 'Network: Unable to connect.')
      end
      tenant_id = rhGet(@oConfig.ExtraGet(:hpc_accounts, @sAccountName, :credentials), :tenant_id)
      tenant_name = nil
      tenants.each { |elem| tenant_name = elem['name'] if elem['id'] == tenant_id }
      if tenant_name
         Logging.debug("Tenant ID '%s': '%s' found." % [tenant_id, tenant_name])
         hCompute = { :tenant_name => tenant_name }
         rhSet(@hAccountData, hCompute, :compute)
      else
         Logging.error("Unable to find the tenant Name for '%s' ID." % tenant_id)
      end
      @oConfig.set('tenants', tenants)
   end

   # Setting up DNS information
   def setup_dns()
      # Get HPCloud account definition
      yHPC = @oConfig.ExtraGet(:hpc_accounts, @sAccountName)
      # Get Forj account definition
      yDNS = rhGet(@hAccountData, :dns)
      yDNS = {} if not yDNS

      sAsk = "Optionally, you can ask Maestro to use/manage a domain name on your cloud. It requires your DNS cloud service to be enabled.\nDo you want to configure it?"
      if agree(sAsk)
         # Getting tenants
         tenants = @oConfig.get('tenants')

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
         yDNS.delete(:service)
         yDNS.delete(:tenant_id)
         Logging.message("Maestro won't manage any Domain with '%s' provider." % [ rhGet(@hAccountData, [:account, :provider])])
      end
      # Question about Domain name
      previousDomainName = rhGet(yDNS, :domain_name) if rhExist?(yDNS, :domain_name) > 0

      sDNS_DomainName = ask('Enter Domain name to add to hostnames (puppet requirement) (ex: dev.forj.io):') do |q|
         q.default = previousDomainName if previousDomainName
         q.validate = /[\w._]+/
      end
      yDNS[:domain_name] = sDNS_DomainName.to_s

      # Attaching to the account.
      rhSet(@hAccountData, yDNS, :dns)
   end

   # manage keypair attached to a FORJ account.
   def keypair_setup()

      # Getting Account keypair information
      yCreds = rhGet(@hAccountData, :credentials)
      key_name = @oConfig.get('keypair_name', yCreds )
      orig_key_path = File.expand_path(@oConfig.get('keypair_path', yCreds))

      Logging.warning("'keypair_path' is missing at least from defaults.yaml. To fix it, set it in your configuration file ~/.forj/config.yaml under default section") if not orig_key_path
      key_path = nil
      while not key_path
         key_path = ask ("Please provide the SSH private key path used by default on this account:") do | q |
            q.default = orig_key_path
            q.validate = /.*+/
         end
         keys_entered = keypair_detect(key_name, key_path)
         if not keys_entered[:private_key_exist?] and not keys_entered[:public_key_exist?]
            if agree("The key you entered was not found. Do you want to create this one?")
               base_dir = File.dirname(keys_entered[:keypair_path])
               if File.directory?(base_dir)
                  if agree("'%s' doesn't exist. Do you want to create it?")
                     ensure_forj_dirs_exists(base_dir)
                  end
               end
            else
               key_path = nil
            end
         end
      end
      keys_imported = nil
      keys_imported = keypair_detect(key_name, @oConfig.LocalGet(key_name, :imported_keys)) if @oConfig.LocalExist?(key_name, :imported_keys)

      if keys_imported and keys_imported[:key_basename] != keys_entered[:key_basename] and $FORJ_KEYPAIRS_PATH != keys_entered[:keypair_path]
         Logging.warning("The private key '%s' was imported from a different private key file '%s'.\nTo not overwrite it, we recommend you to choose a different keypair name." % [key_name, sImportedKey])
         key_name = nil
      end

      key_name = ask ("Please provide the keypair name used by default on this account:") do | q |
         q.default = key_name
         q.validate = /.*+/
      end
      key_name = key_name.to_s

      keys = keypair_detect(key_name, key_path)

      Logging.info("Configuring forj keypair '%s'" % [ keys[:keypair_name] ] )


      private_key_file = File.join(keys[:keypair_path], keys[:private_key_name])
      public_key_file = File.join(keys[:keypair_path], keys[:public_key_name])


      # Creation sequences
      if not keys[:private_key_exist?]
         # Need to create a key. ask if we need so.
         Logging.message("Private key file '%s' was not found. forj will propose to create one for you. Please review the proposed private key file name and path.\nYou can press Enter to accept the default value." % keys[:private_key_path])
         real_key_path = File.expand_path(ask("Private key file path:") do |q|
            q.validate = /\w+/
            q.default = private_key_file
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
            if real_key_path != key_path and not @oConfig.LocalDefaultExist?('keypair_path')
               Logging.debug("Saving forj keypair '%s' as default." % [real_key_path] )
               @oConfig.LocalSet('keypair_path', real_key_path)
               @oConfig.SaveConfig()
            end
         end
      end

      if not keys[:public_key_exist?]
         Logging.message("Your public key '%s' was not found. Getting it from the private one. It may require your passphrase." % [public_key_file])
         command = 'ssh-keygen -y -f %s > %s' % [private_key_file,public_key_file ]
         Logging.debug("Executing '%s'" % command)
         system(command)
      end

      forj_private_key_file = File.join($FORJ_KEYPAIRS_PATH, key_name )
      forj_public_key_file = File.join($FORJ_KEYPAIRS_PATH, key_name + ".pub")

      # Saving sequences
      if keys[:keypair_path] != $FORJ_KEYPAIRS_PATH
         if not File.exists?(forj_private_key_file)
            Logging.info("Importing key pair to FORJ keypairs list.")
            FileUtils.copy(private_key_file, forj_private_key_file)
            FileUtils.copy(public_key_file, forj_public_key_file)
            # Attaching this keypair to the account
            rhSet(@hAccountData, key_name, :credentials, 'keypair_name')
            rhSet(@hAccountData, forj_private_key_file, :credentials, 'keypair_path')
            @oConfig.LocalSet(key_name.to_s, private_key_file, :imported_keys)
            @oConfig.SaveConfig()
         end
      end
   end

   def setup_maestro_creds()
      # Check required global data
      if not $FORJ_CREDS_PATH
         Logging.fatal(1, "Internal error: '$FORJ_CREDS_PATH' missing.")
      end
      if not Helpers.dir_exists?($FORJ_CREDS_PATH)
         Logging.fatal(1, "Internal error: '%s' doesn't exist." % $FORJ_CREDS_PATH)
      end

      Logging.info("Completing hpcloud account '%s' information." % [@sAccountName] )

      forj_user = rhGet(@hAccountData, :credentials, :os_user)
      enc_hpcloud_os_key = rhGet(@hAccountData, :credentials, :os_enckey)

      hpcloud_os_user = ask('Enter hpcloud username: ') do |q|
         q.validate = /\w+/
         q.default = forj_user if forj_user
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

      if enc_hpcloud_os_key
         hpcloud_os_key_hidden = '*' * Encryptor.decrypt(
             :value => Base64::strict_decode64(enc_hpcloud_os_key),
             :key   => entr[:key],
             :iv    => entr[:iv],
             :salt  => entr[:salt]
            ).length
         hpcloud_os_key_hidden="[%s]" % hpcloud_os_key_hidden
         Logging.message("A password is already set for '%s'. If you want to keep it, just press Enter" %  [hpcloud_os_user])
      else
         hpcloud_os_key_hidden = ""
      end

      hpcloud_os_key = ""
      while hpcloud_os_key == ""
         # ask for password.
         hpcloud_os_key = ask("Enter hpcloud password for '%s': %s" % [hpcloud_os_user, hpcloud_os_key_hidden]) do |q|
            q.echo = '*'
         end
         if hpcloud_os_key == "" and enc_hpcloud_os_key
            hpcloud_os_key = Encryptor.decrypt(:value => Base64::strict_decode64(enc_hpcloud_os_key), :key => entr[:key], :iv => entr[:iv], :salt => entr[:salt])
         else
            Logging.message("The password cannot be empty.") if hpcloud_os_key == ""
         end
      end
      enc_hpcloud_os_key = Base64::strict_encode64(Encryptor.encrypt(:value => hpcloud_os_key, :key => entr[:key], :iv => entr[:iv], :salt => entr[:salt]))

      cloud_fog = File.join($FORJ_CREDS_PATH, @sAccountName+'.g64')

      # Security fix: Remove old temp file with clear password.
      old_file = '%s/master.forj-13.5' % [$FORJ_CREDS_PATH]
      File.delete(old_file) if File.exists?(old_file)
      old_file = '%s/creds' % [$FORJ_CREDS_PATH]
      File.delete(old_file) if File.exists?(old_file)

      provider_load() if not @oConfig.ExtraExist?(:hpc_accounts, @sAccountName)
      hpc_creds = @oConfig.ExtraGet(:hpc_accounts, @sAccountName, :credentials)

      rhSet(@hAccountData, hpcloud_os_user.to_s, :credentials, :os_user)
      rhSet(@hAccountData, enc_hpcloud_os_key, :credentials, :os_enckey)

      IO.popen('gzip -c | base64 -w0 > %s' % [cloud_fog], 'r+') {|pipe|
         pipe.puts('HPCLOUD_OS_USER=%s' % [hpcloud_os_user] )
         pipe.puts('HPCLOUD_OS_KEY=%s' % [hpcloud_os_key] )
         pipe.puts('DNS_KEY=%s' % [hpc_creds[:account_id]] )
         pipe.puts('DNS_SECRET=%s' % [hpc_creds[:secret_key]])
         pipe.close_write
      }
      Logging.info("'%s' written." % cloud_fog)
   end
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
  FileUtils.chmod(0700, $FORJ_KEYPAIRS_PATH)
  Helpers.ensure_dir_exists($FORJ_CREDS_PATH)
end
