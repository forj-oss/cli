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
  def boot(blueprint, name,
      build, infra_dir, build_config,
      branch, maestro_repo, boothook, box_name,
      oConfig, test = false)
    begin

      # Check options and set data
      cloud_provider=oConfig.get('provider')
      Logging.fatal(1, 'No provider specified.') if not cloud_provider

      if cloud_provider != 'hpcloud'
         Logging.fatal(1, "forj setup support only hpcloud. '%s' is currently not supported." % cloud_provider)
      end

      oConfig.setDefault('account_name', cloud_provider)

      initial_msg = 'booting %s on %s (~/.forj/forj.log)' % [blueprint , cloud_provider]
      Logging.high_level_msg(initial_msg) #################

      # Initialize defaults
      maestro_url =  oConfig.get('maestro_url')

      infra_dir = oConfig.get('infra_repo') unless infra_dir

      # Ask information if needed.
      bBuildInfra=false
      if not Dir.exist?(File.expand_path(infra_dir))
         sAsk = 'Your \'%s\' infra directory doesn\'t exist. Do you want to create a new one from Maestro(repo github)/templates/infra (yes/no)?' % [infra_dir]
         bBuildInfra=agree(sAsk)
      else
         Logging.info('Re-using your infra... in \'%s\'' % [infra_dir])
      end
      if not Dir.exist?(File.expand_path(infra_dir)) and not bBuildInfra
         Logging.info ('Exiting.')
         return
      end

      # Step Maestro Clone
      if not maestro_repo
         Logging.high_level_msg('cloning maestro repo ...' ) #################
         Logging.info('cloning maestro repo from \'%s\'...' % maestro_url)
         Repositories.clone_repo(maestro_url)
         maestro_repo=File.expand_path('~/.forj/maestro')
      else
         maestro_repo=File.expand_path(maestro_repo)
         if not File.exists?('%s/templates/infra/%s-maestro.box.GITBRANCH.env.tmpl' % [maestro_repo, cloud_provider])
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

      Logging.high_level_msg('Configuring network...') #################
      Logging.info('Configuring network \'%s\'' % [oConfig.get('network')])
      begin
        network = Network.get_or_create_network(oFC, oConfig.get('network'))
        subnet = Network.get_or_create_subnet(oFC, network.id, network.name)
        router = Network.get_or_create_router(oFC, network, subnet)
      rescue => e
        Logging.fatal(1, "Network properly configured is required.\n%s\n%s" % [e.message, e.backtrace.join("\n")])
      end

      Logging.state('Configuring keypair...') #################
      Logging.info('Configuring keypair \'%s\'' % [oConfig.get('keypair_name')])
      SecurityGroup.hpc_import_key(oConfig, oFC.sAccountName)

      Logging.state('Configuring security group...') #################

      Logging.info('Configuring Security Group \'%s\'' % [oConfig.get('security_group')])
      security_group = SecurityGroup.get_or_create_security_group(oFC, oConfig.get('security_group'))
      ports = oConfig.get('ports')

      Logging.state('Configuring security group ports...') #################
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

      ENV['FORJ_HPC'] = oFC.sAccountName
      ENV['FORJ_HPC_NET'] = network.name
      ENV['FORJ_SECURITY_GROUP'] = oConfig.get('security_group')
      ENV['FORJ_KEYPAIR'] = oConfig.get('keypair_name')
      ENV['FORJ_HPC_NOVA_KEYPUB'] = oConfig.get('keypair_path') + '.pub'
      ENV['FORJ_BASE_IMG'] = oConfig.get('image')

      # run build.sh to boot maestro
      puts

      build = 'bin/build.sh' unless build

      build_config = oConfig.get('build_config') unless build_config

      branch = oConfig.get('branch') unless branch

      box_name = oConfig.get('box_name') unless box_name

      meta = '--meta blueprint=%s ' % [blueprint]

      command = '%s --build_ID %s --box-name %s --build-conf-dir %s --build-config %s --gitBranch %s --debug-box %s' % [build, name, box_name, infra_dir, build_config, branch, meta]

      maestro_build_path = File.expand_path('~/.forj/maestro/build')

      current_dir = Dir.pwd

      Dir.chdir(File.expand_path('~/.forj/maestro/build'))

      Logging.info("Calling '%s' from '%s'" %  [build, Dir.pwd])
      Logging.debug(command)
      Kernel.system(ENV, command)
      Dir.chdir(current_dir)

      if test
        Logging.debug 'test flag is on, deleting objects'
        Network.delete_router_interface(subnet.id, router)
        Network.delete_subnet(subnet.id)
        Network.delete_network(network.name)
      end

    rescue Interrupt
      Logging.message("\n'%s' boot from '%s' interrupted by user" % [name, blueprint])
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end
end
