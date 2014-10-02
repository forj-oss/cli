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

def rhExist?(yVal, *p)

   if p.length() == 0
      return 0
   end
   return 0 if yVal.class != Hash
   p=p.flatten
   if p.length() == 1
      return 1 if yVal.key?(p[0])
      return 0
   end
   return 0 if yVal.nil? or not yVal.key?(p[0])
   ret = 0
   ret = rhExist?(yVal[p[0]], p.drop(1)) if yVal[p[0]].class == Hash
   return 1 + ret
end

def rhGet(yVal, *p)

   if p.length() == 0 or not yVal
      return nil
   end
   return nil if yVal.class != Hash
   p=p.flatten
   if p.length() == 1
      return yVal[p[0]] if yVal.key?(p[0])
      return nil
   end
   return nil if not yVal
   return rhGet(yVal[p[0]], p.drop(1)) if yVal.key?(p[0])
   nil
end

def rhSet(yVal, value, *p)
   if p.length() == 0
      return yVal
   end
   p=p.flatten
   if p.length() == 1
      if not yVal.nil?
         if value
            yVal[p[0]] = value
         else
            yVal.delete(p[0])
         end
         return yVal
      end
      if value
         ret = { p[0] => value }
      else
         ret = {}
      end
      return ret
   end
   if not yVal.nil?
      yVal[p[0]] = {} if not yVal[p[0]] or yVal[p[0]].class != Hash
      ret=rhSet(yVal[p[0]], value, p.drop(1))
      return yVal
   else
      ret = rhSet(nil, value, p.drop(1))
      return { p[0] => ret }
   end
end

def rhKeyToSymbol(yVal, levels = 1)
   return nil if yVal.nil? or yVal.class != Hash
   yRes = {}
   yVal.each { | key, value |
   if key.class == String
      if levels <= 1
         yRes[key.to_sym] = value
      else
         yRes[key.to_sym] = rhKeyToSymbol(value, levels - 1)
      end
   else
      if levels <= 1
         yRes[key] = value
      else
         yRes[key] = rhKeyToSymbol(value, levels - 1)
      end
   end
   }
   yRes
end

def rhKeyToSymbol?(yVal, levels = 1)
   return false if yVal.nil? or yVal.class != Hash
   yVal.each { | key, value |
   if key.class == String
      return true
   end
   if levels >1
      res = rhKeyToSymbol?(value, levels - 1)
      return true if res
   end
   }
   false
end

class ForjDefault

   # @sDefaultsName='defaults.yaml'
   # @yDefaults = defaults.yaml file data hash

   # Load yaml documents (defaults)
   # If config doesn't exist, it will be created, empty with 'defaults:' only


   def self.exist?(key, section = :default)
      key = key.to_sym if key.class == String
      (rhExist?(@@yDefaults, section, key) == 2)
   end

   def self.get(key, section = :default)
      key = key.to_sym if key.class == String
      return(rhGet(@@yDefaults, section, key)) if key
      rhGet(@@yDefaults, section) if not key
   end

   def self.dump()
      @@yDefaults
   end
      # Loop on Config metadata
   def self.meta_each
      rhGet(@@yDefaults, :sections).each { | section, hValue |
         hValue.each { | key, value |
            yield section, key, value
            }
         }
   end

   def self.meta_exist?(key)
      return nil if not key
      
      key = key.to_sym if key.class == String
      section = rhGet(@@account_section_mapping, key)
      rhExist?(@@yDefaults, :sections, section, key) == 3
   end
   
   def self.build_section_mapping
      @@account_section_mapping = {}
      rhGet(@@yDefaults, :sections).each { | section, hValue |
         next if section == :default
         hValue.each_key { | map_key |
            Logging.fatal(1, "defaults.yaml: Duplicate entry between sections. '%s' defined in section '%s' already exists in section '%s'" % [map_key, section, rhGet(@account_section_mapping, map_key) ])if rhExist?(@account_section_mapping, map_key) != 0
            rhSet(@@account_section_mapping, section, map_key)
            }
         }
   end

   def self.get_meta_section(key)
      key = key.to_sym if key.class == String
      rhGet(@@account_section_mapping, key)
   end

   if not $LIB_PATH
      Logging.fatal(1, 'Internal $LIB_PATH was not set.')
   end

   Logging.info('Reading default configuration...')

   @@sDefaultsName=File.join($LIB_PATH,'defaults.yaml')

   @@yDefaults=YAML.load_file(@@sDefaultsName)
   
   self.build_section_mapping
end

class ForjConfig

   # Internal Object variables:
   # @sConfigName= 'config.yaml'
   # @yRuntime   = data in memory.
   # @yLocal     = config.yaml file data hash.
   # @yObjConfig = Extra loaded data
   # ForjDefault  = Application defaults class

   attr_reader :sConfigName

   # Load yaml documents (defaults + config)
   # If config doesn't exist, it will be created, empty with 'defaults:' only

   def default_dump(interms = nil)
      # Build a config hash.

      res = {}
      ForjDefault.dump[:default].each_key { |key|
         dump_key = exist?(key)
         rhSet(res, get(key), dump_key, key)
         }
      if rhExist?(@yLocal, :default) == 1
         @yLocal[:default].each_key { |key|
         dump_key = exist?(key)
         rhSet(res, get(key), dump_key, key) if rhExist?(res, dump_key, key) != 2
         }
      end
      if interms
         if interms.instance_of? Hash
            @interms.each_key { | key|
               dump_key = exist?(key)
               rhSet(res, get(key), dump_key, key) if rhExist?(res, dump_key, key) != 2
               }
         elsif interms.instance_of? Array # Array of hash of hash
            interms.each { | elem |
               elem.each_key { | key|
               dump_key = exist?(key)
                  rhSet(res, get(key), dump_key, key) if rhExist?(res, dump_key, key) != 2
                  }
               }
         end
      end
      @yRuntime.each_key { |key|
         dump_key = exist?(key)
         rhSet(res, get(key), dump_key, key) if rhExist?(res, dump_key, key) != 2
         }

      res
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

      if File.exists?(@sConfigName)
         @yLocal = YAML.load_file(@sConfigName)
         if rhKeyToSymbol?(@yLocal, 2)
            @yLocal = rhKeyToSymbol(@yLocal, 2) 
            self.SaveConfig()
         end

      else
         @yLocal = { :default => nil }
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
     Logging.info('Configuration file "%s" updated.' % @sConfigName)
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
         Logging.info('Configuration file "%s" updated.' % sFile)
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

      key = key.to_sym if key.class == String

      return(rhExist?(@yObjConfig, section, name) == 2) if not key
      return(rhExist?(@yObjConfig, section, name, key) == 3)
   end

   def ExtraGet(section, name, key = nil, default = nil)
      return nil if not section or not name

      key = key.to_sym if key.class == String
      return default unless ExtraExist?(section, name, key)
      return rhGet(@yObjConfig, section, name, key) if key
      rhGet(@yObjConfig, section, name)
   end

   def ExtraSet(section, name, key, value)
     key = key.to_sym if key.class == String
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
      
      key = key.to_sym if key.class == String
      return false if key.class != Symbol

      if value
         rhSet(@yRuntime, value, key)
      else
         @yRuntime.delete(key)
      end
      true
   end

   def runtimeExist?(key)
      (rhExist?(@yRuntime, key) == 1)
   end

   def runtimeGet(key)
      rhGet(@yRuntime, key) if runtimeExist?(key)
   end

   def get(key, interms = nil, default = nil)
      key = key.to_sym if key.class == String
      return nil if key.class != Symbol
      # If key is in runtime
      return runtimeGet(key) if runtimeExist?(key)
      # Check data in intermediate hashes or array of hash. (like account data - key have to be identical)
      if interms
         if interms.instance_of? Hash
            return rhGet(interms, key) if rhExist?(interms, key) == 1
         elsif interms.instance_of? Array # Array of hashes
            iCount=0
            oVal = nil
            interms.each { | elem |
               if elem.class == Hash
                  elem.each { | hashkey, value |
                     if value.class == Hash and rhExist?(elem, hashkey, key) == 2 # hash of hash
                        oVal = rhGet(elem, hashkey, key)
                        break
                     elsif value.class != Hash and rhExist?(elem, hashkey) == 1 # single hash: key = value.
                        oVal = rhGet(elem, hashkey)
                        break

                     end
                     }
                  break if oVal
               end
               iCount += 1
               }
            return oVal
         end
      end
      # else key in local default config of default section.
      return LocalGet(key) if LocalDefaultExist?(key)
      # else key in application defaults
      return ForjDefault.get(key) if ForjDefault.exist?(key)
      # else default
      default
   end

   def getAppDefault(section, key = nil)

      key = key.to_sym if key.class == String

      ForjDefault.get(key, section)
   end

   def exist?(key, interms = nil)
      key = key.to_sym if key.class == String

      # Check data in intermediate hashes or array of hash. (like account data - key have to be identical)
      return "runtime" if rhExist?(@yRuntime, key) == 1
      if interms
         if interms.instance_of? Hash
            return 'hash' if rhExist?(interms, key) == 1
         elsif interms.instance_of? Array # Array of hash
            iCount = 0
            interms.each { | elem |
               if elem.class == Hash
                  elem.each { | hashkey, value |
                     return ("%s" % hashkey)  if value.class == Hash and rhExist?(elem, hashkey, key) == 2
                     return ("hash[%s]" % iCount)  if value.class != Hash and rhExist?(elem, hashkey) == 1
                     }
               end
               iCount += 1
               }
         end
      end
      return 'local' if LocalDefaultExist?(key)
      # else key in application defaults
      return 'default' if ForjDefault.exist?(key)
      false
   end

   def LocalDefaultExist?(key)
      LocalExist?(key)
   end

   def LocalExist?(key, section = :default)

      key = key.to_sym if key.class == String
      return true if rhExist?(@yLocal, section, key) == 2
      false
   end

   def LocalSet(key, value, section = :default)
     key = key.to_sym if key.class == String
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

   def LocalGet(key, section = :default, default = nil)
     key = key.to_sym if key.class == String

     return default if rhExist?(@yLocal, section, key) != 2
     rhGet(@yLocal, section, key)
   end

   def LocalDel(key, section = :default)
     key = key.to_sym if key.class == String
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

   def meta_each
      ForjDefault.meta_each { |section, key, value| 
         next if rhGet(value, :account_exclusive)
         yield section, key, value
      }
   end

end
