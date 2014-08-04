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
      key_name, key_path, region, catalog,
      test = false)
    begin
      initial_msg = 'booting %s on %s' % [blueprint , cloud_provider]

      Logging.info(initial_msg)
      puts (initial_msg)

      forj_dir = File.expand_path(File.dirname(__FILE__))
      Dir.chdir(forj_dir)

      if catalog
        definitions = YamlParse.get_values(catalog)
      else
        definitions = YamlParse.get_values('catalog.yaml')
      end

      maestro_url =  definitions['default']['maestro']

      #Repositories.clone_repo(maestro_url)

      network = Network.get_or_create_network(definitions[blueprint]['network'])
      begin
        subnet = Network.get_or_create_subnet(network.id, name)
        router = Network.get_router(definitions[blueprint]['router'])
        Network.create_router_interface(subnet.id, router)
      rescue => e
        puts e.message
      end

      security_group = SecurityGroup.get_or_create_security_group(definitions[blueprint]['security_group'])

      key_name = definitions[blueprint]['keypair_name'] unless key_name
      key_path = definitions[blueprint]['keypair_path'] unless key_path
      SecurityGroup.upload_existing_key(key_name, key_path)

      ports = definitions[blueprint]['ports']

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
      current_dir = Dir.pwd
      home = Helpers.get_home_path
      build_path = home + '/.forj/maestro/build'
      Dir.chdir(build_path)

      build = 'bin/build.sh' unless build

      build_config_dir = definitions[blueprint]['build_config_dir'] unless build_config_dir

      build_config = definitions[blueprint]['build_config'] unless build_config

      branch = definitions[blueprint]['branch'] unless branch

      box_name = definitions[blueprint]['box_name'] unless box_name

      meta = '--meta blueprint=%s --meta HPCLOUD_PRIV=~/.cache/forj/master.forj-13.5.g64' % [blueprint]

      command = '%s --build_ID %s --box-name %s --build-conf-dir %s --build-config %s --gitBranch %s --debug-box %s' % [build, name, box_name, build_config_dir, build_config, branch, meta]

      Logging.info('using build.sh for %s' % [name])
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
