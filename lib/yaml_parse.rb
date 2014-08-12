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
require 'yaml'
require_relative 'log.rb'
include Logging

#
# YamlParse module
#
module YamlParse
  def get_values(path_to_yaml)
    begin
      Logging.info('getting values from defaults.yaml, this will be a service catalog.forj.io')
      YAML.load_file(path_to_yaml)
    rescue => e
      Logging.error(e.message)
    end
  end

  def dump_values(string, path)
    begin
      File.open(path, 'w') do |out|
        YAML.dump(string, out)
      end
    rescue => e
      Logging.error(e.message)
    end
  end
end
