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

   def exist?(key, section = 'default')
      (rhExist?(@yDefaults, section, key) == 2)
   end

   def get(key, section = 'default')
      rhGet(@yDefaults, section, key)
   end

   def dump()
      @yDefaults
   end
end

class ForjConfig

   # Internal Object variables:
   # @sConfigName= 'config.yaml'
   # @yRuntime   = data in memory.
   # @yLocal     = config.yaml file data hash.
   # @yObjConfig = Extra loaded data
   # @oDefaults  = Application defaults object

	attr_reader :sConfigName

   # Load yaml documents (defaults + config)
   # If config doesn't exist, it will be created, empty with 'defaults:' only

   def default_dump()
      @oDefaults.dump()
   end

   def initialize(sConfigName=nil)

      if not $FORJ_DATA_PATH
         Logging.fatal(1, 'Internal $FORJ_DATA_PATH was not set.')
      end

      sConfigDefaultName='config.yaml'

      if sConfigName
         if File.dirname(sConfigName) == '.'
            sConfigName = File.join($FORJ_DATA_PATH,sConfigName)
         end
         sConfigName = File.expand_path(sConfigName)
         if not File.exists?(sConfigName)
            Logging.warning("Config file '%s' doesn't exists. Using default one." % [sConfigName] )
            @sConfigName = File.join($FORJ_DATA_PATH,sConfigDefaultName)
         else
            @sConfigName = sConfigName
         end
      else
         @sConfigName = File.join($FORJ_DATA_PATH,sConfigDefaultName)
      end

      @oDefaults = ForjDefault.new

      if File.exists?(@sConfigName)
         @yLocal = YAML.load_file(@sConfigName)
      else
         @yLocal = { 'default' => nil }
         # Write the empty file
         Logging.info('Creating your default configuration file ...')
         self.SaveConfig()
      end

      @yRuntime = {}
      @yObjConfig = {}
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
      hVal = rhGet(@yObjConfig, section, name)
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
         rhSet(@yObjConfig, hVal, section, name)
         hVal
      end
   end

   def ExtraExist?(section, name, key = nil)
      return nil if not section or not name

      return(rhExist?(@yObjConfig, section, name) == 2) if not key
      return(rhExist?(@yObjConfig, section, name, key) == 3)
   end

   def ExtraGet(section, name, key = nil, default = nil)
      return nil if not section or not name

      return default unless ExtraExist?(section, name, key)
      return rhGet(@yObjConfig, section, name, key) if key
      rhGet(@yObjConfig, section, name)
   end

   def ExtraSet(section, name, key = nil, value)
      if key
         rhSet(@yObjConfig, value, section, name, key)
      else
         rhSet(@yObjConfig, value, section, name)
      end
   end

   def set(key, value)
      # Function to set a runtime key/value, but remove it if value is nil.
      # To set in config.yaml, use LocalSet
      # To set on extra data, like account information, use ExtraSet
      if not key
         return false
      end
      if value
         rhSet(@yRuntime, value, key)
      else
         @yRuntime.delete(key)
      end
      true
   end

   def get(key, interms = nil, default = nil)
      # If key is in runtime
      return rhGet(@yRuntime, key) if rhExist?(@yRuntime, key) == 1
      # Check data in intermediate hashes or array of hash. (like account data - key have to be identical)
      if interms
         if interms.instance_of? Hash
            return rhGet(interms, key) if rhExist?(interms, key) == 1
         elsif interms.instance_of? Array # Array of hash
            iCount=0
            interms.each { | elem |
               if elem.class == Hash and rhExist?(elem, key) == 1
                  break
               end
               iCount += 1
               }
            return rhGet(interms[iCount], key) if iCount< interms.length()
         end
      end
      # else key in local default config of default section.
      return LocalGet(key) if LocalDefaultExist?(key)
      # else key in application defaults
      return @oDefaults.get(key) if @oDefaults.exist?(key)
      # else default
      default
   end

   def getAppDefault(section, key)
      @oDefaults.get(key, section)
   end

   def exist?(key, interms = nil)
      # Check data in intermediate hashes or array of hash. (like account data - key have to be identical)
      return "runtime" if rhExist?(@yRuntime, key) == 1
      if interms
         if interms.instance_of? Hash
            return 'hash' if rhExist?(interms, key) == 1
         elsif interms.instance_of? Array # Array of hash
            iCount = 0
            Array.each { | elem |
               return ("array[%s]" % iCount)  if elem.class == Hash and rhExist?(elem, key) == 1
               iCount += 1
               }
         end
      end
      return 'local' if LocalDefaultExist?(key)
      # else key in application defaults
      return 'default' if @oDefaults.exist?(key)
      false
   end

   def LocalDefaultExist?(key)
      LocalExist?(key)
   end

   def LocalExist?(key, section = 'default')
      return true if rhExist?(@yLocal, section, key) == 2
      false
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
     return true
   end

   def LocalGet(key, section = 'default', default = nil)
     return default if rhExist?(@yLocal, section, key) != 2
     rhGet(@yLocal, section, key)
   end

   def LocalDel(key, section = 'default')
     if not key
        return false
     end
     if not @yLocal.has_key?(section)
        return false
     end
     @yLocal[section].delete(key)
     return true
   end

   # Function to return in fatal error if a config data is nil. Help to control function requirement.
   def fatal_if_inexistent(key)
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
