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


# puts "test_library included"

require 'rubygems'
require 'yaml'
require_relative 'log.rb'
include Logging

class ForjConfig

   # Internal variables:
   # @sDefaultsName='defaults.yaml'
   # @sConfigName='config.yaml'
   # @yLocal = config.yaml file data hash.
   # @yDefaults = defaults.yaml file data hash
   # @yConfig = defaults.yaml + local_config data hash

   attr_reader   :yDefaults
   attr_accessor :yLocal
   attr_reader   :yConfig

   def initialize(sConfigName=nil)
      # Load yaml documents (defaults + config)
      # If config doesn't exist, it will be created, empty with 'defaults:' only

      puts ('INFO: Reading default configuration...')

      @sDefaultsName=File.join($LIB_PATH,'defaults.yaml')
      sConfigDefaultName='config.yaml'

      if sConfigName
         if not File.exists?(sConfigName)
            Logging.error('Config file %s doesn\'t exists. Using default one.')
            @sConfigName=File.join($FORJ_DATA_PATH,sConfigDefaultName)
         else
            @sConfigName=sConfigName
         end
      else
         @sConfigName=File.join($FORJ_DATA_PATH,sConfigDefaultName)
      end

      @yDefaults=YAML.load_file(@sDefaultsName)
      @yConfig=@yDefaults.clone

      if File.exists?(@sConfigName)
         @yLocal=YAML.load_file(@sConfigName)
      else
         @yLocal={ 'default' => nil }
         if not File.exists?(@sConfigName)
            # Write the empty file
            if not File.exists?($FORJ_DATA_PATH)
               Dir.mkdir($FORJ_DATA_PATH)
            end
            puts ('INFO: Creating your default configuration file ...')
            self.SaveConfig()
         end
      end

      if @yLocal['default']
         @yLocal['default'].each do | key, value |
            if key == 'ports'
               # merging ports array.
               @yConfig['default']['ports'].concat(value)
            else
               if @yConfig['default'][key]
                  @yConfig['default'][key]=value
               end
            end
         end
      end
   end

   def SaveConfig()
     begin
       File.open(@sConfigName, 'w') do |out|
         YAML.dump(@yLocal, out)
       end
     rescue => e
       Logging.error(e.message)
     end
     puts ('INFO: Configuration file "%s" updated.' % @sConfigName)
   end
end
