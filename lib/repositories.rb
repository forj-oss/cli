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
require 'git'
require 'fileutils'
require 'require_relative'

require_relative 'yaml_parse.rb'
include YamlParse
#require_relative 'log.rb'
#include Logging

#
# Repositories module
#

# Current version of the infra. Compatible with forj version or higher.
INFRA_VERSION = "37"

module Repositories
  def clone_repo(maestro_url)
      current_dir = Dir.pwd

      home = File.expand_path('~')
      path = home + '/.forj/'

      begin
        if File.directory?(path)
          if File.directory?(path + 'maestro')
            FileUtils.rm_r path + 'maestro'
          end
          Git.clone(maestro_url, 'maestro', :path => path)
        end
      rescue => e
        Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
        puts 'Error while cloning the repo from %s' % [maestro_url]
        puts 'If this error persist you could clone the repo manually in ~/.forj/'
      end
      Dir.chdir(current_dir)
  end



   def create_infra(maestro_repo)
      # Build our own infra from maestro infra templates.
      infra = File.join($FORJ_DATA_PATH, 'infra')
      dest_cloud_init = File.join(infra, 'cloud-init')
      template = File.join(maestro_repo, 'templates', 'infra')
      cloud_init = File.join(template, 'cloud-init')

      if File.directory?(infra)
         Logging.debug("Cleaning up '%s'" % [infra])
         FileUtils.rm_r(infra)
      end
      Helpers.ensure_dir_exists(dest_cloud_init)
      Logging.debug("Copying recursively '%s' to '%s'" % [cloud_init, infra])
      FileUtils.copy_entry(cloud_init, dest_cloud_init)

      build_env = File.join(template,'maestro.box.master.env')
      Logging.debug("Copying '%s' to '%s'" % [build_env, infra])
      FileUtils.copy(build_env, infra)
      
      file_ver = File.join(infra, 'forj-cli.ver')
      File.write(file_ver, $INFRA_VERSION)
   end
  
   def infra_rebuild_required?(oConfig, infra_dir)
      # This function check if the current infra is compatible with current gem version.
      
      # prior 0.0.37 - Use a template file of build env file.
      # 0.0.37 - Using a generic version of build env file, fully managed by forj cli.
      return false if not File.exists?(infra_dir)
      
      if infra_dir != File.join($FORJ_DATA_PATH, 'infra') 
         # Do not take care. We do not manage it, ourself.
         return false
      end

      file_ver = File.join(infra_dir, 'forj-cli.ver')
      forj_infra_version = nil
      forj_infra_version = File.read(file_ver) if File.exist?(file_ver)

      if forj_infra_version
         case forj_infra_version
            when $INFRA_VERSION
               return false
            else
               old_infra_data_update(oConfig, forj_infra_version, infra_dir)
         end
      else # Prior version 37
         old_infra_data_update(oConfig, 36, infra_dir)
      end   
      true
   end
   
   def old_infra_data_update(oConfig, version, infra_dir)
      Logging.info("Migrating your local infra repo to the latest version.")
   # Supporting old version.
      case version
         when 36
            # Moving from 0.0.36 or less to 0.0.37 or higher.
            # SET_COMPUTE="{SET_COMPUTE!}" => Setting for Compute. ignored. Coming from HPC
            # SET_TENANT_NAME="{SET_TENANT_NAME!}" => Setting for Compute. ignored. Need to query HPC from current Tenant ID

            # SET_DNS_TENANTID="{SET_DNS_TENANTID!}" => Setting for DNS. meta = dns_tenantid
            #  ==> :forj_accounts, sAccountName, :dns, :tenant_id

            # SET_DNS_ZONE="{SET_DNS_ZONE!}" => Setting for DNS. meta = dns_zone
            # ==> :forj_accounts, sAccountName, :dns, :service

            # SET_DOMAIN="{SET_DOMAIN!}" => Setting for Maestro (required) and DNS if enabled. 
            # ==> :forj_accounts, sAccountName, :dns, :domain_name
            sAccountName = oConfig.get('account_name')

            yDns = {}
            yDns = oConfig.ExtraGet(:forj_accounts, sAccountName, :dns) if oConfig.ExtraExist?(:forj_accounts, sAccountName, :dns)
            build_env = File.join(infra_dir, 'maestro.box.master.env')
            Logging.debug("Reading data from '%s'" % build_env)
            tags = {'SET_DNS_TENANTID' => :tenant_id,
                    'SET_DNS_ZONE' => :service,
                    'SET_DOMAIN' => :domain_name
                   }
            begin
               bUpdate = nil

               File.open(build_env) do |f|
                  f.each_line do |line|
                     mObj = line.match(/^(SET_[A-Z_]+)=["'](.*)["'].*$/)
                     if mObj
                        Logging.debug("Reviewing detected '%s' tag" % [mObj[1]])
                        tag = (tags[mObj[1]]? tags[mObj[1]] : nil)
                        if tag and mObj[2]
                           if bUpdate == nil and rhGet(yDns, tag) and rhGet(yDns, tag) != mObj[2]
                              Logging.message("Your account setup is different than build env.")
                              Logging.message("We suggest you to update your account setup with data from your build env.")
                              bUpdate = agree("Do you want to update your setup with those build environment data?")
                           end
                           if bUpdate != nil and bUpdate
                              Logging.debug("Saved: '%s' = '%s'" % [mObj[1],mObj[2]])
                              rhSet(yDns, mObj[2], tag)
                           end
                        end
                     end
                  end
               end
            rescue => e
               Logging.fatal(1, "Unable to open the build environment file to migrate it\n%s" % e.backtrace.join('\n'))
            end
            oConfig.ExtraSet(:forj_accounts, sAccountName, :dns, yDns)
            oConfig.ExtraSave(File.join($FORJ_ACCOUNTS_PATH, sAccountName), :forj_accounts, sAccountName)
      end
   end
end
