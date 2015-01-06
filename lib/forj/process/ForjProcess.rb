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

# Forj Process solution

require 'git'
require 'fileutils'
require 'find'
require 'digest'
require 'json'
require 'encryptor' # gem install encryptor
require 'base64'
require 'net/ssh'

$INFRA_VERSION = "0.0.37"

# Functions for boot
class ForjCoreProcess

   def build_metadata(sObjectType, hParams)
      key_file = File.join($FORJ_CREDS_PATH, '.key')

      if not File.exists?(key_file)
         # Need to create a random key.
         entr = {
            :key => rand(36**10).to_s(36),
            :salt => Time.now.to_i.to_s,
            :iv => Base64::strict_encode64(OpenSSL::Cipher::Cipher.new('aes-256-cbc').random_iv)
         }

         PrcLib.debug("Writing '%s' key file" % key_file)
         File.open(key_file, 'w') do |out|
            out.write(Base64::encode64(entr.to_yaml))
         end
      else
         PrcLib.debug("Loading '%s' key file" % key_file)
         encoded_key = IO.read(key_file)
         entr = YAML.load(Base64::decode64(encoded_key))
      end
      os_enckey = hParams[:os_enckey]

      begin
         os_key = Encryptor.decrypt(
            :value => Base64::strict_decode64(os_enckey),
            :key => entr[:key],
            :iv => Base64::strict_decode64(entr[:iv]),
            :salt => entr[:salt]
         )
      rescue => e
         raise "Unable to decript your password. You need to re-execute setup."
      end

      hpcloud_priv = nil
      IO.popen('gzip -c' , 'r+') {|pipe|
         pipe.puts('HPCLOUD_OS_USER=%s' % [hParams[:os_user]] )
         pipe.puts('HPCLOUD_OS_KEY=%s' % [os_key] )
         pipe.puts('DNS_KEY=%s' % [hParams[:account_id]] )
         pipe.puts('DNS_SECRET=%s' % [hParams[:account_key]])
         pipe.close_write
         hpcloud_priv = pipe.read
      }

      config.set(:server_name, "maestro.%s" % hParams[:instance_name]) # Used by :server object

      hMeta = {
         'cdksite' => config.get(:server_name),
         'cdkdomain' => hParams[:domain_name],
         'eroip' => '127.0.0.1',
         'erosite' => config.get(:server_name),
         'erodomain' => hParams[:domain_name],
         'gitbranch' => hParams[:branch],
         'security_groups' => hParams[:security_group],
         'tenant_name' => hParams[:tenant_name],
         'network_name' => hParams[:network_name],
         'hpcloud_os_region' => hParams[:compute],
         'PUPPET_DEBUG' => 'True',
         'image_name' => hParams[:image_name],
         'key_name' => hParams[:keypair_name],
         'hpcloud_priv' => Base64.strict_encode64(hpcloud_priv).gsub('=', '') # Remove pad
      }

      if hParams[:dns_service]
         hMeta['dns_zone'] = hParams[:dns_service]
         hMeta['dns_tenantid'] = hParams[:dns_tenant_id]
      end
      # If requested by user, ask Maestro to instantiate a blueprint.
      hMeta['blueprint'] = hParams[:blueprint] if hParams[:blueprint]

      # Add init additionnal git clone steps.
      hMeta['repos'] = hParams[:repos] if hParams[:repos]
      # Add init bootstrap additionnal steps
      hMeta['bootstrap'] = hParams[:bootstrap] if hParams[:bootstrap]

      config.set(:meta_data, hMeta) # Used by :server object

      hMetaPrintable = hMeta.clone
      hMetaPrintable['hpcloud_priv'] = "XXX - data hidden - XXX"
      PrcLib.info("Metadata set:\n%s" % hMetaPrintable)

      oMetaData = register(hMeta, sObjectType)
      oMetaData[:meta_data] = hMeta

      oMetaData
   end

   def build_forge(sObjectType, hParams)

      oForge = Get(sObjectType, config[:instance_name])
      if oForge.empty? or oForge[:servers].length == 0
         PrcLib.high_level_msg ("\nBuilding your forge...\n")
         Create(:internet_server)
      else
         oForge[:servers].each { | oServerToFind |
            Get(:server, oServerToFind[:id]) if /^maestro\./ =~ oServerToFind[:name]
         }
         PrcLib.high_level_msg ("\nChecking your forge...\n")
         oServer = DataObjects(:server, :ObjectData)
         if oServer
            oIP = Query(:public_ip, :server_id => oServer[:id])
            if oIP.length > 0
               register oIP[0]
            end
            Create(:keypairs)
         else
            PrcLib.high_level_msg ("\nYour forge exist, without maestro. Building Maestro...\n")
            Create(:internet_server)

            PrcLib.high_level_msg ("\nBuilding your forge...\n")
         end
      end

      oServer = DataObjects(:server, :ObjectData)

      #Get keypairs
      hKeys = keypair_detect(oServer[:key_name], File.join($FORJ_KEYPAIRS_PATH, oServer[:key_name]))

      private_key_file = File.join(hKeys[:keypair_path], hKeys[:private_key_name])
      public_key_file  = File.join(hKeys[:keypair_path], hKeys[:public_key_name])

      oServerKey = Get(:keypairs, oServer[:key_name])

      keypair_coherent = coherent_keypair?(hKeys, oServerKey)

      # Define the log lines to get and test.
      config.set(:log_lines, 5)

      PrcLib.info("Maestro server '%s' id is '%s'." % [oServer[:name], oServer[:id]])
      # Waiting for server to come online before assigning a public IP.

      sStatus = :checking
      maestro_create_status(sStatus)
      oAddress = DataObjects(:public_ip, :ObjectData)

      if oServer[:attrs][:status] == :active
         sMsg = <<-END
Your forj Maestro server is up and running and is publically accessible through IP '#{oAddress[:public_ip]}'.

You can connect to '#{oServer[:name]}' with:
ssh ubuntu@#{oAddress[:public_ip]} -o StrictHostKeyChecking=no -i #{private_key_file}
         END
         if not keypair_coherent
            sMsg += ANSI.bold("\nUnfortunatelly") + " your current keypair is not usable to connect to your server.\nYou need to fix this issue to gain access to your server."
         end
         PrcLib.info(sMsg)

         oLog = Get(:server_log, 25)[:attrs][:output]
         if /cloud-init boot finished/ =~ oLog
            sStatus = :active
            PrcLib.high_level_msg ("\n%s\nThe forge is ready...\n" % sMsg)
         else
            PrcLib.high_level_msg ("\n%s\nThe forge is still building...\n" % sMsg)
            sStatus = :cloud_init
         end
      else
         sleep 5
         sStatus = :starting
      end

      mCloudInitError = []
      iCurAct = 0
      oOldLog = ""

      while sStatus != :active
         maestro_create_status(sStatus, iCurAct)
         iCurAct += 1
         iCurAct = iCurAct % 4
         begin
            oServer = Get(:server, oServer[:attrs][:id])
         rescue => e
            PrcLib.error(e.message)
         end
         if sStatus == :starting
            if oServer[:attrs][:status] == :active
               sStatus = :assign_ip
            end
         elsif sStatus == :assign_ip
            if oAddress.empty?
               query_cache_cleanup(:public_ip) # To be able to ask for server IP assigned
               oAddresses = Query(:public_ip, :server_id => oServer[:id])
               if oAddresses.length == 0
                  # Assigning Public IP.
                  oAddress = Create(:public_ip)
               else
                  oAddress = oAddresses[0]
               end
            end
            sMsg = <<-END
Public IP for server '#{oServer[:name]}' is assigned.
Now, as soon as the server respond to the ssh port, you will be able to get a tail of the build with:
while [ 1 = 1 ]
do
  ssh ubuntu@#{oAddress[:public_ip]} -o StrictHostKeyChecking=no -i #{private_key_file} tail -f /var/log/cloud-init.log
  sleep 5
done
            END
            if not keypair_coherent
               sMsg += ANSI.bold("\nUnfortunatelly") + " your current keypair is not usable to connect to your server.\nYou need to fix this issue to gain access to your server."
            end
            PrcLib.info(sMsg)
            PrcLib.high_level_msg ("\n%s\nThe forge is still building...\n" % sMsg)
            sStatus = :cloud_init
         else #analyze the log output
            oLog = Get(:server_log, 25)[:attrs][:output]
            iCurAct = 4 if oLog == oOldLog
            oOldLog = oLog
            if /cloud-init boot finished/ =~ oLog
               sStatus = :active
               if mCloudInitError != []
                  PrcLib.high_level_msg ("Critical error cleared. Cloud-init seems moving...")
                  PrcLib.info ("Critical error cleared. Cloud-init seems moving...")
                  mCloudInitError = []
               end
            elsif /\[CRITICAL\]/ =~ oLog
               mCritical = oLog.scan(/.*\[CRITICAL\].*\n/)
               if not (mCloudInitError == mCritical)
                  sReported = oLog.clone
                  sReported['CRITICAL'] = ANSI.bold('CRITICAL')
                  PrcLib.error("cloud-init error detected:\n-----\n%s\n-----\nPlease connect to the box to decide what you need to do." % [sReported])
                  mCloudInitError = mCritical
               end
            elsif sStatus == :cloud_init and /cloud-init-nonet gave up waiting for a network device/ =~ oLog
               # Valid for ubuntu image 12.04
               PrcLib.warning("Cloud-init has gave up to configure the network. waiting...")
               sStatus = :nonet
            elsif sStatus == :nonet and /Booting system without full network configuration/ =~ oLog
               # Valid for ubuntu image 12.04
               PrcLib.warning("forj has detected an issue to bring up your maestro server. Removing it and re-creating a new one. please be patient...")
               sStatus = :restart
            elsif sStatus == :restart
               Delete(:server)
               Create(:internet_server)
               sStatus = :starting
            end
         end
         sleep(5) if sStatus != :active
      end

      oForge = get_forge(sObjectType, config[:instance_name], hParams)
      sMsg = "Your Forge '%s' is ready and accessible from IP #{oAddress[:public_ip]}." % config[:instance_name]
      # TODO: read the blueprint/layout to identify which services are implemented and can be accessible.
      if config[:blueprint]
         sMsg += "\nMaestro has implemented the following server(s) for your blueprint '%s':" % config[:blueprint]
         iCount = 0
         oForge[:servers].each { | oServer|
            next if /^maestro\./ =~ oServer[:name]
            register(oServer)
            oIP = Query(:public_ip, :server_id => oServer[:id])
            if oIP.length == 0
               sMsg += "\n- %s (No public IP)" % [oServer[:name]]
            else
               sMsg += "\n- %s (%s)" % [oServer[:name], oIP[0][:public_ip]]
            end
            iCount += 1
         }
         if iCount > 0
            sMsg += "\n%d server(s) identified.\n" % iCount
         else
            sMsg = "No servers found except maestro"
            PrcLib.warning("Something went wrong, while creating nodes for " \
               "blueprint '%s'. check maestro logs." % config[:blueprint])
         end
      else
         sMsg += "\nMaestro has NOT implemented any servers, because you did not provided a blueprint. Connect to Maestro, and ask Maestro to implement any kind of blueprint you need. (Feature currently under development)"
      end
      PrcLib.info(sMsg)
      PrcLib.high_level_msg ("\n%s\nEnjoy!\n" % sMsg)
      oForge
   end

   def maestro_create_status(sStatus, iCurAct = 4)
      sActivity = "/-\\|?"
      if iCurAct < 4
         sCurAct = "ACTIVE"
      else
         sCurAct = ANSI.bold("PENDING")
      end

      case sStatus
         when :checking
            PrcLib.state("Checking server status")
         when :starting
            PrcLib.state("STARTING")
         when :assign_ip
            PrcLib.state("%s - %s - Assigning Public IP" % [sActivity[iCurAct], sCurAct])
         when :cloud_init
            PrcLib.state("%s - %s - Currently running cloud-init. Be patient." % [sActivity[iCurAct], sCurAct])
         when :nonet
            PrcLib.state("%s - %s - Currently running cloud-init. Be patient." % [sActivity[iCurAct], sCurAct])
         when :restart
            PrcLib.state("RESTARTING - Currently restarting maestro box. Be patient.")
         when :active
            PrcLib.info("Server is active")
      end
   end

   def clone_or_use_maestro_repo(sObjectType, hParams)

      maestro_url = hParams[:maestro_url]
      maestro_repo = File.expand_path(hParams[:maestro_repo]) unless hParams[:maestro_repo].nil?
      path_maestro = File.expand_path('~/.forj/')
      hResult = {}

      begin
         if maestro_repo and File.directory?(maestro_repo)
            PrcLib.info("Using maestro repo '%s'" % maestro_repo)
            hResult[:maestro_repo] = maestro_repo
         else
            hResult[:maestro_repo] = File.join(path_maestro, 'maestro')
            PrcLib.state("Cloning maestro repo from '%s' to '%s'" % [maestro_url, File.join(path_maestro, 'maestro')])
            if File.directory?(path_maestro)
               if File.directory?(File.join(path_maestro, 'maestro'))
                  FileUtils.rm_r File.join(path_maestro, 'maestro')
               end
            end
            git = Git.clone(maestro_url, 'maestro', :path => path_maestro)
            git.checkout(config[:branch]) if config[:branch] != 'master'
            PrcLib.info("Maestro repo '%s' cloned on branch '%s'" % [File.join(path_maestro, 'maestro'), config[:branch]])
         end
      rescue => e
         PrcLib.error("Error while cloning the repo from %s\n%s\n%s" % [maestro_url, e.message, e.backtrace.join("\n")])
         PrcLib.info("If this error persist you could clone the repo manually in ~/.forj/")
      end
      oMaestro = register(hResult, sObjectType)
      oMaestro[:maestro_repo] = hResult[:maestro_repo]
      oMaestro
   end

   def create_or_use_infra(sObjectType, hParams)
      infra = File.expand_path(hParams[:infra_repo])
      maestro_repo = hParams[:maestro_repository, :maestro_repo]
      branch = hParams[:branch]
      dest_cloud_init = File.join(infra, 'cloud-init')
      template = File.join(maestro_repo, 'templates', 'infra')
      cloud_init = File.join(template, 'cloud-init')

      hInfra = { :infra_repo => dest_cloud_init}

      AppInit.ensure_dir_exists(dest_cloud_init)

      bReBuildInfra = infra_is_original?(infra, maestro_repo)

      if bReBuildInfra
         PrcLib.state("Building your infra workspace in '%s'" % [infra])

         PrcLib.debug("Copying recursively '%s' to '%s'" % [cloud_init, infra])
         FileUtils.copy_entry(cloud_init, dest_cloud_init)

         file_ver = File.join(infra, 'forj-cli.ver')
         File.write(file_ver, $INFRA_VERSION)
         PrcLib.info("The infra workspace '%s' has been built from maestro predefined files." % [infra])
      else
         PrcLib.info("Re-using your infra... in '%s'" % [infra])
      end


      oInfra = register(hInfra, sObjectType)
      oInfra[:infra_repo] = hInfra[:infra_repo]
      oInfra
   end

   # Function which compare directories from maestro templates to infra.
   def infra_is_original?(infra_dir, maestro_dir)
      dest_cloud_init = File.join(infra_dir, 'cloud-init')
      template = File.join(maestro_dir, 'templates', 'infra')
      sMD5List = File.join(infra_dir, '.maestro_original.yaml')
      bResult = true
      hResult = {}
      if File.exists?(sMD5List)
         begin
            hResult = YAML.load_file(sMD5List)
         rescue => e
            PrcLib.error("Unable to load valid Original files list '%s'. Your infra workspace won't be migrated, until fixed." % sMD5List)
            bResult = false
         end
         if not hResult
            hResult = {}
            bResult = false
         end
      end
      # We are taking care on bootstrap files only.
      Find.find(File.join(template, 'cloud-init')) { | path |
         if not File.directory?(path)
            sMaestroRelPath = path.clone
            sMaestroRelPath[File.join(template, 'cloud-init/')] = ""
            sInfra_path = File.join(dest_cloud_init, sMaestroRelPath)
            if File.exists?(sInfra_path)
               md5_file = Digest::MD5.file(sInfra_path).hexdigest
               if hResult.key?(sMaestroRelPath) and hResult[sMaestroRelPath] != md5_file
                  bResult = false
                  PrcLib.info("'%s' infra file has changed from original template in maestro." % sInfra_path)
               else
                  PrcLib.debug("'%s' infra file has not been updated." % sInfra_path)
               end
            end
            md5_file = Digest::MD5.file(path).hexdigest
            hResult[sMaestroRelPath] = md5_file
         end
      }
      begin
         File.open(sMD5List, 'w') do |out|
            YAML.dump(hResult, out)
         end
      rescue => e
         PrcLib.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
      if bResult
         PrcLib.debug("No original files found has been updated. Infra workspace can be updated/created if needed.")
      else
         PrcLib.warning("At least, one file has been updated. Infra workspace won't be updated by forj cli.")
      end
      bResult
   end

   def infra_rebuild(infra_dir)
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
      PrcLib.info("Migrating your local infra repo (%s) to the latest version." % version)
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
               PrcLib.debug("Reading data from '%s'" % build_env)
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
                           PrcLib.debug("Reviewing detected '%s' tag" % [mObj[1]])
                           tag = (tags[mObj[1]]? tags[mObj[1]] : nil)
                           if tag and mObj[2]
                              if bUpdate == nil and rhGet(yDns, tag) and rhGet(yDns, tag) != mObj[2]
                                 PrcLib.message("Your account setup is different than build env.")
                                 PrcLib.message("We suggest you to update your account setup with data from your build env.")
                                 bUpdate = agree("Do you want to update your setup with those build environment data?")
                              end
                              if bUpdate != nil and bUpdate
                                 PrcLib.debug("Saved: '%s' = '%s'" % [mObj[1],mObj[2]])
                                 rhSet(yDns, mObj[2], tag)
                              end
                           end
                        end
                     end
                  end
               rescue => e
                  PrcLib.fatal(1, "Failed to open the build environment file '%s'" % build_env, e)
               end
            end
            file_ver = File.join(infra_dir, 'forj-cli.ver')
            File.write(file_ver, $INFRA_VERSION)
            oConfig.oConfig.ExtraSet(:forj_accounts, sAccountName, :dns, yDns)
            oConfig.oConfig.ExtraSave(File.join($FORJ_ACCOUNTS_PATH, sAccountName), :forj_accounts, sAccountName)
            return bRebuild
      end
   end

   def build_userdata(sObjectType, hParams)
      # get the paths for maestro and infra repositories
      maestro_path = hParams[:maestro_repository].values
      infra_path = hParams[:infra_repository].values

      # concatenate the paths for boothook and cloud_config files
      #~ build_dir = File.expand_path(File.join($FORJ_DATA_PATH, '.build'))
      #~ boothook = File.join(maestro_path, 'build', 'bin', 'build-tools')
      #~ cloud_config = File.join(maestro_path, 'build', 'maestro')

      mime = File.join($FORJ_BUILD_PATH, 'userdata.mime.%s' % rand(36**5).to_s(36))

      meta_data = JSON.generate(hParams[:metadata, :meta_data])

      build_tmpl_dir = File.expand_path(File.join($LIB_PATH, 'build_tmpl'))

      PrcLib.state("Preparing user_data - file '%s'" % mime)
      # generate boot_*.sh
      mime_cmd = "#{build_tmpl_dir}/write-mime-multipart.py"
      bootstrap = "#{build_tmpl_dir}/bootstrap_build.sh"

      cmd = "%s '%s' '%s' '%s' '%s' '%s' '%s' '%s'" % [
         bootstrap, # script
         $FORJ_DATA_PATH, # $1 = Forj data base dir
         hParams[:maestro_repository, :maestro_repo], # $2 = Maestro repository dir
         config[:bootstrap_dirs], # $3 = Bootstrap directories
         config[:bootstrap_extra_dir], # $4 = Bootstrap extra directory
         meta_data,  # $5 = meta_data (string)
         mime_cmd, # $6: mime script file to execute.
         mime # $7: mime file generated.
      ]

      # TODO: Replace shell script call to ruby functions
      if $LIB_FORJ_DEBUG >= 1
         cmd += " >> #{$FORJ_DATA_PATH}/forj.log"
      else
         cmd += " | tee -a #{$FORJ_DATA_PATH}/forj.log"
      end
      raise ForjError.new, "#{bootstrap} script file is not found." if not File.exists?(bootstrap)
      PrcLib.debug("Running '%s'" % cmd)
      Kernel.system(cmd)

      raise ForjError.new(), "mime file '%s' not found." % mime if not File.exists?(mime)

      begin
         user_data = File.read(mime)
      rescue => e
         PrcLib.fatal(1, e.message)
      end
      if $LIB_FORJ_DEBUG < 5
         File.delete(mime)
      else
         ForjLib.debug(5, "user_data temp file '%s' kept" % mime)
      end

      config[:user_data] = user_data

      oUserData = register(hParams, sObjectType)
      oUserData[:user_data] = user_data
      oUserData[:user_data_encoded] = Base64.strict_encode64(user_data)
      oUserData[:mime] = mime
      PrcLib.info("user_data prepared. File: '%s'" % mime)
      oUserData
  end

end

# Functions for setup
class ForjCoreProcess

   # Check files existence
   def forj_check_keypairs_files(keypath)
      key_name = config.get(:keypair_name)

      keys_entered = keypair_detect(key_name, keypath)
      if not keys_entered[:private_key_exist? ] and not keys_entered[:public_key_exist? ]
         if agree("The key you entered was not found. Do you want to create this one?")
            base_dir = keys_entered[:keypair_path]
            if not File.directory?(base_dir)
               if agree("'%s' doesn't exist. Do you want to create it?" % base_dir)
                  AppInit.ensure_dir_exists(base_dir)
               else
                  return false
               end
            end
         else
            return false
         end
      end
      true
   end

   # keypair_files post setup
   def forj_setup_keypairs_files
      # Getting Account keypair information
      key_name = config[:keypair_name]
      key_path = File.expand_path(config[:keypair_files])

      keys_imported = nil
      keys_imported = keypair_detect(key_name, config.oConfig.localGet(key_name, :imported_keys)) if config.oConfig.localExist?(key_name, :imported_keys)
      keys = keypair_detect(key_name, key_path)

      if keys_imported and keys_imported[:key_basename] != keys[:key_basename] and $FORJ_KEYPAIRS_PATH != keys[:keypair_path]
         PrcLib.warning("The private key '%s' was assigned to a different private key file '%s'.\nTo not overwrite it, we recommend you to choose a different keypair name." % [key_name, keys_imported[:key_basename] ])
         new_key_name = key_name
         sMsg = "Please, provide a different keypair name:"
         while key_name == new_key_name
            new_key_name = ask (sMsg) do | q |
               q.validate = /.+/
            end
            new_key_name = new_key_name.to_s
            sMsg = "Incorrect. You have to choose a keypair name different than '#{key_name}'. If you want to interrupt, press Ctrl-C and retry later.\nSo, please, provide a different keypair name:" if key_name == new_key_name
         end
         key_name = new_key_name
         config.set(:key_name, key_name)
         keys = keypair_detect(key_name, key_path)
      end

      private_key_file = File.join(keys[:keypair_path], keys[:private_key_name])
      public_key_file = File.join(keys[:keypair_path], keys[:public_key_name])


      # Creation sequences
      if not keys[:private_key_exist? ]
         # Need to create a key. ask if we need so.
         PrcLib.message("The private key file attached to keypair named '%s' is not found. Running ssh-keygen to create it." % keys[:keypair_name])
         if not File.exists?(private_key_file)
            AppInit.ensure_dir_exists(File.dirname(private_key_file))
            command = 'ssh-keygen -t rsa -f %s' % private_key_file
            PrcLib.debug("Executing '%s'" % command)
            system(command)
         end
         if not File.exists?(private_key_file)
            PrcLib.fatal(1, "'%s' not found. Unable to add your keypair to hpcloud. Create it yourself and provide it with -p option. Then retry." % [private_key_file])
         else
            PrcLib.fatal(1, "ssh-keygen did not created your key pairs. Aborting. Please review errors in ~/.forj/forj.log")
         end
      end

      if not keys[:public_key_exist? ]
         PrcLib.message("Your public key '%s' was not found. Getting it from the private one. It may require your passphrase." % [public_key_file])
         command = 'ssh-keygen -y -f %s > %s' % [private_key_file,public_key_file ]
         PrcLib.debug("Executing '%s'" % command)
         system(command)
      end

      forj_private_key_file = File.join($FORJ_KEYPAIRS_PATH, key_name )
      forj_public_key_file = File.join($FORJ_KEYPAIRS_PATH, key_name + ".pub")

      # Saving sequences

      if keys[:keypair_path] != $FORJ_KEYPAIRS_PATH
         if not File.exists?(forj_private_key_file) or not File.exists?(forj_public_key_file)
            PrcLib.info("Importing key pair to FORJ keypairs list.")
            FileUtils.copy(private_key_file, forj_private_key_file)
            FileUtils.copy(public_key_file, forj_public_key_file)
            # Attaching this keypair to the account
            Lorj::rhSet(@hAccountData, key_name, :credentials, 'keypair_name')
            Lorj::rhSet(@hAccountData, forj_private_key_file, :credentials, 'keypair_path')
            config.oConfig.LocalSet(key_name.to_s, private_key_file, :imported_keys)
         else
            # Checking source/dest files content
            if Digest::MD5.file(private_key_file).hexdigest != Digest::MD5.file(forj_private_key_file).hexdigest
               PrcLib.info("Updating private key keypair piece to FORJ keypairs list.")
               FileUtils.copy(private_key_file, forj_private_key_file)
            else
               PrcLib.info("Private key keypair up to date.")
            end
            if Digest::MD5.file(public_key_file).hexdigest != Digest::MD5.file(forj_public_key_file).hexdigest
               PrcLib.info("Updating public key keypair piece to FORJ keypairs list.")
               FileUtils.copy(public_key_file, forj_public_key_file)
            else
               PrcLib.info("Public key keypair up to date.")
            end
         end
      end
      # Saving internal copy of private key file for forj use.
      config.set(:keypair_path, forj_private_key_file )
      PrcLib.info("Configured forj keypair '%s' with '%s'" % [ keys[:keypair_name], File.join(keys[:keypair_path], keys[:key_basename]) ] )
      true # forj_setup_keypairs_files successfull
   end

   def forj_DNS_settings()
      sAsk = "Optionally, you can ask Maestro to use/manage a domain name on your cloud. It requires your DNS cloud service to be enabled.\nDo you want to configure it?"
      config.set(:dns_settings, agree(sAsk))
      true
   end

   def forj_DNS_settings?(sKey)
      # Return true to ask the question. false otherwise
      if not config.get(:dns_settings)
         config.set(sKey, nil)
         return false # Do not ask
      end
      true
   end

   def setup_tenant_name()
      # TODO: To re-introduce with a Controller call instead.
      oSSLError=SSLErrorMgt.new # Retry object
      PrcLib.debug("Getting tenants from hpcloud cli libraries")
      begin
         tenants = Connection.instance.tenants(@sAccountName)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace, e)
            retry
         end
         PrcLib.fatal(1, 'Network: Unable to connect.')
      end
      tenant_id = rhGet(@oConfig.ExtraGet(:hpc_accounts, @sAccountName, :credentials), :tenant_id)
      tenant_name = nil
      tenants.each { |elem| tenant_name = elem['name'] if elem['id'] == tenant_id }
      if tenant_name
         PrcLib.debug("Tenant ID '%s': '%s' found." % [tenant_id, tenant_name])
         rhSet(@hAccountData, tenant_name, :maestro, :tenant_name)
      else
         PrcLib.error("Unable to find the tenant Name for '%s' ID." % tenant_id)
      end
      @oConfig.set('tenants', tenants)
   end

end

#Funtions for get
class ForjCoreProcess
  def get_forge(sCloudObj, sForgeId, hParams)
    sQuery = {}
    hServers = []
    sQuery[:name] = sForgeId

    oServers = Query(:server, sQuery )

    regex =  Regexp.new('\.%s$' % sForgeId)

    oServers.each { |oServer|
      oName = oServer[:name]
      hServers<<oServer if regex =~ oName
    }
   PrcLib.info("%s server(s) were found under instance name %s " % [hServers.count(), sQuery[:name]])

   oForge = register(hServers, sCloudObj)
   oForge[:servers] = hServers
   oForge[:name] = sForgeId
   oForge
  end
end

#Funtions for destroy
class ForjCoreProcess
   def delete_forge(sCloudObj, hParams)

      PrcLib.state("Destroying server(s) of your forge")

      forge_serverid = config.get(:forge_server)

      oForge = hParams[:forge]

      oForge[:servers].each{|server|
         next if forge_serverid and forge_serverid != server[:id]
         register(server)
         PrcLib.state("Destroying server '%s'" % server[:name])
         Delete(:server)
      }
      if forge_serverid.nil?
         PrcLib.high_level_msg ("The forge '%s' has been destroyed. (all servers linked to the forge)\n" % oForge[:name] )
      else
         PrcLib.high_level_msg ("Server(s) selected in the forge '%s' has been removed.\n"  % [oForge[:name]])
      end
  end
end

# Functions for ssh
class ForjCoreProcess
   def ssh_connection(sObjectType, hParams)
      oForge = hParams[:forge]
      oServer = nil

      oForge[:servers].each{|server|
         next if hParams[:forge_server] != server[:id]
         oServer = server
         break
      }

      #Get server information
      PrcLib.state("Getting server information")
      oServer = Get(:server, oServer[:id])
      register(oServer)

      # Get Public IP of the server. Needs the server to be loaded.
      oAddress = Query(:public_ip, :server_id =>  oServer[:id])

      if oAddress.length == 0
         PrcLib.fatal(1, "ip address for %s server was not found" % oServer[:name])
      else
         public_ip = oAddress[0][:public_ip]
      end

      if config[:identity].nil? or not config[:identity].is_a?(String)
         hKeys = keypair_detect(oServer[:key_name], File.join($FORJ_KEYPAIRS_PATH, oServer[:key_name]))
      else
         hKeys = keypair_detect(oServer[:key_name], File.expand_path(config[:identity]))
      end

      private_key_file = File.join(hKeys[:keypair_path], hKeys[:private_key_name])
      public_key_file = File.join(hKeys[:keypair_path], hKeys[:public_key_name])

      PrcLib.info("Found openssh private key file '%s'." % private_key_file) if hKeys[:private_key_exist? ]
      if hKeys[:public_key_exist? ]
         PrcLib.info("Found openssh public key file '%s'."  % public_key_file)
      else
         PrcLib.warning("Openssh public key file '%s' not found. Unable to verify keys coherence with remote server." % public_key_file)
      end

      if hKeys[:private_key_exist? ]
         ssh_options = { :keys => private_key_file}
         PrcLib.debug("Using private key '%s'." % private_key_file)
      else
         PrcLib.fatal 1, <<-END
The server '#{oServer[:name]}' has been configured with a keypair '#{oServer[:key_name]}' which is not found locally.
You won't be able to connect to that server without '#{oServer[:key_name]}' private key.
To connect to this box, you need to provide the appropriate private key file with option -i
         END
      end

      # Get ssh user
      image  = Get(:image, oServer[:image_id])
      user = hParams[:ssh_user]

      if user.nil?
         user = image[:ssh_user]
      end

      PrcLib.debug("Using account '%s'." % user)

      begin
         PrcLib.state("creating ssh connection with '%s' box" % oServer[:name])
         session = Net::SSH.start(public_ip, user, ssh_options) do |ssh|
            ssh_login(ssh_options, user, public_ip)
         end
         PrcLib.debug("Error closing ssh connection, box %s " % oServer[:name]) if not session
      rescue => e
         PrcLib.fatal 1, <<-END
#{e.message}
You were not able to connect to this box. Please note that there is no garantuee that your local private key file '#{private_key_file}' is the one that was used while building this box.
You have to check with the user who created that box.
         END
      end
      register({ :success => true }, sObjectType)
   end

   def setup_ssh_user(sCloudObj, hParams)
       images  = Query(:image, { name: hParams[:image_name]} )
       case images.length
         when 0
            sDefault = hParams[:default_value]
         else
            if images[0, :ssh_user].nil?
               sDefault = hParams[:default_value]
            else
               sDefault = images[0, :ssh_user]
            end
       end
       { default_value: sDefault, list: config[:users] }
   end

   def ssh_login(options, user, public_ip)
      sOpts = "-o StrictHostKeyChecking=no -o ServerAliveInterval=180"
      sOpts += " -i %s" % options[:keys] if options[:keys]

      command = 'ssh %s %s@%s' % [sOpts, user, public_ip]
      PrcLib.debug("Running '%s'" % command)
      system(command)
   end

   def ssh_user(image_name)
      return "fedora" if image_name =~ /fedora/i
      return "centos" if image_name =~ /centos/i
      return "ubuntu"
   end

end
