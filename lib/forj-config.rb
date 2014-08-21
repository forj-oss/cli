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

#require_relative 'log.rb'
#include Logging

class ForjDefault

   # @sDefaultsName='defaults.yaml'
   # @yDefaults = defaults.yaml file data hash

   attr_reader   :yDefaults
   
   def initialize()
      # Load yaml documents (defaults)
      # If config doesn't exist, it will be created, empty with 'defaults:' only

      if not $LIB_PATH
         raise 'Internal $LIB_PATH was not set.'
      end
      
      Logging.info ('Reading default configuration...')

      @sDefaultsName=File.join($LIB_PATH,'defaults.yaml')

      @yDefaults=YAML.load_file(@sDefaultsName)
   end

end

class ForjConfig 

   # Internal variables:
   # @sConfigName='config.yaml'
   # @yRuntime = data in memory.
   # @yLocal = config.yaml file data hash.
   # @yConfig = defaults.yaml + local_config data hash
   
   attr_reader   :yLocal
   attr_reader   :yConfig
   attr_reader   :sConfigName

   def initialize(sConfigName=nil)
      # Load yaml documents (defaults + config)
      # If config doesn't exist, it will be created, empty with 'defaults:' only


      if not $FORJ_DATA_PATH
         raise 'Internal $FORJ_DATA_PATH was not set.'
      end

      sConfigDefaultName='config.yaml'

      if sConfigName
         if File.dirname(sConfigName) == '.'
            sConfigName= File.join($FORJ_DATA_PATH,sConfigName)
         end  
         sConfigName = File.expand_path(sConfigName)
         if not File.exists?(sConfigName)
            Logging.warning("Config file '%s' doesn't exists. Using default one." % [sConfigName] )
            @sConfigName=File.join($FORJ_DATA_PATH,sConfigDefaultName)
         else   
            @sConfigName=sConfigName
         end
      else
         @sConfigName=File.join($FORJ_DATA_PATH,sConfigDefaultName)
      end


      @Default=ForjDefault.new
      
    
      if File.exists?(@sConfigName)
         @yLocal=YAML.load_file(@sConfigName)
      else
         @yLocal={ 'default' => nil }
         if not File.exists?(@sConfigName)
            # Write the empty file
            if not File.exists?($FORJ_DATA_PATH)
               Dir.mkdir($FORJ_DATA_PATH)
            end
            Logging.info ('Creating your default configuration file ...')
            self.SaveConfig()
         end
      end
     
      BuildConfig()
      
      @yRuntime={}
   end


   def SaveConfig()
     begin
       File.open(@sConfigName, 'w') do |out|
         YAML.dump(@yLocal, out)
       end
     rescue => e
       Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
       return false
     end
     Logging.info ('Configuration file "%s" updated.' % @sConfigName)
     return true
   end
   
   def LocalSet(key, value, section = 'default')
     if not key or not value
        return false
     end
     if @yLocal[section] == nil
        @yLocal[section]={}
     end
     if @yLocal.has_key?(section)
        @yLocal[section].merge!({key => value})
     else
        @yLocal.merge!(section => {key => value})
     end   
     BuildConfig()
     return true
   end
   
   def LocalDel(key,section = 'default')
     if not key
        return false
     end
     if not @yLocal.has_key?(section)
        return false
     end   
     @yLocal[section].delete(key)
     BuildConfig()
     return true
   end
   
   def setDefault(key, value)
     if not key 
        return false
     end
     if not @yRuntime[key]
        @yRuntime[key] = value
     end   
     return true
   end
   
   def set(key, value)
     if not key 
        return false
     end
     if value
        @yRuntime[key] = value
     else
        @yRuntime.delete(key)
     end   
     return true
   end
  
   def get(key, default = @yConfig['default'][key])
     if @yRuntime.has_key?(key)
        @yRuntime[key]
     else
        default
     end
   end
  
   def BuildConfig()
      # This function implements the logic to get defaults, superseed by local config. 
      # Take care of ports array, which is simply merged.
      
      @yConfig={ 'default' => @Default.yDefaults['default'].clone }
      if @yLocal['default']
         @yConfig['default'].merge!(@yLocal['default']) { |key, oldval, newval| key == 'ports'? newval.clone.push(oldval.clone).flatten: newval }
      end   
      @yConfig.merge!(@yLocal) { |key, oldval, newval| key == 'default'? oldval: newval }
   end

end
