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
require_relative 'log.rb'
include Logging
require_relative 'helpers.rb'
include Helpers


#
# Boot module
#
module Boot
  def boot(blueprint, cloud_provider, name,
      build, infra_dir, build_config,
      branch, git_repo, boothook, box_name,
      key_name, key_path, region, config,
      test = false)
    begin
      initial_msg = 'booting %s on %s (~/.forj/forj.log)' % [blueprint , cloud_provider]

      Logging.info(initial_msg)

      forj_dir = File.expand_path(File.dirname(__FILE__))
      Dir.chdir(forj_dir)

      oConfig=ForjConfig.new(config)
      hConfig=oConfig.yConfig['default']

      # Initialize defaults
      maestro_url =  hConfig['maestro_url']

      infra_dir = hConfig['infra_repo'] unless infra_dir

      # Ask information if needed.
      bBuildInfra=false
      if not Dir.exist?(File.expand_path(infra_dir))
         sAsk = 'Your \'%s\' infra directory doesn\'t exist. Do you want to create a new one from Maestro(repo github)/templates/infra (yes/no)?' % [infra_dir]
         bBuildInfra=agree(sAsk)
      else
         puts('INFO: Re-using your infra... in \'%s\'' % [infra_dir])
      end
      if not Dir.exist?(File.expand_path(infra_dir)) and not bBuildInfra
         puts ('Exiting.')
         return
      end

      # Step Maestro Clone
      puts('INFO: cloning maestro repo from \'%s\'...' % maestro_url)
      Repositories.clone_repo(maestro_url)

      if bBuildInfra
         puts('INFO: Building your infra... in \'%s\'' % [infra_dir])
         Repositories.create_infra
      end

      puts('INFO: Configuring network \'%s\'' % [hConfig['network']])
      network = Network.get_or_create_network(hConfig['network'])
      begin
        subnet = Network.get_or_create_subnet(network.id, name)
        router = Network.get_router(hConfig['router'])
        Network.create_router_interface(subnet.id, router)
      rescue => e
        puts e.message
      end


      puts('INFO: Configuring keypair \'%s\'' % [hConfig['keypair_name']])
      key_name = hConfig['keypair_name'] unless key_name
      key_path = hConfig['keypair_path'] unless key_path
      SecurityGroup.upload_existing_key(key_name, key_path)

      puts('INFO: Configuring Security Group \'%s\'' % [hConfig['security_group']])
      security_group = SecurityGroup.get_or_create_security_group(hConfig['security_group'])
      ports = hConfig['ports']

      ports.each do|port|
        Network.get_or_create_rule(security_group.id, 'tcp', port, port)
      end

      ENV['FORJ_HPC_NETID'] = network.id
      ENV['FORJ_SECURITY_GROUP'] = security_group.name
      ENV['FORJ_KEYPAIR'] = key_name
      ENV['FORJ_HPC_KEYPUB'] = key_path
      if region
        ENV['FORJ_REGION'] = region
      end

      # run build.sh to boot maestro
      puts
      current_dir = Dir.pwd
      home = Helpers.get_home_path
      build_path = home + '/.forj/maestro/build'
      Dir.chdir(build_path)

      build = 'bin/build.sh' unless build

      build_config = hConfig['build_config'] unless build_config

      branch = hConfig['branch'] unless branch

      box_name = hConfig['box_name'] unless box_name

      meta = '--meta blueprint=%s ' % [blueprint]

      command = '%s --build_ID %s --box-name %s --build-conf-dir %s --build-config %s --gitBranch %s --debug-box %s' % [build, name, box_name, infra_dir, build_config, branch, meta]

      Logging.info('Calling build.sh')
      Logging.info(command)

      Kernel.system(command)
      Dir.chdir(current_dir)

      if test
        puts 'test flag is on, deleting objects'
        Network.delete_router_interface(subnet.id, router)
        Network.delete_subnet(subnet.id)
        Network.delete_network(network.name)
      end

    rescue SystemExit, Interrupt
      msg = '%s interrupted by user' % [name]
      puts msg
      Logging.info(msg)
    rescue StandardError => e
      Logging.error(e.message)
      puts e.backtrace.join("\n")

      puts e.message
    end
  end
end
