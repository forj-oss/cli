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


require_relative 'network.rb'
include Network
require_relative 'yaml_parse.rb'
include YamlParse
require_relative 'security.rb'
include SecurityGroup
require_relative 'repositories.rb'
include Repositories
#require_relative 'log.rb'
#include Logging
require_relative 'helpers.rb'
include Helpers


#
# Boot module
#
module Boot
  def boot(blueprint, name, build, build_config,
      branch, boothook, box_name, oConfig)
    begin

      Logging.fatal(1, 'FORJ account not specified. Did you used `forj setup`, before?') if not oConfig.get('account_name')

      oForjAccount = ForjAccount.new(oConfig)

      oForjAccount.ac_load()


      # Load Forj account data
      forjAccountFile = File.join($FORJ_ACCOUNTS_PATH, oConfig.get('account_name'))
      oConfig.ExtraLoad(forjAccountFile, :forj_accounts, oConfig.get('account_name'))

      # Check options and set data
      cloud_provider = oForjAccount.get(:account, :provider, 'hpcloud')

      if cloud_provider != 'hpcloud'
         Logging.fatal(1, "forj setup support only hpcloud. '%s' is currently not supported." % cloud_provider)
      end

      initial_msg = "booting %s on %s\nCheck log with `tail -f ~/.forj/forj.log`.\nUse --verbose or --debug for more boot status on screen" % [blueprint , cloud_provider]
      Logging.high_level_msg(initial_msg) #################

      # Initialize defaults
      maestro_url =  oConfig.get('maestro_url')

      infra_dir = File.expand_path(oConfig.get('infra_repo'))
      

      # Check about infra repo compatibility with forj cli
      bBuildInfra = Repositories.infra_rebuild_required?(oConfig, infra_dir)
      
      # Ask information if needed.
      if not Dir.exist?(File.expand_path(infra_dir))
         sAsk = 'Your \'%s\' infra directory doesn\'t exist. Do you want to create a new one from Maestro(repo github)/templates/infra (yes/no)?' % [infra_dir]
         bBuildInfra=agree(sAsk)
      else
         Logging.info('Re-using your infra... in \'%s\'' % [infra_dir]) if not bBuildInfra
      end
      if not Dir.exist?(File.expand_path(infra_dir)) and not bBuildInfra
         Logging.info ('Exiting.')
         return
      end

      # Get FORJ DNS setting
      yDNS = rhGet(oForjAccount.hAccountData, :dns)
      Logging.fatal(1, "DNS or domain name are missing. Please execute forj setup %s" % oForjAccount.get(:account, 'name')) if not yDNS

      branch = oConfig.get('branch') unless branch

      # Step Maestro Clone
      if not oConfig.get(:maestro_repo)
         Logging.info('cloning maestro repo from \'%s\'...' % maestro_url)
         Repositories.clone_repo(maestro_url)
         maestro_repo=File.expand_path('~/.forj/maestro')
      else
         maestro_repo=File.expand_path(oConfig.get(:maestro_repo))
         if not File.exists?('%s/templates/infra/maestro.box.%s.env' % [maestro_repo, branch])
            Logging.fatal(1, "'%s' is not a recognized Maestro repository. forj cli searched for templates/infra/%s-maestro.box.GITBRANCH.env.tmpl" % [maestro_repo, cloud_provider])
         end
         Logging.info('Using your maestro cloned repo \'%s\'...' % maestro_repo)
      end

      if bBuildInfra
         Logging.info('Building your infra... in \'%s\'' % [infra_dir])
         Repositories.create_infra(maestro_repo)
      end

      # Connect to services
      oFC=ForjConnection.new(oConfig)

      Logging.info('Configuring network \'%s\'' % [oConfig.get('network')])
      begin
        network = Network.get_or_create_network(oFC, oConfig.get('network'))
        subnet = Network.get_or_create_subnet(oFC, network.id, network.name)
        router = Network.get_or_create_router(oFC, network, subnet)
      rescue => e
        Logging.fatal(1, "Network properly configured is required.\n%s\n%s" % [e.message, e.backtrace.join("\n")])
      end

      Logging.info('Configuring keypair \'%s\'' % [oForjAccount.get(:credentials, 'keypair_name')])
      SecurityGroup.hpc_import_key(oForjAccount)


      Logging.info('Configuring Security Group \'%s\'' % [oConfig.get('security_group')])
      security_group = SecurityGroup.get_or_create_security_group(oFC, oConfig.get('security_group'))
      ports = oConfig.get('ports')

      ports.each do |port|
        port = port.to_s if port.class != String
        if not /^\d+(-\d+)?$/ =~ port
           Logging.error("Port '%s' is not valid. Must be <Port> or <PortMin>-<PortMax>" % [port])
        else
           mPortFound = /^(\d+)(-(\d+))?$/.match(port)
           portmin = mPortFound[1]
           portmax = (mPortFound[3]) ? (mPortFound[3]) : (portmin)
           Network.get_or_create_rule(oFC, security_group.id, 'tcp', portmin, portmax)
        end
      end

      oBuildEnv = BuildEnv.new(oConfig)
      ENV['FORJ_CLI_ENV'] = oBuildEnv.sBuildEnvFile
      oBuildEnv.set('FORJ_HPC',             oFC.sAccountName)
      oBuildEnv.set('FORJ_HPC_NET',         network.name)
      oBuildEnv.set('FORJ_SECURITY_GROUP',  oForjAccount.get(:maestro,    'security_group'))
      oBuildEnv.set('FORJ_KEYPAIR',         oForjAccount.get(:credentials,'keypair_name'))
      oBuildEnv.set('FORJ_HPC_NOVA_KEYPUB', oForjAccount.get(:credentials,'keypair_path') + '.pub')
      oBuildEnv.set('FORJ_BASE_IMG',        oForjAccount.get(:maestro,    'image'))
      oBuildEnv.set('FORJ_FLAVOR',          oForjAccount.get(:maestro,    'flavor'))
      oBuildEnv.set('FORJ_BP_FLAVOR',       oForjAccount.get(:maestro,    'bp_flavor'))
      oBuildEnv.set('FORJ_TENANT_NAME',     oForjAccount.get(:compute,    :tenant_name))
      oBuildEnv.set('FORJ_HPC_COMPUTE',     rhGet(oConfig.ExtraGet(:hpc_accounts,  oFC.sAccountName, :regions), :compute))
      

      oBuildEnv.set('FORJ_DOMAIN', yDNS[:domain_name])

      if yDNS[:tenant_id]
         oBuildEnv.set('FORJ_DNS_TENANTID', yDNS[:tenant_id])
         oBuildEnv.set('FORJ_DNS_ZONE',     yDNS[:service])
      end
      oBuildEnv.save()

      # run build.sh to boot maestro
      puts

      build = 'bin/build.sh' unless build

      build_config = oConfig.get('build_config')
      box_name = oConfig.get('box_name')

      arg = '--meta blueprint=%s ' % [blueprint]

      command = '%s --build_ID %s --box-name %s --build-conf-dir %s --build-config %s --gitBranch %s --debug-box %s' % [build, name, box_name, infra_dir, build_config, branch, arg]

      maestro_build_path = File.join(maestro_repo, 'build')

      current_dir = Dir.pwd
      Dir.chdir(maestro_build_path)

      Logging.info("Calling '%s' from '%s'" %  [build, Dir.pwd])
      Logging.debug("%s=%s %s" % ['FORJ_CLI_ENV', ENV['FORJ_CLI_ENV'], command])
      Kernel.system(ENV, command)
      Dir.chdir(current_dir)

#      if test
#        Logging.debug 'test flag is on, deleting objects'
#        Network.delete_router_interface(subnet.id, router)
#        Network.delete_subnet(subnet.id)
#        Network.delete_network(network.name)
#      end

    rescue Interrupt
      Logging.message("\n'%s' boot from '%s' interrupted by user" % [name, blueprint])
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

end


class BuildEnv

   attr_reader :sBuildEnvFile
   
   def initialize(oConfig)

      oConfig.fatal_if_inexistent('infra_repo')
      oConfig.fatal_if_inexistent('account_name')

      sBuildDir = File.expand_path(File.join(oConfig.get('infra_repo'),'build'))
      @sBuildEnvFile = File.join(sBuildDir, oConfig.get('account_name')+'.build.env')
      Helpers.ensure_dir_exists(sBuildDir)
      @yBuildEnvVar = {}
      @oConfig = oConfig
   end

   def set(key, value)
      # This file creates the in-memory data required to configure specific project build_env.
      # Name : ~/.forj/account/<Account>.build.env
      if value
         Logging.debug("Setting '%s' = '%s'" % [key, value])
         @yBuildEnvVar[key] = value
      else
         Logging.debug("'%s' is not set" % [key])
      end
   end

   def save()
      begin
         File.open(@sBuildEnvFile, 'w') do |out|
            @yBuildEnvVar.each do | key, value |
               desc = @oConfig.getAppDefault(:description, key)
               out.write("# %s - %s\n" % [key, desc]) if desc
               value = "" if not value
               out.write("%s='%s'\n\n" % [key, value])
            end
         end
         Logging.debug("'%s' written." % [@sBuildEnvFile])
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end
end
