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
    home = File.expand_path('~')
    path = home + '/.forj/'
    infra = path + 'infra/'

    if File.directory?(infra)
      FileUtils.rm_r(infra)
    end
    Dir.mkdir(infra)

    command = 'cp -rp ~/.forj/maestro/templates/infra/cloud-init ~/.forj/infra/'
    Kernel.system(command)

    fill_template = 'python %s/build_tmpl/build-env.py -p ~/.forj/infra --maestro-path %s' % [$LIB_PATH, maestro_repo]
    Kernel.system(fill_template)
  end
end
