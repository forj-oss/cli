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
         Logging.fatal(1, 'Internal $LIB_PATH was not set.')
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
         Logging.fatal(1, 'Internal $FORJ_DATA_PATH was not set.')
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
         # Write the empty file
         Logging.info ('Creating your default configuration file ...')
         self.SaveConfig()
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

   def ExtraSave(sFile, section, name)
      hVal = rhGet(@Default.yDefaults, :extra_loaded, section, name)
      if hVal
         begin
            File.open(sFile, 'w') do |out|
               YAML.dump(hVal, out)
            end
         rescue => e
            Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
            return false
         end
         Logging.info ('Configuration file "%s" updated.' % sFile)
         return true
      end
   end

   def ExtraLoad(sFile, section, name)
      if File.exists?(sFile)
         hVal = YAML.load_file(sFile)
         rhSet(@Default.yDefaults, hVal, :extra_loaded, section, name)
      end
      BuildConfig()
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

   def LocalGet(key, section = 'default', default = nil)
      if @yLocal.has_key?(key)
         return @yLocal[key]
      end
      default
   end

   def LocalDel(key, section = 'default')
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

   def ExtraExist?(section, name, key)
      return nil if not section or not name
      
      return(rhExist?(@yConfig, :extra_loaded, section, name) == 3) if not key
      return(rhExist?(@yConfig, :extra_loaded, section, name, key) == 4)
   end

   def ExtraGet(section, name, key = nil, default = nil)
      return nil if not section or not name
      
      if key
         return default unless ExtraExist?(section, name, key)
         rhGet(@yConfig, :extra_loaded, section, name, key)
      else
         return default unless rhExist?(@yConfig, :extra_loaded, section, name) == 3
         rhGet(@yConfig, :extra_loaded, section, name)
      end   
   end

   def ExtraSet(section, name, key, value)
      rhSet(@yConfig, value, :extra_loaded, section, name, key)
   end

   def set(key, value, par = {})
      # Function to set a config key, but remove it if value is nil.
      if not key
         return false
      end
      if par[:section] and par[:name]
         # Set data in extra_loaded
         ExtraSet(par[:section], par[:name], key, value)
      elsif par[:section]
         # To set key=value on config.yaml, use LocalSet
         if value
            rhSet(@yRuntime, value, par[:section], key)
         else
            hVal = rhGet(@yRuntime, par[:section])
            hVal.delete(key)
         end
      else
         if value
            rhSet(@yRuntime, value, key)
         else
            @yRuntime.delete(key)
         end
      end
      true
   end

   def get(key, par = {})
      if par[:section] and par[:name]
         # Get data only from extra_loaded
         return ExtraGet(par[:section], par[:name], key, par[:default])
      elsif par[:section]
         # If section/key is in runtime
         return rhGet(@yRuntime, par[:section], key) if rhExist?(@yRuntime, par[:section], key) == 2
         # If section/key is in default config
         return rhGet(@yConfig,  par[:section], key) if rhExist?(@yConfig,  par[:section], key) == 2
      else
         # If key is in runtime
         return rhGet(@yRuntime, key) if rhExist?(@yRuntime, key) == 1
      end
      # else key in default config of default section.
      return rhGet(@yConfig, 'default', key) if rhExist?(@yConfig, 'default', key) == 2
      # else default
      par[:default]
   end

   def exist?(key, par = {})
      if par[:section] and par[:name]
         # section/name/key exist in extra_loaded ?
         return ExtraExist?(par[:section], par[:name], key)
      elsif par[:section]
         # section/key exist in runtime?
         return "runtime" if rhExist?(@yRuntime, par[:section], key) == 2
         # section/key exist in default config ?
         return "default" if rhExist?(@yConfig, par[:section], key) == 2
      else
         return "runtime" if rhExist?(@yRuntime, key) == 1
         return "default" if rhExist?(@yRuntime, 'default', key) == 2
      end
      false
   end

   def BuildConfig()
      # This function implements the logic to get defaults, superseed by local config.
      # Take care of ports array, which is simply merged.

      @yConfig = @Default.yDefaults.clone
      if @yLocal['default']
         @yConfig['default'].merge!(@yLocal['default']) { |key, oldval, newval| key == 'ports'? newval.clone.push(oldval.clone).flatten: newval }
      end
      @yConfig.merge!(@yLocal) { |key, oldval, newval| (key == 'default' or key == :extra_load)? oldval: newval }
   end

   def LocalDefaultExist?(key)
      return true if @yLocal['default'][key]
      false
   end

   def fatal_if_inexistent(key)
      # Function to return in fatal error if a config data is nil. Help to control function requirement.
      Logging.fatal(1, "Internal error - %s: '%s' is missing" % [caller(), key]) if not self.get(key)
   end
end

def rhExist?(yVal, *p)

   if p.length() == 0
      return 0
   end
   return 0 if yVal.class != Hash
   p=p.flatten
   if p.length() == 1
      return 1 if yVal[p[0]]
      return 0
   end
   return 0 if not yVal or not yVal[p[0]]
   ret = rhExist?(yVal[p[0]], p.drop(1)) if yVal[p[0]]
   return 1 + ret
   0
end

def rhGet(yVal, *p)

   if p.length() == 0 or not yVal
      return nil
   end
   p=p.flatten
   if p.length() == 1
      return yVal[p[0]] if yVal[p[0]]
      return nil
   end
   return nil if not yVal
   return rhGet(yVal[p[0]], p.drop(1)) if yVal[p[0]]
   nil
end

def rhSet(yVal, value, *p)
   if p.length() == 0
      return yVal
   end
   p=p.flatten
   if p.length() == 1
      if yVal
         yVal[p[0]] = value
         return yVal
      end
      ret = { p[0] => value }
      return ret
   end
   if yVal
      yVal[p[0]] = {} if not yVal[p[0]] or yVal[p[0]].class != Hash
      ret=rhSet(yVal[p[0]], value, p.drop(1))
      return yVal
   else
      ret = rhSet(nil, value, p.drop(1))
      return { p[0] => ret }
   end
end
