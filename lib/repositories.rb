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
$INFRA_VERSION = "0.0.37"

module Repositories
  def clone_repo(maestro_url, oConfig)
      current_dir = Dir.pwd

      home = File.expand_path('~')
      path = home + '/.forj/'

      begin
        if File.directory?(path)
          if File.directory?(path + 'maestro')
            FileUtils.rm_r path + 'maestro'
          end
          git = Git.clone(maestro_url, 'maestro', :path => path)
          git.checkout(oConfig[:branch]) if oConfig[:branch] != 'master'
          Logging.info("Maestro repo '%s' cloned on branch '%s'" % [path, oConfig[:branch]])
        end
      rescue => e
        Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
        puts 'Error while cloning the repo from %s' % [maestro_url]
        puts 'If this error persist you could clone the repo manually in ~/.forj/'
      end
      Dir.chdir(current_dir)
  end

   def ensure_build_env_file(maestro_repo, branch)
      infra = File.join($FORJ_DATA_PATH, 'infra')
      template = File.join(maestro_repo, 'templates', 'infra')

      template_file = 'maestro.box.master.env'
      env_file = 'maestro.box.' + branch + '.env'

      source_build_env = File.join(template, template_file)
      dest_build_env = File.join(infra, env_file)

      if not File.exist?(source_build_env)
         raise <<-END
Your Maestro repository branch is too old.
Suggestion:
1. Clone %s to a different location.
   $ mkdir -p ~/src/forj-oss
   $ cd ~/src/forj-oss
   $ git clone %s
2. Use this master branch of maestro repository with forj
   $ forj set maestro_repo=~/src/forj-oss/maestro

then retry your boot.
END
      end
      return if File.exist?(dest_build_env)

      Logging.info("Creating '%s' to '%s'" % [source_build_env, dest_build_env])
      FileUtils.copy(source_build_env, dest_build_env)
   end

   def create_infra(maestro_repo, branch)
      # Build our own infra from maestro infra templates.
      infra = File.join($FORJ_DATA_PATH, 'infra')
      dest_cloud_init = File.join(infra, 'cloud-init')
      template = File.join(maestro_repo, 'templates', 'infra')
      cloud_init = File.join(template, 'cloud-init')

      if File.directory?(infra)
         Logging.debug("Cleaning up '%s'" % [infra])
         FileUtils.rm_r(infra)
      end
      AppInit.ensure_dir_exists(dest_cloud_init)
      if not File.exist?(cloud_init)
         raise <<-END
Your Maestro repository branch is too old.
Suggestion:
1. Clone %s to a different location.
   $ mkdir -p ~/src/forj-oss
   $ cd ~/src/forj-oss
   $ git clone %s
2. Use this master branch of maestro repository with forj
   $ forj set maestro_repo=~/src/forj-oss/maestro

then retry your boot.
END
      end
      Logging.debug("Copying recursively '%s' to '%s'" % [cloud_init, infra])
      FileUtils.copy_entry(cloud_init, dest_cloud_init)

      file_ver = File.join(infra, 'forj-cli.ver')
      File.write(file_ver, $INFRA_VERSION)
   end

   # Infra repository compatibility
   # <  0.0.37 - Use a template file of build env file.
   #              => Migration required.
   # >= 0.0.37 - Using a generic version of build env file, fully managed by forj cli.
   #              => No migration

   def infra_rebuild_required?(oConfig, infra_dir)
      # This function check if the current infra is compatible with current gem version.

      return false if not File.exists?(infra_dir)

      if infra_dir != File.join($FORJ_DATA_PATH, 'infra')
         # Do not take care. We do not manage it, ourself.
         return false
      end

      file_ver = File.join(infra_dir, 'forj-cli.ver')
      forj_infra_version = nil
      forj_infra_version = File.read(file_ver) if File.exist?(file_ver)

      if forj_infra_version
         return false if Gem::Version.new(forj_infra_version) == Gem::Version.new($INFRA_VERSION)
         return true if Gem::Version.new(forj_infra_version) < Gem::Version.new($INFRA_VERSION)
      end
      # Before version 0.0.37, version file did not exist. So return true
      true
   end

   def infra_rebuild(oConfig, infra_dir)
      return false if not File.exists?(infra_dir)

      file_ver = File.join(infra_dir, 'forj-cli.ver')
      forj_infra_version = nil
      forj_infra_version = File.read(file_ver) if File.exist?(file_ver)

      if forj_infra_version.nil? or forj_infra_version == ""
         # Prior version 37
         return(old_infra_data_update(oConfig, '0.0.36', infra_dir))
      elsif Gem::Version.new(forj_infra_version) < Gem::Version.new($INFRA_VERSION)
         return(old_infra_data_update(oConfig, forj_infra_version, infra_dir))
      end
   end

   def old_infra_data_update(oConfig, version, infra_dir)
      Logging.info("Migrating your local infra repo (%s) to the latest version." % version)
      bRebuild = false # Be default migration is successful. No need to rebuild it.
      case version
         when '0.0.36'
            # Moving from 0.0.36 or less to 0.0.37 or higher.
            # SET_COMPUTE="{SET_COMPUTE!}" => Setting for Compute. ignored. Coming from HPC
            # SET_TENANT_NAME="{SET_TENANT_NAME!}" => Setting for Compute. ignored. Need to query HPC from current Tenant ID

            # SET_DNS_TENANTID="{SET_DNS_TENANTID!}" => Setting for DNS. meta = dns_tenantid
            #  ==> :forj_accounts, sAccountName, :dns, :tenant_id

            # SET_DNS_ZONE="{SET_DNS_ZONE!}" => Setting for DNS. meta = dns_zone
            # ==> :forj_accounts, sAccountName, :dns, :service

            # SET_DOMAIN="{SET_DOMAIN!}" => Setting for Maestro (required) and DNS if enabled.
            # ==> :forj_accounts, sAccountName, :dns, :domain_name
            sAccountName = oConfig.get(:account_name)

            yDns = {}
            yDns = oConfig.oConfig.ExtraGet(:forj_accounts, sAccountName, :dns) if oConfig.oConfig.ExtraExist?(:forj_accounts, sAccountName, :dns)
            Dir.foreach(infra_dir) do | file |
               next if not /^maestro\.box\..*\.env$/ =~ file
               build_env = File.join(infra_dir, file)
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
                  Logging.fatal(1, "Failed to open the build environment file '%s'" % build_env, e)
               end
            end
            file_ver = File.join(infra_dir, 'forj-cli.ver')
            File.write(file_ver, $INFRA_VERSION)
            oConfig.oConfig.ExtraSet(:forj_accounts, sAccountName, :dns, yDns)
            oConfig.oConfig.ExtraSave(File.join($FORJ_ACCOUNTS_PATH, sAccountName), :forj_accounts, sAccountName)
            return bRebuild
      end
   end
end
