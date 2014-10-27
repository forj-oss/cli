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

# ForjAccount manage a list of key/value grouped by section.
# The intent of ForjAccount is to attach some keys/values to
# an account to help end users to switch between each of them.
#
# ForjAccount based on ForjConfig (see forj-config.rb)
# ensure ForjConfig and ForjAccount defines following common functions
# - set (key, value)
# - get (key)
#
# This means that key HAVE to be unique across sections
# By default, keys maps with the same key name in ForjConfig.
# But we can redefine the ForjConfig mapping of any key on need.
#
# ForjConfig, loads Account meta structure from defaults.yaml, sections
#
# defaults.yaml structure is:
# sections:
#   default: => defines key/values recognized by ForjAccount to be only managed by ForjConfig.
#     <key> :
#       :desc : <value> => defines the ForjConfig key description.
#   <section>: Define a section name. For each keys on this section, the account file will kept those data under this section.
#     <key>:
#       :desc:              defines the key description.
#       :readonly:          true if this key cannot be updated by ForjAccount.set
#       :account_exclusive: true if this key cannot be predefined on ForjConfig keys list
#       :default:           <ForjConfig real key name> Used to map the ForjAccount key to a different ForjConfig key name.

class ForjAccount

   attr_reader :sAccountName
   attr_reader :hAccountData
   attr_reader :oConfig

   # This object manage data located in oConfig[:hpc_accounts/AccountName]

   def initialize(oConfig)
      # Initialize object
      @oConfig = oConfig

      if @oConfig.get(:account_name)
         @sAccountName = @oConfig.get(:account_name)
      else
         @sAccountName = 'hpcloud'
      end
      @sAccountFile = File.join($FORJ_ACCOUNTS_PATH, @sAccountName)

      sProvider = 'hpcloud'
      sProvider = @oConfig.get(:provider) if @oConfig.get(:provider)

      @hAccountData = {}
      _set(:account, :name, @sAccountName) if exist?(:name) != 'hash'
      _set(:account, :provider, sProvider)  if exist?(:provider) != 'hash'

   end

   # oForjAccount data get at several levels:
   # - get the data from runtime (runtimeSet/runtimeGet)
   # - otherwise, get data from account file under section described in defaults.yaml (:account_section_mapping), as soon as this mapping exists.
   # - otherwise, get the data from the local configuration file. Usually ~/.forj/config.yaml
   # - otherwise, get the data from defaults.yaml
   # otherwise, use the get default parameter as value. Default is nil.
   def get(key, default = nil)
      return nil if not key

      key = key.to_sym if key.class == String

      return @oConfig.runtimeGet(key) if @oConfig.runtimeExist?(key)

      section = ForjDefault.get_meta_section(key)
      default_key = key

      if not section
         Logging.debug("ForjAccount.get: No section found for key '%s'." % [key])
      else
         return rhGet(@hAccountData, section, key) if rhExist?(@hAccountData, section, key) == 2

         hMeta = @oConfig.getAppDefault(:sections)
         if rhExist?(hMeta, section, key, :default) == 3
            default_key = rhGet(hMeta, section, key, :default)
            Logging.debug("ForjAccount.get: Reading default key '%s' instead of '%s'" % [default_key, key])
         end
         return default if rhExist?(hMeta, section, key, :account_exclusive) == 3
      end

      @oConfig.get(default_key , default )
   end

   def [](key, default = nil)
      get(key, default)
   end

   def exist?(key)
      return nil if not key

      key = key.to_sym if key.class == String
      section = ForjDefault.get_meta_section(key)
      if not section
         Logging.debug("ForjAccount.exist?: No section found for key '%s'." % [key])
         return nil
      end
      return @sAccountName if rhExist?(@hAccountData, section, key) == 2

      hMeta = @oConfig.getAppDefault(:sections)
      if rhExist?(hMeta, section, key, :default) == 3
         default_key = rhGet(hMeta, section, key, :default)
         Logging.debug("ForjAccount.exist?: Reading default key '%s' instead of '%s'" % [default_key, key])
      else
         default_key = key
      end
      return nil if rhExist?(hMeta, section, key, :account_exclusive) == 3

      @oConfig.exist?(default_key)

   end

   # Return true if readonly. set won't be able to update this value.
   # Only _set (private function) is able.
   def readonly?(key)
      return nil if not key

      key = key.to_sym if key.class == String
      section = ForjDefault.get_meta_section(key)

      rhGet(@oConfig.getAppDefault(:sections, section), key, :readonly)

   end

   def meta_set(key, hMeta)
      key = key.to_sym if key.class == String
      section = ForjDefault.get_meta_section(key)
      hCurMeta = rhGet(@oConfig.getAppDefault(:sections, section), key)
      hMeta.each { | mykey, myvalue |
         rhSet(hCurMeta, myvalue, mykey)
         }
   end

   def meta_exist?(key)
      return nil if not key

      key = key.to_sym if key.class == String
      section = ForjDefault.get_meta_section(key)
      rhExist?(@oConfig.getAppDefault(:sections, section), key) == 1
   end

   def get_meta_section(key)
      key = key.to_sym if key.class == String
      rhGet(@account_section_mapping, key)
   end

   def meta_type?(key)
      return nil if not key

      section = ForjDefault.get_meta_section(key)

      return section if section == :default
      @sAccountName
   end

   # Loop on account metadata
   def metadata_each
      rhGet(ForjDefault.dump(), :sections).each { | section, hValue |
         next if section == :default
         hValue.each { | key, value |
            yield section, key, value
            }
         }
   end

   # Return true if exclusive
   def exclusive?(key)
      return nil if not key

      key = key.to_sym if key.class == String
      section = ForjDefault.get_meta_section(key)

      rhGet(@oConfig.getAppDefault(:sections, section), key, :account_exclusive)
   end

   # This function update a section/key=value if the account structure is defined.
   # If no section is defined, set it in runtime config.
   def set(key, value)
      return nil if not key

      key = key.to_sym if key.class == String
      section = ForjDefault.get_meta_section(key)

      return @oConfig.set(key, value) if not section
      return nil if readonly?(key)
      _set(section, key, value)
   end

   def []=(key, value)
      set(key, value)
   end

   def del(key)
      return nil if not key

      key = key.to_sym if key.class == String
      section = ForjDefault.get_meta_section(key)
      return nil if not section
      rhSet(@hAccountData, nil, section, key)
   end

   def getAccountData(section, key, default=nil)
      return rhGet(@hAccountData, section, key) if rhExist?(@hAccountData, section, key) == 2
      default
   end

   def ac_new(sAccountName)
      return nil if sAccountName.nil?
      @sAccountName = sAccountName
      @sAccountFile = File.join($FORJ_ACCOUNTS_PATH, @sAccountName)

      @hAccountData = {:account => {:name => sAccountName, :provider => @oConfig.get(:provider_name)}}
   end

   def ac_load(sAccountName = @sAccountName)
      # Load Account Information

      if sAccountName != @sAccountName
         ac_new(sAccountName)
      end

      if File.exists?(@sAccountFile)
         @hAccountData = @oConfig.ExtraLoad(@sAccountFile, :forj_accounts, @sAccountName)
         # Check if hAccountData are using symbol or needs to be updated.
         sProvider = @oConfig.get(:provider, 'hpcloud')
         rhSet(@hAccountData, @sAccountName, :account, :name) if rhExist?(@hAccountData, :account, :name) != 2
         rhSet(@hAccountData, sProvider, :account, :provider) if rhExist?(@hAccountData, :account, :provider) != 2

         if rhKeyToSymbol?(@hAccountData, 2)
            @hAccountData = rhKeyToSymbol(@hAccountData, 2)
            self.ac_save()
         end
         return @hAccountData
      end
      nil
   end

   def dump()
      { :forj_account => @hAccountData }
   end

   def ac_save()
      @oConfig.ExtraSet(:forj_accounts, @sAccountName, nil, @hAccountData)
      @oConfig.ExtraSave(@sAccountFile, :forj_accounts, @sAccountName)

      if not @oConfig.LocalDefaultExist?('account_name')
         @oConfig.LocalSet('account_name',@sAccountName)
         @oConfig.SaveConfig
      end
   end

   # private functions
   private
   def _set(section, key, value)
      return nil if not key or not section

      rhSet(@hAccountData, value, section, key)
   end

end
