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
         Logging.debug("Loading Process '%s'" % sProcessClass)

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
            cBaseProcess = Object.const_set(sProcessClass, cNewClass)
            cProcessClass = sProcessClass
            load sFile
         else
            Logging.warning("Process file definition '%s' is missing. " % sFile)
         end
      }

      if sControllerClass
         Logging.debug("Loading Controler/definition '%s'" % sControllerClass)
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

      oForjAccount = ForjAccount.new(oConfig)
      unless sAccount.nil?
         oForjAccount.ac_load(sAccount, false)
         #~ sControllerMod = oForjAccount.getAccountData(:account, :provider)
      #~ else
         #~ sControllerMod = oConfig.get(:provider_name)
      end
      aProcessList = [:CloudProcess]

      sControllerMod = oForjAccount.get(:provider_name)
      raise ForjError.new(), "Provider_name not set. Unable to create instance ForjCloud." if sControllerMod.nil?

      sControllerProcessMod = File.join($PROVIDERS_PATH, sControllerMod, sControllerMod.capitalize + "Process.rb")
      if File.exist?(sControllerProcessMod)
         aProcessList << sControllerProcessMod
      else
         Logging.debug("No Provider process defined. File '%s' not found." % sControllerProcessMod)
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

   def get_data(oObj, *key)

      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.get_data(oObj, :attrs, key)
   end

   def register(oObj)

      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.register(oObj)
   end

   def config
      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.config
   end

   def query_single(sCloudObj, sQuery, name)
      oList = controler.query(sCloudObj, sQuery)
      case oList[:list].length()
         when 0
            Logging.debug("No %s '%s' found" % [sCloudObj, name] )
            nil
         when 1
            Logging.debug("Found %s '%s'." % [sCloudObj, name])
            oList[:list][0]
         else
            Logging.debug("Found several %s. Searching for '%s'." % [sCloudObj, name])
            # Looping to find the one corresponding
            element = nil
            oList[:list].each { | oElem |
               bFound = true
               sQuery.each { | key, value |
                  if oElem[:attrs][key] != value
                     bFound = false
                     break
                  end
               }
               if bFound
                  element = oElem
                  break
               end
            }
            if element.nil?
               Logging.debug("No %s '%s' found" % [sCloudObj, name])
               return nil
            end
            Logging.debug("Found %s '%s'." % [sCloudObj, name])
            element
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

# This class represents Object Parameters
class ObjectData
   def initialize(bInternal = false)

      @hParams = {}
      @hParams[:hdata] = {} unless bInternal
   end

   def [] (*key)

      key = key.flatten
      # Return ObjectData Element if asked.
      return @hParams[key[0]] if key[1] == :ObjectData

      # Return attritutes if asked
      return rhGet(@hParams, key[0], :attrs,  key[2..-1]) if key[1] == :attrs

      # Return Controller object data if asked
      return rhGet(@hParams, key[0], :object, key[2..-1]) if key[1] == :object

      # By default, if key is detected as a controller object, return its data.
      return rhGet(@hParams, key[0], :object,  key[1..-1]) if rhExist?(@hParams, key[0], :object) == 2

      # otherwise, simply return what is found in keys hierarchy.
      rhGet(@hParams, key)
   end

   def []= (*key, value)
      return nil if key[1] == :object
      rhSet(@hParams, value, key)
   end

   def add(oObject)
      # Requires to be a valid framework object.
      raise ForjError.new, "Invalid Framework object type" if rhExist?(oObject, :object_type) != 1

      sObjectType = oObject[:object_type]

      @hParams[sObjectType] = oObject
   end

   def delete(sObjectType)
      @hParams[sObjectType] = nil
   end

   def << (hHash)
      @hParams.merge!(hHash)
   end

   def exist?(*key)
      raise ForjError.new, "ObjectData: key is not list of values (string/symbol or array)" if not [Array, String, Symbol].include?(key.class)

      key = [key] if key.is_a?(Symbol) or key.is_a?(String)

      key = key.flatten

      # Return true if ObjectData Element is found when asked.
      return true if key[1] == :ObjectData and rhExist?(@hParams, key[0], :object) == 2

      # Return true if attritutes or controller object attributes found when asked.
      return (rhExist?(@hParams, key) == key.length) if [:object, :attrs].include?(key[1])

      # By default, if key is detected as a controller object, return true if attribute is found.
      return (rhExist?(@hParams, key[0], :object,  key[1..-1]) == key.length+1) if rhExist?(@hParams, key[0], :object) == 2

      # By default true if found key hierarchy
      (rhExist?(@hParams, key) == key.length)
   end

   def get(*key)
      rhGet(@hParams, key)
   end

   def type?(*key)
      nil if rhExist?(@hParams, key) != 1
      :data
      :DataObject if rhExist?(@hParams, key, :object) == 2
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
      Logging.debug("Create Object '%s' - Running '%s'" % [sCloudObj, pProc])

      # Call the process function.
      # At some point, the process will call the controller, via the framework.
      # This controller call via the framework has the role to
      # create an ObjectData well formatted, with _return_map function
      # See Definition.connect/create/update/query/get functions (lowercase)
      oObject = @oForjProcess.method(pProc).call(sCloudObj, aParams)

      @ObjectData.add oObject
      oObject
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
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, :delete_e, pProc)

      bState = @oForjProcess.method(pProc).call(sCloudObj, aParams)

      @ObjectData.delete(sCloudObj) if bState
      #~ rhSet(@CloudData, nil, sCloudObj) if bState
   end

   # This function returns a list of objects
   def Query(sCloudObj, sQuery)

      return nil if not sCloudObj

      raise ForjError.new(), "$s.Get: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :query_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, :query_e, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, :query_e, pProc).reverse
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, :query_e, pProc)

      # Call the process function.
      # At some point, the process will call the controller, via the framework.
      # This controller call via the framework has the role to
      # create an ObjectData well formatted, with _return_map function
      # See Definition.connect/create/update/query/get functions (lowercase)
      @oForjProcess.method(pProc).call(sCloudObj, sQuery, aParams)

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
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, :get_e, pProc)

      # Call the process function.
      # At some point, the process will call the controller, via the framework.
      # This controller call via the framework has the role to
      # create an ObjectData well formatted, with _return_map function
      # See Definition.connect/create/update/query/get functions (lowercase)
      oObjValue = @oForjProcess.method(pProc).call(sCloudObj, sUniqId, aParams)

      @ObjectData.add(oObjValue)
      #~ rhSet(@CloudData, oObjValue, sCloudObj)
      oObjValue
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
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, :update_e, pProc)

      @oForjProcess.method(pProc).call(sCloudObj, aParams)
   end

   def Setup(sObjectType, sAccountName)
      # Loop in dependencies to get list of data object to setup
      raise ForjError,new(), "Setup: '%s' not a valid object type." if rhExist?(@@meta_obj, sObjectType) != 1

      aSetup = [[]]
      oInspectedObjects = []
      oInspectObj = [sObjectType]

      @oForjConfig.ac_load(sAccountName) if sAccountName

      Logging.debug("Setup is identifying account data to ask for '%s'" % sObjectType)
      while oInspectObj.length() >0
         # Identify data to ask
         sObjectType = oInspectObj.pop
         Logging.debug("Checking '%s'" % sObjectType)
         hTopParams = rhGet(@@meta_obj,sObjectType, :params)
         if hTopParams[:list].nil?
            Logging.debug("Warning! Object '%s' has no data/object needs. Check the process" % sObjectType)
            next
         end
         hTopParams[:keys].each { |sKeypath, hParams|
            oKeyPath = KeyPath.new(sKeypath)
            sKey = oKeyPath.sKey
            case hParams[:type]
               when :data
                  hMeta = _get_meta_data(sKey)
                  next if hMeta.nil?

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
                           aSetup.each_index { |iCurLevel|
                              if aSetup[iCurLevel].include?(depend_key)
                                 bFound = true
                                 iLevel = [iLevel, iCurLevel + 1].max
                              end
                           }
                              aSetup[iLevel] = [] if aSetup[iLevel].nil?
                        }
                     end
                     if bFound
                        if not aSetup[iLevel].include?(sKey)
                           if hMeta[:ask_sort].is_a?(Fixnum)
                              if aSetup[iLevel][hMeta[:ask_sort]].nil?
                                 aSetup[iLevel][hMeta[:ask_sort]] = sKey
                              else
                                 aSetup[iLevel].insert(hMeta[:ask_sort], sKey)
                              end
                           else
                              aSetup[iLevel] << sKey
                           end
                           Logging.debug("'%s' added in setup list. level %s." % [sKey, iLevel])
                        end
                     else
                        oInspectedObjects << sKey
                     end
                  end
               when :CloudObject
                  oInspectObj << sKey if not oInspectObj.include?(sKey) and not oInspectedObjects.include?(sKey)
            end
         }
         oInspectedObjects << sObjectType
      end
      Logging.debug("Setup will ask for :\n %s" % aSetup.to_yaml)

      # Ask for user input
      aSetup.each_index { | iIndex |
         Logging.debug("Ask step %s:" % iIndex)
         aSetup[iIndex].each { | sKey |
            hParam = _get_meta_data(sKey)
            hParam = {} if hParam.nil?
            sDesc = "'%s' value" % sKey
            sDesc = hParam[:desc] unless hParam[:desc].nil?
            sDefault = @oForjConfig.get(sKey, hParam[:default_value])
            rValidate = nil

            rValidate = hParam[:validate] unless hParam[:validate].nil?
            bRequired = (hParam[:required] == true)
            if not hParam[:list_values].nil?
               hValues = hParam[:list_values]
               sObjectToLoad = hValues[:object]
               oObject = get_object(sObjectToLoad)
               oObject = Create(sObjectToLoad) if oObject.nil?
               return nil if oObject.nil?
               oParams = ObjectData.new
               oParams.add(oObject)
               oParams<< hValues[:query_params]
               bListStrict = (hValues[:validate] == :list_strict)

               case hValues[:query_type]
                  when :controller_call
                     raise ForjError.new(), "values_type => :provider_function requires missing :query_call declaration (Controller function)" if hValues[:query_call].nil?
                     pProc = hValues[:query_call]
                     begin
                        aList = @oProvider.method(pProc).call(sObjectToLoad, oParams)
                     rescue => e
                        raise ForjError.new(), "Error during call of '%s':\n%s" % [pProc, e.message]
                     end
                  when :process_call
                     raise ForjError.new(), "values_type => :process_function requires missing :query_call declaration (Provider function)" if hValues[:query_call].nil?
                     pProc = hValues[:query_call]
                     sObjectToLoad = hValues[:object]
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
               value = _ask(sDesc, sDefault, rValidate, hParam[:encrypted], bRequired)
            end

            @oForjConfig.set(sKey, value)
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
   def register(oObject)
      raise ForjError.new(), "register fails. The object type is not a DataObject." if rhExist?(oObject, :object_type) != 1
      @ObjectData.add oObject
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
   # Those function assumes hParams are already prepared.
   # Results are formatted as usual framework Data object.
   def connect(sObjectType)

      hParams = _get_object_params(sObjectType, :create_e, :connect, true)
      oControlerObject = @oProvider.connect(sObjectType, hParams)
      begin
         _return_map(sObjectType, oControlerObject)
      rescue => e
         raise ForjError.new(), "connect %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
      end
   end

   def create(sObjectType)
      # The process ask the controller to create the object.
      # hParams have to be fully readable by the controller.
      hParams = _get_object_params(sObjectType, :create_e, :create, true)
      oControlerObject = @oProvider.create(sObjectType, hParams)
      begin
         _return_map(sObjectType, oControlerObject)
      rescue => e
         raise ForjError.new(), "create %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
      end
      Logging.debug("%s.%s - loaded." % [@oForjProcess.class, sObjectType])
   end

   def delete(sObjectType)
      hParams = _get_object_params(sObjectType, :delete_e, :delete, true)
      @oProvider.delete(sObjectType, hParams)
   end

   def get(sObjectType, sUniqId)

      hParams = _get_object_params(sObjectType, :get_e, :get, true)

      oControlerObject = @oProvider.get(sObjectType, hParams)
      begin
         _return_map(sObjectType, oControlerObject)
      rescue => e
         raise ForjError.new(), "get %s.%s : %s" % [@oForjProcess.class, e.message]
      end
   end

   def query(sObjectType, sQuery)

      hParams = _get_object_params(sObjectType, :query_e, :query, true)
      sProviderQuery = query_map(sObjectType, sQuery)

      oControlerObject = @oProvider.query(sObjectType, sProviderQuery, hParams)

      oObjects = {
         :object      => oControlerObject,
         :object_type => :object_list,
         :list       => []
      }
      oObjects[:object].each { | key |
         begin
            oObjects[:list] << _return_map(sObjectType, key)
         rescue => e
            raise ForjError.new(), "For each object '%s' attributes : %s" % [sObjectType, e.message]
         end
      }
      Logging.debug("Object %s - queried. Found %s object(s)." % [sObjectType, oObjects[:list].length()])
      oObjects

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
            Logging.debug("%s.%s - Updating: %s = %s (old : %s)" % [@oForjProcess.class, sObjectType, key, value, old_value])
         end
      }
      oControlerObject = @oProvider.update(sObjectType, hParams) if bUpdated
      Logging.debug("%s.%s - Saved." % [@oForjProcess.class, sObjectType])
      begin
         _return_map(sObjectType, oControlerObject)
      rescue => e
         raise ForjError.new(), "update %s.%s : %s" % [@oForjProcess.class, sObjectType, e.message]
      end
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
      @ObjectData[sCloudObj]
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
