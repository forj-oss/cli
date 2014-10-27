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


# Those classes describes :
# - processes (BaseProcess)   : How to create/delete/edit/query object.
# - controler (BaseControler) : If a provider is defined, define how will do object creation/etc...
# - definition(BaseDefinition): Functions to declare objects, query/data mapping and setup
# this task to make it to work.

module ForjLib
   def ForjLib::debug(iLevel, sMsg)
      if iLevel <= $LIB_FORJ_DEBUG
         Logging.debug("-%s- %s" % [iLevel, sMsg])
      end
   end
end

module ForjLib
   class ForjLib::Data

      def initialize(oType = :object)
         # Support :data for single object data
         #         :list for a list of object data
         oType = :data if not [:list, :object, :data].include?(oType)
         @oType = oType
         case oType
            when :data, :object
               @data = new_object
            when :list
               @data = new_object_list
         end
      end

      def type?()
         @oType
      end

      def object_type?()
         @data[:object_type]
      end

      def set(oObj, sObjType = nil, hQuery = {})
         if oObj.is_a?(ForjLib::Data)
            oType = oObj.type?
            case oType
               when :data, :object
                  @data[:object_type] = oObj.object_type?
                  @data[:object] = oObj.get(:object)
                  @data[:attrs] = oObj.get(:attrs)
               when :list
                  @data[:object_type] = oObj.object_type?
                  @data[:object] = oObj.get(:object)
                  @data[:list] = oObj.get(:list)
                  @data[:query] = oObj.get(:query)
            end
            return self
         end

         # while saving the object, a mapping work is done?
         case @oType
            when :data, :object
               @data[:object_type] = sObjType
               @data[:object] = oObj
               @data[:attrs] = yield(sObjType, oObj)
            when :list
               @data[:object] = oObj
               @data[:object_type] = sObjType
               @data[:query] = hQuery
               unless oObj.nil?
                  begin
                     oObj.each { | oObject |
                        next if oObject.nil?
                        begin
                           oDataObject = ForjLib::Data.new(:object)

                           oDataObject.set(oObject, sObjType) { |sObjectType, oObject|
                              yield(sObjectType, oObject)
                           }
                           @data[:list] << oDataObject
                        rescue => e
                           raise ForjError.new(), "'%s' Mapping attributes issue.\n%s" % [sObjType, e.message]
                        end
                     }
                  rescue => e
                     raise ForjError.new(), "each function is not supported by '%s'.\n%s" % [oObj.class, e.message]
                  end
               end
         end
         self
      end

      def [](*key)
         get(*key)
      end

      def []=(*key, value)
         return false if @oType == :list
         rhSet(@data, value, :attrs, key)
         true
      end

      def get(*key)
         return @data if key.length == 0
         case @oType
            when :data, :object # Return only attrs or the real object.
               return @data[key[0]] if key[0] == :object
               return rhGet(@data, key) if key[0] == :attrs
               rhGet(@data, :attrs, key)
            when :list
               return @data[key[0]] if [:object, :query].include?(key[0])
               return @data[:list][key[0]] if key.length == 1
               @data[:list][key[0]][key[1..-1]] # can Return only attrs or the real object.
         end
      end

      def exist?(*key)
         case @oType
            when :data, :object
               return true if key[0] == :object and @data.key?(key[0])
               return true  if key[0] == :attrs and rhExist?(@data, key)
               (rhExist?(@data, :attrs, key) == key.length+1)
            when :list
               return true if key[0] == :object and @data.key?(key[0])
               (rhExist?(@data[:list][key[0]], :attrs, key[1..-1]) == key.length)
         end
      end

      def nil?()
         @data[:object].nil?
      end

      def length()
         case @oType
            when :data
               return 0 if self.nil?
               1
            when :list
               @data[:list].length
         end
      end

      def each(sData = :list)
         to_remove = []
         return nil if @oType != :list or not [:object, :list].include?(sData)

         @data[:list].each { |elem|
            sAction = yield (elem)
            case sAction
               when :remove
                  to_remove << elem
            end
         }
         if to_remove.length > 0
            to_remove.each { | elem |
               @data[:list].delete(elem)
            }
         end
      end

      def each_index(sData = :list)
         to_remove = []
         return nil if @oType != :list or not [:object, :list].include?(sData)

         @data[:list].each_index { |iIndex|
            sAction = yield (iIndex)
            case sAction
               when :remove
                  to_remove << @data[:list][iIndex]
            end
         }
         if to_remove.length > 0
            to_remove.each { | elem |
               @data[:list].delete(elem)
            }
         end
      end

      def registered?()
         @bRegister
      end

      def register()
         @bRegister = true
         self
      end

      def unregister()
         @bRegister = false
         self
      end
      private

      def new_object_list
         {
            :object        => nil,
            :object_type   => nil,
            :list          => [],
            :query         => nil
         }
      end

      def new_object
         oCoreObject = {
            :object_type => nil,
            :attrs => {},
            :object => nil,
         }
      end

   end
end

class ForjError < RuntimeError
   attr_reader :ForjMsg

   def initialize(message = nil)
      @ForjMsg = message
   end
end

# Class to handle key or keypath on needs
class KeyPath

   def initialize(sKeyPath = nil)

      @keypath = []
      self.set sKeyPath
   end

   def key=(sKeyPath)
      self.set(sKeyPath)
   end

   def set(sKeyPath)

      if sKeyPath.is_a?(Symbol)
         @keypath = [ sKeyPath]
      elsif sKeyPath.is_a?(Array)
         @keypath = sKeyPath
      elsif sKeyPath.is_a?(String)
         if /[^\\\/]?\/[^\/]/ =~ sKeyPath or /:[^:\/]/ =~ sKeyPath
            # keypath to interpret
            aResult = sKeyPath.split('/')
            aResult.each_index { | iIndex |
               next if not aResult[iIndex].is_a?(String)
               aResult[iIndex] = aResult[iIndex][1..-1].to_sym if aResult[iIndex][0] == ":"
            }
            @keypath = aResult
         else
            @keypath = [sKeyPath]
         end
      end
   end

   def aTree()
      @keypath
   end

   def sFullPath()
      return nil if @keypath.length == 0
      aKeyAccess = @keypath.clone
      aKeyAccess.each_index { |iIndex|
         next if not aKeyAccess[iIndex].is_a?(Symbol)
         aKeyAccess[iIndex] = ":" + aKeyAccess[iIndex].to_s
      }
      aKeyAccess.join('/')
   end

   def to_s
      return nil if @keypath.length == 0
      aKeyAccess = @keypath.clone
      aKeyAccess.each_index { |iIndex|
         next if not aKeyAccess[iIndex].is_a?(Symbol)
         aKeyAccess[iIndex] = aKeyAccess[iIndex].to_s
      }
      aKeyAccess.join('/')
   end

   def sKey(iIndex = -1)
      return nil if @keypath.length == 0
      @keypath[iIndex] if self.length >= 1
   end

   def length()
      @keypath.length
   end
end

# This is the main class definition.
# It drives creation of High level cloud class object, like servers
# Initialization requires a Configuration Object (ForjConfig) and the Account to load.
# Account is loaded with ForjAccount Object.
# During ForjCloud initialization, general options + account options are loaded.

# For example, to create a server

#   oCloud = ForjCloud.new(oConfig, 'myhpcloud')
#   oConfig.set(:server_name,'myservername')
#   oCloud.Create(:server)

# Most of data are predefined from account or general config.
# If some required value are missing, an error is reported.
# A Process Object can be defined, in order to add some process features, like :maestro_server

# Based Forj Object to use, with a process and (or not) a controler.
class ForjObject

   # ForjObject parameters are:
   # oForjConfig : Required. an instance of a configuration system which HAVE to provide
   #               2 kind of functions:
   #               - set (key, value) and []=(key, value)
   #                 From processes, you can set a runtime data with:
   #                    config.set(key, value)
   #                 OR
   #                    config[key] = value
   #
   #               - get (key, default) and [](key, default)
   #                 default is an optional value.
   #                 From processes, you can get a data (runtime/account/config.yaml or defaults.yaml) with:
   #                    config.get(key)
   #                 OR
   #                    config[key]

   # sProcessClass: Required. string or symbol. Is the name of ProcessClass to use.
   #                This class is dynamically loaded and derived from BaseProcess class.
   #                It loads the Process class content from a file '$CORE_PROCESS_PATH/<sProcessClass>.rb'
   #                If sProcessClass is a file path, this file will be loaded as a ruby include.

   # <sProcessClass>.rb file name is case sensible and respect RUBY Class name convention

   # sControllerClass: Optional. string or symbol. Is the name of ControlerClass to use.
   #                  This class is dynamically loaded and derived from BaseControler class.
   #                  It loads the Controler class content from a file '$PROVIDER_PATH/<sControlerClass>.rb'
   #
   #                  The provider can redefine partially or totally some processes
   #                  ForjObject will load those redefinition from file:
   #                  '$PROVIDER_PATH/<sControlerClass>Process.rb'

   # <sControllerClass>.rb or <sControllerClass>Process.rb file name is case sensible and respect RUBY Class name convention

   attr_reader :config


   def initialize(oForjConfig, processesClass = nil, sControllerClass = nil)
      # Loading ProcessClass
      # Create Process derived from respectively BaseProcess
      @config = oForjConfig

      if processesClass.nil?
         aProcessesClass = []
      elsif not processesClass.is_a?(Array)
         aProcessesClass = [processesClass]
      else
         aProcessesClass = processesClass
      end

      cBaseProcess = BaseProcess
      cProcessClass = nil

      aProcessesClass.each { | sProcessClass |
         ForjLib.debug(1, "Loading Process '%s'" % sProcessClass)

         # And load the content from the <sProcessClass>.rb
         if sProcessClass.is_a?(Symbol)
            sFile = File.join($CORE_PROCESS_PATH, sProcessClass.to_s + '.rb')
         else
            if sProcessClass.include?('/')
               # Consider a path to the process file. File name is the name of the class.
               sPath = File.dirname(File.expand_path(sProcessClass))
               file = File.basename(sProcessClass)
               file['.rb'] = '' if file['.rb']
               sProcessClass = file
               sProcessClass = file.capitalize if (/[A-Z]/ =~ file) != 0
            else
               sPath = $CORE_PROCESS_PATH
            end
            sFile = File.join(sPath, sProcessClass + '.rb')
         end
         if File.exists?(sFile)
            cNewClass = Class.new(cBaseProcess)
            sProcessClass = "%sProcess" %  sProcessClass if not /Process$/ =~ sProcessClass
            ForjLib.debug(1, "Declaring Process '%s'" % sProcessClass)
            cBaseProcess = Object.const_set(sProcessClass, cNewClass)
            cProcessClass = sProcessClass
            BaseDefinition.current_process(cBaseProcess)
            load sFile
         else
            Logging.warning("Process file definition '%s' is missing. " % sFile)
         end
      }

      if sControllerClass
         ForjLib.debug(1, "Loading Controler/definition '%s'" % sControllerClass)
         # Add Provider Object -------------
         sProviderClass = sControllerClass.capitalize

         # Initialize an empty class derived from BaseDefinition.
         # This to ensure provider Class will be derived from this Base Class
         # If this class is derived from a different Class, ruby will raise an error.

         # Create Definition and Controler derived from respectively BaseDefinition and BaseControler
         cBaseDefinition = Class.new(BaseDefinition)
         # Finally, name that class!
         Object.const_set sProviderClass, cBaseDefinition

         cBaseControler = Class.new(BaseController)
         Object.const_set sProviderClass + 'Controller', cBaseControler

         # Loading Provider base file. This file should load a class
         # which have the same name as the file.
         if sControllerClass.include?('/')
            # Consider a path to the process file. File name is the name of the class.
            sPath = File.dirname(File.expand_path(sControllerClass))
            file = File.basename(sControllerClass)
            file['.rb'] = '' if file['.rb']
            sControllerClass = file
         else
            sPath = File.join($PROVIDERS_PATH, sControllerClass)
         end
         sFile = File.join(sPath, sProviderClass + '.rb')
         if File.exists?(sFile)
            load sFile
         else
            raise ForjError.new(), "Provider file definition '%s' is missing. Cannot go on" % sFile
         end

         #cForjBaseCloud = Class.new(ForjBaseCloud)
         # Finally, name that class!
         #Object.const_set sProviderClass, cForjBaseCloud

         # Identify Provider Classes. Search for
         # - Definition Class (sProviderClass) - Contains ForjClass Object
         # - Controller Class (sProviderClass + 'Controller') - Provider Cloud controler object

         # Search for Definition Class
         begin
            # Get it from Objects
            oDefClass = Object.const_get(sProviderClass)
         rescue
            raise ForjError.new(), 'ForjCloud: Unable to find class "%s"' % sProviderClass
         end

         # Search for Controler Class
         # - Process Class (sProviderClass + 'Process') - Provider Process object if defined
         begin
            # Get the same one suffixed with 'Provider' from Objects
            oCoreObjectControllerClass = Object.const_get(sProviderClass + 'Controller')
         rescue
            raise ForjError.new(), 'ForjCloud: Unable to find class "%s"' % sProviderClass + 'Controller'
         end

         # Then, we create an BaseCloud Object with 2 objects joined:
         # ForjAccount and a BaseControler Object type


      else
         oCoreObjectControllerClass = nil
      end

      # Add Process management object ---------------
      unless cProcessClass.nil?
         begin
            oBaseProcessDefClass = Object.const_get(cProcessClass)
         rescue
            raise ForjError.new(), 'ForjCloud: Unable to find class "%s"' % cProcessClass
         end
      else
         raise ForjError.new(), 'ForjCloud: No valid process loaded. Aborting.'
      end
      # Ex: Hpcloud(ForjAccount, HpcloudProvider)
      if oCoreObjectControllerClass
         @oCoreObject = oDefClass.new(oForjConfig, oBaseProcessDefClass.new(), oCoreObjectControllerClass.new())
      else
         @oCoreObject = oDefClass.new(oForjConfig, oBaseProcessDefClass.new())
      end

   end

   def Connect(oCloudObj)
      return nil if not oCloudObj or not @oCoreObject
      @oCoreObject.Connect(oCloudObj)
   end

   def Create(oCloudObj)
      return nil if not oCloudObj or not @oCoreObject
      @oCoreObject.Create(oCloudObj)
   end

   def Delete(oCloudObj)
      return nil if not oCloudObj or not @oCoreObject

      @oCoreObject.Delete(oCloudObj)
   end

   def Query(oCloudObj, sQuery)
      return nil if not oCloudObj or not @oCoreObject

      @oCoreObject.Query(oCloudObj, sQuery)
   end

   def Get(oCloudObj, sId)
      return nil if not oCloudObj or not @oCoreObject or sId.nil?

      @oCoreObject.Get(oCloudObj, sId)
   end

   def Update(oCloudObj)
      return nil if not oCloudObj or not @oCoreObject

      @oCoreObject.Update(oCloudObj)
   end

   # Function used to ask users about setting up his account.
   def Setup(oCloudObj, sAccountName = nil)
      return nil if not oCloudObj or not @oCoreObject
      @oCoreObject.Setup(oCloudObj, sAccountName)
   end
end

# This class based on generic ForjObject, defines a Cloud Process to use.
class ForjCloud < ForjObject
   def initialize(oConfig, sAccount = nil, aProcesses = [])

      unless oConfig.is_a?(ForjAccount)
         oForjAccount = ForjAccount.new(oConfig)
         unless sAccount.nil?
            oForjAccount.ac_load(sAccount)
         end
      else
         oForjAccount = oConfig
      end
      aProcessList = [:CloudProcess]

      sControllerMod = oForjAccount.get(:provider_name)
      raise ForjError.new(), "Provider_name not set. Unable to create instance ForjCloud." if sControllerMod.nil?

      sControllerProcessMod = File.join($PROVIDERS_PATH, sControllerMod, sControllerMod.capitalize + "Process.rb")
      if File.exist?(sControllerProcessMod)
         aProcessList << sControllerProcessMod
      else
         ForjLib.debug(1, "No Provider process defined. File '%s' not found." % sControllerProcessMod)
      end

      super(oForjAccount, aProcessList.concat(aProcesses), sControllerMod)
   end
end


# class describing generic Object Process
# Ex: How to get a Network Object (ie: get a network or create it if missing)
class BaseProcess
   def initialize()
      @oDefinition = nil
   end

   def set_BaseObject(oDefinition)
      @oDefinition = oDefinition
   end
   private

   def controler
      raise ForjError.new(), "No Controler object loaded." if not @oDefinition
      @oDefinition
   end

   def object
      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition
   end

   def format_object(sObjectType, oMiscObj)

      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.format_object(sObjectType, oMiscObj)
   end

   def format_query(sObjectType, oMiscObj, hQuery)

      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.format_list(sObjectType, oMiscObj, hQuery)
   end

   def get_data(oObj, *key)

      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.get_data(oObj, :attrs, key)
   end

   def register(oObject, sObjectType = nil)

      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.register(oObject, sObjectType)
   end

   def config
      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.config
   end

   def query_single(sCloudObj, oList, sQuery, name, sInfoMsg = {})
      oList = controler.query(sCloudObj, sQuery)
      sInfo = {
         :notfound   => "No %s '%s' found",
         :checkmatch => "Found 1 %s. checking exact match for '%s'.",
         :nomatch    => "No %s '%s' match",
         :found      => "Found %s '%s'.",
         :more       => "Found several %s. Searching for '%s'.",
         :items_form => "%s",
         :items      => [:name]
      }
      sInfo[:notfound]     = sInfoMsg[:notfound]   if sInfoMsg.key?(:notfound)
      sInfo[:checkmatch]   = sInfoMsg[:checkmatch] if sInfoMsg.key?(:checkmatch)
      sInfo[:nomatch]      = sInfoMsg[:nomatch]    if sInfoMsg.key?(:nomatch)
      sInfo[:found]        = sInfoMsg[:found]      if sInfoMsg.key?(:found)
      sInfo[:more]         = sInfoMsg[:more]       if sInfoMsg.key?(:more)
      sInfo[:items]        = sInfoMsg[:items]      if sInfoMsg.key?(:items)
      sInfo[:items_form]   = sInfoMsg[:items_form] if sInfoMsg.key?(:items_form)
      case oList.length()
         when 0
            Logging.info( sInfo[:notfound] % [sCloudObj, name] )
            oList
         when 1
            ForjLib.debug(2, sInfo[:checkmatch] % [sCloudObj, name])
            element = nil
            oList.each { | oElem |
               bFound = true
               sQuery.each { | key, value |
                  if oElem[key] != value
                     bFound = false
                     break
                  end
               }
               :remove if not bFound
            }
            if oList.length == 0
               Logging.info(sInfo[:nomatch] % [sCloudObj, name])
            else
               sItems = []
               if sInfo[:items].is_a?(Array)
                  sInfo[:items].each { | key |
                     sItems << oList[0, key]
                  }
               else
                  sItems << oList[0, sInfo[:items]]
               end
               sItem = sInfo[:items_form] % sItems
               Logging.info(sInfo[:found] % [sCloudObj, sItem])
            end
            oList
         else
            ForjLib.debug(2, sInfo[:more] % [sCloudObj, name])
            # Looping to find the one corresponding
            element = nil
            oList.each { | oElem |
               bFound = true
               sQuery.each { | key, value |
                  if oElem[key] != value
                     bFound = false
                     break
                  end
               }
               :remove if not bFound
            }
            if oList.length == 0
               Logging.info(sInfo[:notfound] % [sCloudObj, name])
            else
               sItems = []
               if sInfo[:items].is_a?(Array)
                  sInfo[:items].each { | key |
                     sItems << oList[0, key]
                  }
               else
                  sItems << oList[0, sInfo[:items]]
               end
               sItem = sInfo[:items_form] % sItems
               Logging.info(sInfo[:found] % [sCloudObj, sItem])
            end
            oList
      end
   end
end


class BaseController
   # Default handlers which needs to be defined by the cloud provider,
   # called by BaseDefinition Create, Delete, Get, Query and Update functions.
   def connect(sObjectType, hParams)
      raise ForjError.new(), "connect has not been redefined by the provider '%s'" % self.class
   end

   def create(sObjectType, hParams)
      raise ForjError.new(), "create_object has not been redefined by the provider '%s'" % self.class
   end

   def delete(sObjectType, hParams)
      raise ForjError.new(), "delete_object has not been redefined by the provider '%s'" % self.class
   end

   def get(sObjectType, sUniqId, hParams)
      raise ForjError.new(), "get_object has not been redefined by the provider '%s'" % self.class
   end

   def query(sObjectType, sQuery, hParams)
      raise ForjError.new(), "query_object has not been redefined by the provider '%s'" % self.class
   end

   def update(sObjectType, hParams)
      raise ForjError.new(), "update_object has not been redefined by the provider '%s'" % self.class
   end

   def forjError(msg)
      raise ForjError.new(), "%s: %s" % [self.class, msg]
   end

   def required?(oParams, key)
      raise ForjError.new(), "%s: %s is not set." % [self.class, key] if not oParams.exist?(key)
   end
end

# represent an object or a list of object

# Collection of DataObject
# This class represents Object Parameters
class ObjectData
   def initialize(bInternal = false)

      @hParams = {}
      @hParams[:hdata] = {} unless bInternal
      @bInternal = bInternal
   end

   def [] (*key)

      key = key.flatten
      # Return ObjectData Element if asked. Ignore additional keys.
      return @hParams[key[0]] if key[1] == :ObjectData

      return @hParams if key.length == 0

      oObject = rhGet(@hParams, key[0])
      return nil if oObject.nil?

      # Return attributes if asked
      return oObject[:attrs,  key[2..-1]] if key[1] == :attrs

      if oObject.is_a?(ForjLib::Data)
         if @bInternal
            # params are retrieved in process context
            # By default, if key is detected as a framework object, return its data.
            return oObject[:attrs,  key[1..-1]]
         else
            # params are retrieved in controller context
            # By default, if key is detected as a controller object, return its data.
            return oObject[:object,  key[1..-1]]
         end
      end

      # otherwise, simply return what is found in keys hierarchy.
      rhGet(@hParams, key)
   end

   # Functions used to set simple data/Object for controller/process function call.
   # TODO: to revisit this function, as we may consider simple data, as ForjLib::Data object
   def []= (*key, value)
      return nil if [:object, :query].include?(key[0])
      rhSet(@hParams, value, key)
   end

   def add(oDataObject)
      # Requires to be a valid framework object.
      raise ForjError.new, "Invalid Framework object type '%s'." % oDataObject.class unless oDataObject.is_a?(ForjLib::Data)

      sObjectType = oDataObject.object_type?

      if oDataObject.type? == :list
         oOldDataObject = rhGet(@hParams, :query, sObjectType)
         oOldDataObject.unregister if oOldDataObject
         rhSet(@hParams, oDataObject, :query, sObjectType)
      else
         oOldDataObject = rhGet(@hParams, sObjectType)
         oOldDataObject.unregister if oOldDataObject
         @hParams[sObjectType] = oDataObject
      end
      oDataObject.register
   end

   def delete(oObj)
      if oObject.is_a?(Symbol)
         sObjectType = oObj
         @hParams[sObjectType] = nil
      else
         raise ForjError.new(), "ObjectData: delete error. oObj is not a symbol or a recognized formatted Object." unless oObj.key?(:object)
         if oObj[:object_type] == :object_list
            rhSet(@hParams, nil, :list, sObjectType)
         else
            sObjectType = oObj[:object_type]
            @hParams[sObjectType] = nil
         end
      end
      oObj.unregister
   end

   def << (hHash)
      @hParams.merge!(hHash)
   end

   def exist?(*key)
      raise ForjError.new, "ObjectData: key is not list of values (string/symbol or array)" if not [Array, String, Symbol].include?(key.class)

      key = [key] if key.is_a?(Symbol) or key.is_a?(String)

      key = key.flatten

      oObject = rhGet(@hParams, key[0])
      return false if oObject.nil?

      if oObject.is_a?(ForjLib::Data)
         # Return true if ObjectData Element is found when asked.
         return true if key[1] == :ObjectData and oObject.type?(key[0]) == :object

         # Return true if attritutes or controller object attributes found when asked.
         return oObject.exist?(key[2..-1]) if key[1] == :attrs
         return oObject.exist?(key[1..-1]) if key.length > 1
         true
      else
         # By default true if found key hierarchy
         (rhExist?(@hParams, key) == key.length)
      end
   end

   #~ def get(*key)
      #~ rhGet(@hParams, key)
   #~ end

   def type?(key)
      return nil if rhExist?(@hParams, key) != 1
      :data
      :DataObject if @hParams[key].type?() == :object
   end

   def cObj(*key)
      rhGet(@hParams, key, :object) if rhExist?(@hParams, key, :object) == 2
   end

end

# Following class defines class levels function to
# declare framework objects.
# As each process needs to define new object to deal with
# require that process to define it with definition functions
# See definition.rb for functions to use.

class BaseDefinition
   # Capitalized function are called to start a process. It is done by ForjObject.

   # BaseCloud Object available functions.
   def Create(sCloudObj)
      return nil if not sCloudObj
      raise ForjError.new(), "%s.Create: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :create_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, :create_e, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop

         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, :create_e, pProc).reverse

         raise ForjError.new(), "loop detection: '%s' is required but Create(%s) did not loaded it." % [sElem, sElem] if oObjMissing.include?(sElem)
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, :create_e, pProc,)
      ForjLib.debug(2, "Create Object '%s' - Running '%s'" % [sCloudObj, pProc])

      # Call the process function.
      # At some point, the process will call the controller, via the framework.
      # This controller call via the framework has the role to
      # create an ObjectData well formatted, with _return_map function
      # See Definition.connect/create/update/query/get functions (lowercase)
      oObject = @oForjProcess.method(pProc).call(sCloudObj, aParams)
      # return usually is the main object that the process called should provide.
      # Save Object if the object has been created by the process, without controller
      unless oObject.nil?
         @ObjectData.add(oObject)
      end
   end

   def Delete(sCloudObj)
      return nil if not sCloudObj

      raise ForjError.new(), "%s.Delete: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :delete_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, :delete_e, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, :delete_e, pProc).reverse
         raise ForjError.new(), "loop detection: '%s' is required but Delete(%s) did not loaded it." % [sElem, sElem] if oObjMissing.include?(sElem)
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, :delete_e, pProc)

      bState = @oForjProcess.method(pProc).call(sCloudObj, aParams)
      # return usually is the main object that the process called should provide.
      if bState
         @ObjectData.del(sCloudObj)
      end

   end

   # This function returns a list of objects
   def Query(sCloudObj, hQuery)

      return nil if not sCloudObj

      raise ForjError.new(), "$s.Get: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      # Check if we can re-use a previous query
      oList = @ObjectData[:query, sCloudObj]
      unless oList.nil?
         if oList[:query] == hQuery
            ForjLib.debug(3, "Using Object '%s' query cache : %s" % [sCloudObj, hQuery])
            return oList
         end
      end

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :query_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, :query_e, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, :query_e, pProc).reverse
         raise ForjError.new(), "loop detection: '%s' is required but Query(%s) did not loaded it." % [sElem, sElem] if oObjMissing.include?(sElem)
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the Process Event handler.
      aParams = _get_object_params(sCloudObj, :query_e, pProc)

      # Call the process function.
      # At some point, the process will call the controller, via the framework.
      # This controller call via the framework has the role to
      # create an ObjectData well formatted, with _return_map function
      # See Definition.connect/create/update/query/get functions (lowercase)
      oObject = @oForjProcess.method(pProc).call(sCloudObj, hQuery, aParams)
      # return usually is the main object that the process called should provide.
      unless oObject.nil?
         # Save Object if the object has been created by the process, without controller
         @ObjectData.add(oObject)
      end
   end

   def Get(sCloudObj, sUniqId)

      return nil if not sCloudObj

      raise ForjError.new(), "$s.Get: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :get_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, :get_e, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, :get_e, pProc).reverse
         raise ForjError.new(), "loop detection: '%s' is required but Get(%s) did not loaded it." % [sElem, sElem] if oObjMissing.include?(sElem)
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the Process Event handler.
      aParams = _get_object_params(sCloudObj, :get_e, pProc)

      # Call the process function.
      # At some point, the process will call the controller, via the framework.
      # This controller call via the framework has the role to
      # create an ObjectData well formatted, with _return_map function
      # See Definition.connect/create/update/query/get functions (lowercase)
      oObject = @oForjProcess.method(pProc).call(sCloudObj, sUniqId, aParams)
      # return usually is the main object that the process called should provide.
      unless oObject.nil?
         # Save Object if the object has been created by the process, without controller
         @ObjectData.add(oObject)
      end
   end

   def Update(sCloudObj)

      return nil if not sCloudObj

      raise ForjError.new(), "$s.Update: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :update_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, :update_e, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, :update_e, pProc).reverse
         raise ForjError.new(), "loop detection: '%s' is required but Update(%s) did not loaded it." % [sElem, sElem] if oObjMissing.include?(sElem)
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, :update_e, pProc)

      oObject = @oForjProcess.method(pProc).call(sCloudObj, aParams)
      # return usually is the main object that the process called should provide.
      unless oObject.nil?
         # Save Object if the object has been created by the process, without controller
         @ObjectData.add(oObject)
      end
   end

   def Setup(sObjectType, sAccountName)
      # Loop in dependencies to get list of data object to setup
      raise ForjError,new(), "Setup: '%s' not a valid object type." if rhExist?(@@meta_obj, sObjectType) != 1

      hAskStep = ForjDefault.get(:ask_step, :setup)
      aSetup = []
      hAskStep.each{ | value |
         aSetup << {
            :desc => value[:desc],
            :pre_step_handler => value[:pre_step_function],
            :order => [[]],
            :post_step_handler => value[:post_step_function]
         }

      }
      oInspectedObjects = []
      oInspectObj = [sObjectType]

      @oForjConfig.ac_load(sAccountName) if sAccountName

      ForjLib.debug(2, "Setup is identifying account data to ask for '%s'" % sObjectType)
      while oInspectObj.length() >0
         # Identify data to ask
         # A data to ask is a data needs from an object type
         # which is declared in section of defaults.yaml
         # and is declared :account to true (in defaults.yaml or in process declaration - define_data)

         sObjectType = oInspectObj.pop
         sAsk_step = 0
         ForjLib.debug(1, "Checking '%s'" % sObjectType)
         hTopParams = rhGet(@@meta_obj,sObjectType, :params)
         if hTopParams[:keys].nil?
            ForjLib.debug(1, "Warning! Object '%s' has no data/object needs. Check the process" % sObjectType)
            next
         end
         hTopParams[:keys].each { |sKeypath, hParams|
            oKeyPath = KeyPath.new(sKeypath)
            sKey = oKeyPath.sKey
            case hParams[:type]
               when :data
                  hMeta = _get_meta_data(sKey)
                  next if hMeta.nil?
                  sAsk_step = hMeta[:ask_step] if rhExist?(hMeta, :ask_step) == 1 and hMeta[:ask_step].is_a?(Fixnum)
                  ForjLib.debug(3, "#{sKey} is part of setup step #{sAsk_step}")
                  aOrder = aSetup[sAsk_step][:order]

                  if oInspectedObjects.include?(sKey)
                     ForjLib.debug(2, "#{sKey} is already asked. Ignored.")
                     next
                  end
                  if hMeta[:account].is_a?(TrueClass)
                     if not hMeta[:depends_on].is_a?(Array)
                        Logging.warning("'%s' depends_on definition have to be an array." % oKeyPath.sFullPath) unless hMeta[:depends_on].nil?
                        iLevel = 0
                        bFound = true
                     else
                        # Searching highest level from dependencies.
                        bFound = false
                        iLevel = 0
                        hMeta[:depends_on].each { |depend_key|
                           aOrder.each_index { |iCurLevel|
                              if aOrder[iCurLevel].include?(depend_key)
                                 bFound = true
                                 iLevel = [iLevel, iCurLevel + 1].max
                              end
                           }
                              aOrder[iLevel] = [] if aOrder[iLevel].nil?
                        }
                     end
                     if bFound
                        if not aOrder[iLevel].include?(sKey)
                           if hMeta[:ask_sort].is_a?(Fixnum)
                              iOrder = hMeta[:ask_sort]
                              if aOrder[iLevel][iOrder].nil?
                                 aOrder[iLevel][iOrder] = sKey
                              else
                                 aOrder[iLevel].insert(iOrder, sKey)
                              end
                              ForjLib.debug(3, "S%s/L%s/O%s: '%s' added in setup list. " % [sAsk_step, iLevel, iOrder, sKey])
                           else
                              aOrder[iLevel] << sKey
                              ForjLib.debug(3, "S%s/L%s/Last: '%s' added in setup list." % [sAsk_step, iLevel, sKey])
                           end
                        end
                     end
                     oInspectedObjects << sKey
                  else
                     ForjLib.debug(2, "#{sKey} used by #{sObjectType} won't be asked during setup. :account = true not set.")
                  end
               when :CloudObject
                  oInspectObj << sKey if not oInspectObj.include?(sKey) and not oInspectedObjects.include?(sKey)
            end
         }
         oInspectedObjects << sObjectType
      end
      ForjLib.debug(2, "Setup check if needs to add unrelated data in the process")
      hAskStep.each_index{ | iStep |
         value = hAskStep[iStep]
         if rhExist?(value, :add) == 1
            sKeysToAdd = rhGet(value, :add)
            sKeysToAdd.each { | sKeyToAdd |
               bFound = false
               aSetup[iStep][:order].each_index { | iOrder |
                  sKeysToAsk = aSetup[iStep][:order][iOrder]
                  unless sKeysToAsk.index(sKeyToAdd).nil?
                     bFound = true
                     break
                  end
               }
               next if bFound
               iLevel = 0
               iOrder = aSetup[iStep][:order].length
               iAtStep = iStep
               hMeta = _get_meta_data(sKeyToAdd)
               if rhExist?(hMeta, :after) == 1
                  sAfterKeys = hMeta[:after]
                  sAfterKeys = [ sAfterKeys ] if not sAfterKeys.is_a?(Array)
                  sAfterKeys.each{ |sAfterKey |
                     bFound = false
                     aSetup.each_index { |iStepToCheck|
                        aSetup[iStepToCheck][:order].each_index { | iLevelToCheck |
                           sKeysToAsk = aSetup[iStepToCheck][:order][iLevelToCheck]
                           iOrderToCheck = sKeysToAsk.index(sAfterKey)
                           unless iOrderToCheck.nil?
                              iAtStep = iStepToCheck if iStepToCheck > iAtStep
                              iLevel = iLevelToCheck if iLevelToCheck > iLevel
                              iOrder = iOrderToCheck + 1 if iOrderToCheck + 1 > iOrder
                              bFound = true
                              break
                           end
                        }
                     }
                  }
               end
               aSetup[iAtStep][:order][iLevel].insert(iOrder, sKeyToAdd)
               ForjLib.debug(3, "S%s/L%s/O%s: '%s' added in setup list at  position." % [iAtStep, iLevel, iOrder, sKeyToAdd])
            }
         end
      }

      ForjLib.debug(2, "Setup will ask for :\n %s" % aSetup.to_yaml)

      Logging.info("Configuring account : '#{config[:account_name]}', provider '#{config[:provider_name]}'")

      # Ask for user input
      aSetup.each_index { | iStep |
         ForjLib.debug(2, "Ask step %s:" % iStep)
         puts "%s%s%s" % [ANSI.bold, aSetup[iStep][:desc], ANSI.clear] unless aSetup[iStep][:desc].nil?
         aOrder = aSetup[iStep][:order]
         aOrder.each_index { | iIndex |
         ForjLib.debug(2, "Ask order %s:" % iIndex)
            aOrder[iIndex].each { | sKey |
               hParam = _get_meta_data(sKey)
               hParam = {} if hParam.nil?

               bOk = false

               if hParam[:pre_step_function]
                  pProc = hParam[:pre_step_function]
                  bOk = not(@oForjProcess.method(pProc).call(sKey))
               end


               sDesc = "'%s' value" % sKey
               puts "#{sKey}: %s" % [hParam[:explanation]] unless rhGet(hParam, :explanation).nil?
               sDesc = hParam[:desc] unless hParam[:desc].nil?
               sDefault = @oForjConfig.get(sKey, hParam[:default_value])
               rValidate = nil

               rValidate = hParam[:validate] unless hParam[:validate].nil?
               bRequired = (hParam[:required] == true)
               while not bOk
                  bOk = true
                  if not hParam[:list_values].nil?
                     hValues = hParam[:list_values]
                     sObjectToLoad = hValues[:object]

                     bListStrict = (hValues[:validate] == :list_strict)

                     case hValues[:query_type]
                        when :controller_call
                           oObject = @ObjectData[sObjectToLoad, :ObjectData]
                           Logging.state("Loading #{sObjectToLoad}.")
                           oObject = Create(sObjectToLoad) if oObject.nil?
                           return nil if oObject.nil?
                           oParams = ObjectData.new
                           oParams.add(oObject)
                           oParams << hValues[:query_params]
                           raise ForjError.new(), "#{sKey}: query_type => :controller_call requires missing :query_call declaration (Controller function)" if hValues[:query_call].nil?
                           pProc = hValues[:query_call]
                           begin
                              aList = @oProvider.method(pProc).call(sObjectToLoad, oParams)
                           rescue => e
                              raise ForjError.new(), "Error during call of '%s':\n%s" % [pProc, e.message]
                           end
                        when :query_call
                           sQuery = {}
                           sQuery = hValues[:query_params] unless hValues[:query_params].nil?
                           Logging.state("Querying #{sObjectToLoad}.")
                           oObjectList = Query(sObjectToLoad, sQuery)
                           aList = []
                           oObjectList.each { | oElem |
                              aList << oElem[hValues[:value]]
                           }
                           aList.sort!
                        when :process_call
                           raise ForjError.new(), "#{sKey}: query_type => :process_call requires missing :query_call declaration (Provider function)" if hValues[:query_call].nil?
                           pProc = hValues[:query_call]
                           sObjectToLoad = hValues[:object]
                           oParams = ObjectData.new
                           oParams.add(oObject)
                           oParams << hValues[:query_params]
                           begin
                              aList = @oForjProcess.method(pProc).call(sObjectToLoad, oParams)
                           rescue => e
                              raise ForjError.new(), "Error during call of '%s':\n%s" % [pProc, e.message]
                           end
                        else
                           raise ForjError.new, "'%s' invalid. %s/list_values/values_type supports %s. " % [hValues[:values_type], sKey, [:provider_function]]
                     end
                     Logging.fatal(1, "%s requires a value from the '%s' query which is empty." % [sKey, sObjectToLoad])if aList.nil? and bListStrict
                     aList = [] if aList.nil?
                     if not bListStrict
                        aList << "other"
                     end
                     say("Enter %s" % ((sDefault.nil?)? sDesc : sDesc + " |%s|" % sDefault))
                     value = choose { | q |
                        q.choices(*aList)
                        q.default = sDefault if sDefault
                     }
                     if not bListStrict and value == "other"
                        value = _ask(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
                     end
                  else
                     pValidateProc = hParam[:validate_function]
                     pAskProc = hParam[:ask_function]

                     if pAskProc.nil?
                        unless pValidateProc.nil?
                           value = _ask(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
                           while not @oForjProcess.method(pValidateProc).call(value)
                              value = _ask(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
                           end
                        else
                           value = _ask(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
                        end
                     else
                        unless pValidateProc.nil?
                           value = @oForjProcess.method(pAskProc).call(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
                           while not @oForjProcess.method(pValidateProc).call(value)
                              value = @oForjProcess.method(pAskProc).call(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
                           end
                        else
                           value = @oForjProcess.method(pAskProc).call(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
                        end
                     end
                  end

                  @oForjConfig.set(sKey, value)
                  if hParam[:post_step_function]
                     pProc = hParam[:post_step_function]
                     bOk = @oForjProcess.method(pProc).call()
                  end
               end
            }
         }
      }
   end

   # Initialize Cloud object Data

   def initialize(oForjConfig, oForjProcess, oForjProvider = nil)
      # Object Data object. Contains all loaded object data.
      # This object is used to build hParams as well.
      @ObjectData = ObjectData.new(true)
      #
      @RuntimeContext = {
         :oCurrentObj => nil
      }

      @oForjConfig = oForjConfig
      raise ForjError.new(), "'%s' is not a valid ForjAccount or ForjConfig Object." % [oForjConfig.class] if not oForjConfig.is_a?(ForjAccount) and not oForjConfig.is_a?(ForjConfig)

      @oProvider = oForjProvider
      if oForjProvider
         raise ForjError.new(), "'%s' is not a valid ForjProvider Object type." % [oForjProvider.class] if not oForjProvider.is_a?(BaseController)
      end

      @oForjProcess = oForjProcess
      raise ForjError.new(), "'%s' is not a valid BaseProcess Object type." % [oForjProcess.class] if not oForjProcess.is_a?(BaseProcess)

      @oForjProcess.set_BaseObject(self)
   end

   # ------------------------------------------------------
   # Functions used by processes functions
   # ------------------------------------------------------
   # Ex: object.set_data(...)
   #     config


   # Function to manipulate the config object.
   # 2 kind of functions:
   # - set (key, value) and []=(key, value)
   #   From processes, you can set a runtime data with:
   #     config.set(key, value)
   #   OR
   #     config[key] = value
   #
   # - get (key, default) and [](key, default)
   #   default is an optional value.
   #   From processes, you can get a data (runtime/account/config.yaml or defaults.yaml) with:
   #     config.get(key)
   #   OR
   #     config[key]

   def config
      raise ForjError.new(), "No config object loaded." if not @oForjConfig
      @oForjConfig
   end

   def format_query(sObjectType, oControlerObject, hQuery)
      {
         :object        => oControlerObject,
         :object_type   => :object_list,
         :list_type     => sObjectType,
         :list          => [],
         :query         => hQuery
      }
   end

   def format_object(sCloudObj, oMiscObject)
      return nil if not sCloudObj or not [String, Symbol].include?(sCloudObj.class)

      sCloudObj = sCloudObj.to_sym if sCloudObj.class == String

      oCoreObject = {
         :object_type => sCloudObj,
         :attrs => {},
         :object => oMiscObject,
      }
   end

   def get_data_metadata(sKey)
      _get_meta_data(sKey)
   end

   # Before doing a query, mapping fields
   # Transform Object query field to Provider query Fields
   def query_map(sCloudObj, hParams)
      return nil if not sCloudObj or not [String, Symbol].include?(sCloudObj.class)
      return {} if not hParams

      sCloudObj = sCloudObj.to_sym if sCloudObj.class == String

      hReturn = {}
      hMap = rhGet(@@meta_obj, sCloudObj, :query_mapping)
      hParams.each { |key, value|
         oKeyPath = KeyPath.new(key)
         sKeyPath = oKeyPath.sFullPath
         raise ForjError.new(), "Forj query field '%s.%s' not defined by class '%s'" % [sCloudObj, oKeyPath.sKey, self.class] if not hMap.key?(oKeyPath.sFullPath)
         oMapPath = KeyPath.new(hMap[oKeyPath.sFullPath])
         hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, sKeyPath)
         if hValueMapping
            raise ForjError.new(), "'%s.%s': No value mapping for '%s'" % [sCloudObj, oKeyPath.sKey, value] if rhExist?(hValueMapping, value) != 1

            rhSet(hReturn, hValueMapping[value], oMapPath.aTree)
         else
            rhSet(hReturn, value, oMapPath.aTree)
         end
      }
      hReturn
   end

   # Used by the Process.
   # Ask controller get_attr to get a data
   # The result is the data of a defined data attribute.
   # If the value is normally mapped (value mapped), the value is
   # returned as a recognized data attribute value.
   def get_attr(oObject, key)

      raise ForjError.new(), "'%s' is not a valid Object type. " % [oObject.class] if not oObject.is_a?(Hash) and rhExist?(oObject, :object_type) != 1
      sCloudObj = oObject[:object_type]
      oKeyPath = KeyPath.new(key)
      raise ForjError.new(), "'%s' key is not declared as data of '%s' CloudObject. You may need to add obj_needs..." % [oKeyPath.sKey, sCloudObj] if rhExist?(@@meta_obj, sCloudObj, :returns, oKeyPath.sFullPath) != 3
      begin
         oMapPath = KeyPath.new(rhGet(@@meta_obj, sCloudObj, :returns, oKeyPath.sFullPath))
         hMap = oMapPath.sFullPath
         value = @oProvider.get_attr(get_cObject(oObject), hMap)

         hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, oKeyPath.sFullPath)

         if hValueMapping
            hValueMapping.each { | found_key, found_value |
               if found_value == value
                  value = found_key
                  break
               end
            }
         end
      rescue => e
         raise ForjError.new(), "'%s.get_attr' fails to provide value of '%s'" % [oProvider.class, key]
      end
   end

   # Register the object to the internal @ObjectData instance
   def register(oObject, sObjectType = nil, sDataType = :object)
      if oObject.is_a?(ForjLib::Data)
         oDataObject = oObject
      else
         raise ForjError.new(), "Unable to register an object '%s' as ForjLib::Data object if ObjectType is not given." % [ oObject.class ] if not sObjectType
         oDataObject = ForjLib::Data.new(sDataType)
         oDataObject.set(oObject, sObjectType) { | sObjType, oControlerObject |
            _return_map(sObjType, oControlerObject)
         }
      end
      @ObjectData.add oDataObject
   end

   # get an attribute/object/... from an object.
   def get_data(oObj, *key)
      if oObj.is_a?(Hash) and oObj.key?(:object_type)
         oObjData = ObjectData.new
         oObjData << oObj
      else
         oObjData = @ObjectData
      end
      oObjData[oObj, *key]
   end

   #~ def hParams(sCloudObj, hParams)
      #~ aParams = _get_object_params(sCloudObj, ":ObjectData.hParams")
   #~ end

   def get_cObject(oObject)
      return nil if rhExist?(oObject, :object) != 1
      rhGet(oObject, :object)
   end

   # a Process can execute any kind of predefined controler task.
   # Those function build hParams with Provider compliant data (mapped)
   # Results are formatted as usual framework Data object and stored.
   def connect(sObjectType)

      hParams = _get_object_params(sObjectType, :create_e, :connect, true)
      oControlerObject = @oProvider.connect(sObjectType, hParams)
      oDataObject = ForjLib::Data.new
      oDataObject.set(oControlerObject, sObjectType) { | sObjType, oObject |
         begin
            _return_map(sObjType, oObject)
         rescue => e
            raise ForjError.new(), "connect %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
         end
      }
      @ObjectData.add oDataObject
      oDataObject
   end

   def create(sObjectType)
      # The process ask the controller to create the object.
      # hParams have to be fully readable by the controller.
      hParams = _get_object_params(sObjectType, :create_e, :create, true)
      oControlerObject = @oProvider.create(sObjectType, hParams)
      oDataObject = ForjLib::Data.new
      oDataObject.set(oControlerObject, sObjectType) { | sObjType, oObject |
         begin
            _return_map(sObjType, oObject)
         rescue => e
            raise ForjError.new(), "create %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
         end
      }
      @ObjectData.add oDataObject

      oDataObject
   end

   # The controller must return true to inform about the real deletion
   def delete(sObjectType)
      hParams = _get_object_params(sObjectType, :delete_e, :delete, true)
      bState = @oProvider.delete(sObjectType, hParams)
      @ObjectData.delete(sCloudObj) if bState
      bState
   end

   def get(sObjectType, sUniqId)

      hParams = _get_object_params(sObjectType, :get_e, :get, true)

      oControlerObject = @oProvider.get(sObjectType, sUniqId, hParams)
      oDataObject = ForjLib::Data.new
      oDataObject.set(oControlerObject, sObjectType) { | sObjType, oObject |
         begin
            _return_map(sObjType, oObject)
         rescue => e
            raise ForjError.new(), "get %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
         end
      }
      @ObjectData.add oDataObject

      oDataObject
   end

   def query(sObjectType, hQuery)

      # Check if we can re-use a previous query
      oList = @ObjectData[:query, sObjectType]
      unless oList.nil?
         if oList[:query] == hQuery
            ForjLib.debug(3, "Using Object '%s' query cache : %s" % [sObjectType, hQuery])
            return oList
         end
      end


      hParams = _get_object_params(sObjectType, :query_e, :query, true)
      sProviderQuery = query_map(sObjectType, hQuery)

      oControlerObject = @oProvider.query(sObjectType, sProviderQuery, hParams)

      oDataObjects = ForjLib::Data.new :list
      oDataObjects.set(oControlerObject, sObjectType, hQuery) { | sObjType, key |
         begin
            _return_map(sObjType, key)
         rescue => e
            raise ForjError.new(), "query %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
         end
      }

      ForjLib.debug(2, "Object %s - queried. Found %s object(s)." % [sObjectType, oDataObjects.length()])

      @ObjectData.add oDataObjects
      oDataObjects
   end

   def update(sObjectType)
      # Need to detect data updated and update the Controler object with the controler

      hParams = _get_object_params(sObjectType, :update_e, :update, true)

      oObject = hParams.get(sObjectType)
      oControlerObject = hParams[sObjectType]

      bUpdated = false
      oObject[attrs].each { |key, value |
         #      hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, key)
         oKeyPath = KeyPath.new(key)
         oMapPath = KeyPath.new(rhGet(@@meta_obj, sCloudObj, :returns, oKeyPath.sFullPath))
         old_value = @oProvider.get_attr(oControlerObject, oMapPath.aTree)
         if value != old_value
            bUpdated = true
            @oProvider.set_attr(oControlerObject, hMap, value)
            ForjLib.debug(2, "%s.%s - Updating: %s = %s (old : %s)" % [@oForjProcess.class, sObjectType, key, value, old_value])
         end
      }
      oControlerObject = @oProvider.update(sObjectType, hParams) if bUpdated
      ForjLib.debug(1, "%s.%s - Saved." % [@oForjProcess.class, sObjectType])
      oDataObject = ForjLib::Data.new
      oDataObject.set(oControlerObject, sObjectType) { | sObjType, oObject |
         begin
            _return_map(sObjType, oObject)
         rescue => e
            raise ForjError.new(), "update %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
         end
      }
      @ObjectData.add oDataObject

      oDataObject
   end


   private

   # -------------------------------------------------------------------------
   # Functions available for Process to communicate with the controler Object
   # -------------------------------------------------------------------------
   def cloud_obj_requires(sCloudObj, res = {})
      aCaller = caller
      aCaller.pop

      return res if @ObjectData.exist?(sCloudObj)
      #~ return res if rhExist?(@CloudData, sCloudObj) == 1

      rhGet(@@meta_obj,sCloudObj, :params).each { |key, hParams|
         case hParams[:type]
            when :data
               if  hParams.key?(:array)
                  hParams[:array].each{ | aElem |
                     aElem = aElem.clone
                     aElem.pop # Do not go until last level, as used to loop next.
                     rhGet(hParams, aElem).each { | subkey, hSubParam |
                        next if aElem.length == 0 and [:array, :type].include?(subkey)
                        if hSubParams[:required] and @oForjConfig.get(subkey).nil?
                           res[subkey] = hSubParams
                        end
                     }
                  }
               else
                  if hParams[:required] and @oForjConfig.get(key).nil?
                     res[key] = hParams
                  end
               end
            when :CloudObject
               #~ if hParams[:required] and rhExist?(@CloudData, sCloudObj) != 1
               if hParams[:required] and not @ObjectData.exist?(sCloudObj)
                  res[key] = hParams
                  cloud_obj_requires(key, res)
               end
         end
      }
      res
   end

   def get_object(sCloudObj)
      #~ return nil if rhExist?(@CloudData, sCloudObj) != 1
      return nil if not @ObjectData.exist?(sCloudObj)
      @ObjectData[sCloudObj, :ObjectData]
      #~ rhGet(@CloudData, sCloudObj)
   end

   def objectExist?(sCloudObj)
      @ObjectData.exist?(sCloudObj)
      #~ (rhExist?(@CloudData, sCloudObj) != 1)
   end

   def get_forjKey(oCloudData, key)
      return nil if not @ObjectData.exist?(sCloudObj)
      @ObjectData[sCloudObj, :attrs, key]
      #~ return nil if rhExist?(oCloudData, sCloudObj) != 1
      #~ rhGet(oCloudData, sCloudObj, :attrs, key)
   end
end
