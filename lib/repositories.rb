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
require_relative 'log.rb'
include Logging

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
          Logging.info('cloning the maestro repo')
          Git.clone(maestro_url, 'maestro', :path => path)
        end
      rescue => e
        puts 'Error while cloning the repo from %s' % [maestro_url]
        puts 'If this error persist you could clone the repo manually in ~/.forj/'
        Logging.error(e.message)
      end
      Dir.chdir(current_dir)
    end
end