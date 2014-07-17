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
           build, build_config_dir, build_config,
           branch, git_repo, boothook, box_name,
           test = false)
    begin
      initial_msg = 'booting %s on %s' % [blueprint , cloud_provider]

      Logging.info(initial_msg)
      puts (initial_msg)

      forj_dir = File.expand_path(File.dirname(__FILE__))
      Dir.chdir(forj_dir)
      definitions = YamlParse.get_values('catalog.yaml')

      maestro_url =  definitions['default']['maestro']

      Repositories.clone_repo(maestro_url)

      network = Network.create_network(name)
      subnet = Network.create_subnet(network.id, name)
      router = Network.get_router(definitions[blueprint]['router'])
      Network.create_router_interface(subnet.id, router)

      security_group = SecurityGroup.create_security_group(blueprint)

      ports = definitions['redstone']['ports']

      ports.each do|port|
        Network.create_security_group_rule(security_group.id, 'tcp', port, port)
      end

      ENV['FORJ_HPC_NETID'] = network.id
      ENV['FORJ_SECURITY_GROUP'] = security_group.name
      #ENV['FORJ_KEYPAIR'] = definitions[blueprint]['keypair']
      #ENV['FORJ_HPC_NOVA_KEYPUB'] = definitions[blueprint]['keypair']

      # run build.sh to boot maestro
      current_dir = Dir.pwd
      home = Helpers.get_home_path
      build_path = home + '/.forj/maestro/build'
      Dir.chdir(build_path)

      build = 'bin/build.sh' unless build

      build_config_dir = '~/.forj/maestro/build/conf' unless build_config_dir

      build_config = 'box' unless build_config

      branch = 'master' unless branch

      git_repo = 'review:forj-oss/maestro' unless git_repo

      box_name = 'maestro' unless box_name

      boothook = '~/.forj/maestro/build/bin/build-tools/boothook.sh' unless boothook

      command = '%s --build_ID %s --box-name %s --build-conf-dir %s --build-config %s --gitBranch %s --gitRepo %s --boothook %s' % [build, name, box_name, build_config_dir, build_config, branch, git_repo, boothook]

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
    end
  end
end
