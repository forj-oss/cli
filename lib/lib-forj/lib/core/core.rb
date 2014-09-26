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
   #               2 functions:
   #               - set (key, value)
   #               - get (key)

   # sProcessClass: Required. string or symbol. Is the name of ProcessClass to use.
   #                This class is dynamically loaded and derived from BaseProcess class.
   #                It loads the Process class content from a file '$CORE_PROCESS_PATH/<sProcessClass>.rb'

   # <sProcessClass>.rb file name is case sensible and respect RUBY Class name convention

   # sControllerClass: Optional. string or symbol. Is the name of ControlerClass to use.
   #                  This class is dynamically loaded and derived from BaseControler class.
   #                  It loads the Controler class content from a file '$PROVIDER_PATH/<sControlerClass>.rb'
   #
   #                  The provider can redefine partially or totally some processes
   #                  ForjObject will load those redefinition from file:
   #                  '$PROVIDER_PATH/<sControlerClass>Process.rb'

   # <sControllerClass>.rb or <sControllerClass>Process.rb file name is case sensible and respect RUBY Class name convention

   def initialize(oForjConfig, sProcessClass = nil, sControllerClass = nil)
      # Loading ProcessClass
      # Create Process derived from respectively BaseProcess
      Logging.debug("Loading Process '%s'" % sProcessClass)
      cBaseProcess = Class.new(BaseProcess)
      Object.const_set sProcessClass, cBaseProcess
      # And load the content from the <sProcessClass>.rb
      if sProcessClass.is_a?(Symbol)
         sFile = File.join($CORE_PROCESS_PATH, sProcessClass.to_s + '.rb')
      else
         sFile = File.join($CORE_PROCESS_PATH, sProcessClass.capitalize + '.rb')
      end
      if File.exists?(sFile)
         load sFile
      else
         raise ForjError.new(), "Process file definition '%s' is missing. Cannot go on" % sFile
      end

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
         $PROVIDER_PATH = File.join($PROVIDERS_PATH, sControllerClass)
         sFile = File.join($PROVIDER_PATH, sProviderClass + '.rb')
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
         # - Controler Class (sProviderClass + 'Controler') - Provider Cloud controler object

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


         # Load the Provider process Class if exists.
         sProcessFile = File.join($PROVIDER_PATH, sControllerClass + 'Process.rb')
         if File.exist?(sProcessFile)
            # Create an object derived from sProcessClass (Ex: CloudProcess) named sProviderClass + 'Process'
            cBaseProcess = Class.new(sProcessClass)
            Object.const_set sProviderClass + 'Process', cBaseProcess
            load File.join($PROVIDER_PATH, sProcessFile)
            byebug
         end
      else
         oCoreObjectControllerClass = nil
      end

      # Add Process management object ---------------
      begin
         oBaseProcessDefClass = Object.const_get(sProcessClass)
      rescue
         raise ForjError.new(), 'ForjCloud: Unable to find class "%s"' % sProcessClass
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

   def Update(oCloudObj)
      return nil if not oCloudObj or not @oCoreObject

      @oCoreObject.Update(oCloudObj)
   end

end

# This class based on generic ForjObject, defines a Cloud Process to use.
class ForjCloud < ForjObject
   def initialize(oConfig, sAccount)

      oForjAccount = ForjAccount.new(oConfig)
      oForjAccount.ac_load(sAccount)

      sProviderFileToLoad = oForjAccount.getAccountData(:account, :provider)

      super(oForjAccount, :CloudProcess, sProviderFileToLoad)
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

   def config
      raise ForjError.new(), "No Base object loaded." if not @oDefinition
      @oDefinition.get_config
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
class ObjectParams
   def initialize()
      @hParams = {
         :hdata => {},
      }
   end

   def [] (key)

      return rhGet(@hParams, key, :object) if rhExist?(@hParams, key, :object) == 2
      rhGet(@hParams, key)
   end

   def []= (key, value)
      @hParams[key] = value
   end

   def exist?(key)
      (rhExist?(@hParams, key) == 1)
   end

   def get(key)
      rhGet(@hParams, key)
   end

   def type?(key)
      nil if rhExist?(@hParams, key) != 1
      :data
      :CloudObject if rhExist?(@hParams, key, :object) == 2
   end

   def cObj(key)
      rhGet(@hParams, key, :object) if rhExist?(@hParams, key, :object) == 2
   end

end

class BaseDefinition
   # BaseCloud Object available functions.
   def Create(sCloudObj)
      return nil if not sCloudObj
      raise ForjError.new(), "%s.Create: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :create_e)
      hReturn = rhGet(@@meta_obj, sCloudObj, :returns)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, pProc).reverse
         raise ForjError.new(), "loop detection: '%s' is required but Create(%s) did not loaded it." % [sElem, sElem] if oObjMissing.include?(sElem)
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, pProc)

      oBaseObject = @oForjProcess.method(pProc).call(sCloudObj, aParams)

      rhSet(@CloudData, oBaseObject, sCloudObj)
   end

   def Delete(sCloudObj)
      return nil if not sCloudObj

      raise ForjError.new(), "%s.Delete: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :delete_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, pProc).reverse
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, pProc)

      bState = @oForjProcess.method(pProc).call(sCloudObj, aParams)

      rhSet(@CloudData, nil, sCloudObj) if bState
   end

   # This function returns a list of objects
   def Query(sCloudObj, sQuery)

      return nil if not sCloudObj

      raise ForjError.new(), "$s.Get: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :query_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, pProc).reverse
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, pProc)

      @oForjProcess.method(pProc).call(sCloudObj, sQuery, aParams)

   end

   def Get(sCloudObj, sUniqId)

      return nil if not sCloudObj

      raise ForjError.new(), "$s.Get: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :get_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, pProc).reverse
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, pProc)

      oObjValue = @oForjProcess.method(pProc).call(sCloudObj, sUniqId, aParams)

      rhSet(@CloudData, oObjValue, sCloudObj)
   end

   def Update(sCloudObj)

      return nil if not sCloudObj

      raise ForjError.new(), "$s.Update: '%s' is not a known object type." % [self.class, sCloudObj] if rhExist?(@@meta_obj, sCloudObj) != 1

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :update_e)

      return nil if pProc.nil?

      # Check required parameters
      oObjMissing = _check_required(sCloudObj, pProc).reverse

      while oObjMissing.length >0
         sElem = oObjMissing.pop
         raise ForjError.new(),"Unable to create Object '%s'" % sElem if not Create(sElem)
         oObjMissing = _check_required(sCloudObj, pProc).reverse
      end
      @RuntimeContext[:oCurrentObj] = sCloudObj # Context: Default object used.

      # build Function params to pass to the event handler.
      aParams = _get_object_params(sCloudObj, pProc)

      @oForjProcess.method(pProc).call(sCloudObj, aParams)
   end

   # Initialize Cloud object Data
   def initialize(oForjConfig, oForjProcess, oForjProvider = nil)
      # Real Object Data
      @CloudData = {}
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
   # Ex: object.query_map(...), object.set_data(...), object.hParams(...)
   #     object.get_config

   def get_config
      raise ForjError.new(), "No config object loaded." if not @oForjConfig
      @oForjConfig
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
         raise ForjError.new(), "Forj query field '%s.%s' not defined by class '%s'" % [sCloudObj, key, self.class] if not hMap.key?(key)
         hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, key)
         if hValueMapping
            raise ForjError.new(), "'%s.%s': No value mapping for '%s'" % [sCloudObj, key, value] if rhExist?(hValueMapping, value) != 1
            hReturn[hMap[key]] = hValueMapping[value]
         else
            hReturn[hMap[key]] = value
         end
      }
      hReturn
   end

   # Get BaseObject Data value
   def get_attr(oObject, key)

      raise ForjError.new(), "'%s' is not a valid Object type. " % [oObject.class] if not oObject.is_a?(Hash) and rhExist?(oObject, :object_type) != 1
      sCloudObj = oObject[:object_type]
      raise ForjError.new(), "'%s' key is not declared as data of '%s' CloudObject. You may need to add obj_needs..." % [key, sCloudObj] if rhExist?(@@meta_obj, sCloudObj, :returns, key) != 3
      begin
         hMap = rhGet(@@meta_obj, sCloudObj, :returns, key)
         @oProvider.get_attr(get_cObject(oObject), hMap)
      rescue => e
         raise ForjError.new(), "'%s.get_attr' fails to provide value of '%s'" % [oProvider.class, key]
      end
   end

   # Set Object Data
   def set_data(oObject, sCloudObj = nil)
      raise ForjError.new(), "set_data fails. The object type is not a DataObject." if rhExist?(oObject, :object_type) != 1
      sCloudObj = oObject[:object_type]
      @CloudData[sCloudObj] = oObject
   end

   def hParams(sCloudObj, hParams)
      aParams = _get_object_params(sCloudObj, pProc)
   end

   def get_cObject(oObject)
      return nil if rhExist?(oObject, :object) != 1
      rhGet(oObject, :object)
   end

   # a Process can execute any kind of predefined controler task.
   # Those function will transform params or results to a valid
   # Object type.
   def connect(sObjectType, hParams)
      oControlerObject = @oProvider.connect(sObjectType, hParams)
      begin
         _return_map(sObjectType, oControlerObject)
      rescue => e
         raise ForjError.new(), "%s.%s : %s" % [@oForjProcess.class, pProc, e.message]
      end
   end

   def create(sObjectType, hParams)
      oControlerObject = @oProvider.create(sObjectType, hParams)
      begin
         _return_map(sObjectType, oControlerObject)
      rescue => e
         raise ForjError.new(), "%s.%s : %s" % [@oForjProcess.class, pProc, e.message]
      end
      Logging.debug("%s.%s - loaded." % [@oForjProcess.class, sObjectType])
   end

   def delete(sObjectType, hParams)
      @oProvider.delete(sObjectType, hParams)
   end

   def get(sObjectType, sUniqId, hParams)
      oControlerObject = @oProvider.get(sObjectType, hParams)
      begin
         _return_map(sObjectType, oControlerObject)
      rescue => e
         raise ForjError.new(), "%s.%s : %s" % [@oForjProcess.class, pProc, e.message]
      end
   end

   def query(sObjectType, sQuery, hParams)
      oControlerObject = @oProvider.query(sObjectType, sQuery, hParams)

      oObjects = {
         :object      => oControlerObject,
         :object_type => :object_list,
         :list       => []
      }
      oObjects[:object].each { | key |
         begin
            oObjects[:list] << _return_map(sObjectType, key)
         rescue => e
            raise ForjError.new(), "%s.%s : %s" % [@oForjProcess.class, pProc, e.message]
         end
      }
      Logging.debug("%s.%s - queried. Found %s object(s)." % [@oForjProcess.class, sObjectType, oObjects[:list].length()])
      oObjects

   end

   def update(sObjectType, hParams)
      # Need to detect data updated and update the Controler object with the controler

      oObject = hParams.get(sObjectType)
      oControlerObject = hParams[sObjectType]

      bUpdated = false
      oObject[attrs].each { |key, value |
         #      hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, key)
         hMap = rhGet(@@meta_obj, sCloudObj, :returns, key)
         old_value = @oProvider.get_attr(oControlerObject, hMap)
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
         raise ForjError.new(), "%s.%s : %s" % [@oForjProcess.class, pProc, e.message]
      end
   end


   private

   # -------------------------------------------------------------------------
   # Functions available for Process to communicate with the controler Object
   # -------------------------------------------------------------------------
   def cloud_obj_requires(sCloudObj, res = {})
      aCaller = caller
      aCaller.pop

      return res if rhExist?(@CloudData, sCloudObj) == 1

      rhGet(@@meta_obj,sCloudObj, :params).each { |key, hParams|
         case hParams[:type]
            when :data
               if hParams[:required] and @oForjConfig.get(key).nil?
                  res[key] = hParams
               end
            when :CloudObject
               if hParams[:required] and rhExist?(@CloudData, sCloudObj) != 1
                  res[key] = hParams
                  cloud_obj_requires(key, res)
               end
         end
      }
      res
   end

   def get_object(sCloudObj)
      return nil if rhExist?(@CloudData, sCloudObj) != 1
      rhGet(@CloudData, sCloudObj)
   end

   def get_forjKey(oCloudData, key)
      return nil if rhExist?(oCloudData, sCloudObj) != 1
      rhGet(oCloudData, sCloudObj, :attrs, key)
   end

   # ------------------------------------------------------
   # Class Definition internal function.
   # ------------------------------------------------------

   def _return_map(sCloudObj, oControlerObject)

      return nil if not sCloudObj or not [String, Symbol].include?(sCloudObj.class)
      return {} if not oControlerObject

      sCloudObj = sCloudObj.to_sym if sCloudObj.class == String

      oCoreObject = {
         :object_type => sCloudObj,
         :attrs => {},
         :object => oControlerObject,
      }
      hMap = rhGet(@@meta_obj, sCloudObj, :returns)
      hMap.each { |key, map|
         next if not map
         oCoreObject[:attrs][key] = @oProvider.get_attr(oControlerObject, map)
         raise ForjError.new(), "Unable to map returned value '%s'. Not detected by provider_object_mapping in '%s'" % [key, oCloudObject.class] if oCoreObject[:attrs][key].nil?
      }
      oCoreObject
   end

   def _get_object_params(sCloudObj, fname)

      aParams = ObjectParams.new # hdata is built from scratch everytime

      rhGet(@@meta_obj,sCloudObj, :params).each { |key, hParams|
         case hParams[:type]
            when :data
               hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, key)
               value = @oForjConfig.get(key)
               if hValueMapping
                  raise ForjError.new(), "'%s.%s': No value mapping for '%s'" % [sCloudObj, key, value] if rhExist?(hValueMapping, value) != 1
                  aParams[key] = hValueMapping[value]
               else
                  aParams[key] = value
               end
               if rhExist?(hParams, :mapping) == 1
                  aParams[:hdata][rhGet(hParams, :mapping)] = aParams[key]
               end
            when :CloudObject
               if hParams[:required] and rhExist?(@CloudData, key, :object) != 2
                  byebug
                  raise ForjError.new(), "Object '%s/%s' is not defined. '%s' requirement failed." % [ self.class, key, fname]
               end
               aParams[key] = get_object(key)
            else
               raise ForjError.new(), "Undefined ObjectData '%s'." % [ hParams[:type]]
         end
      }
      aParams
   end

   def _check_required(sCloudObj, fname)
      aCaller = caller
      aCaller.pop

      oObjMissing=[]

      rhGet(@@meta_obj,sCloudObj, :params).each { |key, hParams|
         case hParams[:type]
            when :data
               if hParams[:required] and @oForjConfig.get(key).nil?
                  sSection = ForjDefault.get_meta_section(key)
                  sSection = 'runtime' if not sSection
                  raise ForjError.new(), "key '%s/%s' is not set. '%s' requirement failed." % [ sSection, key, fname], aCaller
               end
            when :CloudObject
               if hParams[:required] and rhExist?(@CloudData, key, :object) != 2
                  oObjMissing << key
               end
         end
      }
      return oObjMissing
   end


   ###################################################
   # Class management Section
   ###################################################

   # Meta Object declaration structure
   # <Object>:
   #   :lambdas:
   #     :create_e:          function to call at 'Create' task
   #     :delete_e:          function to call at 'Delete' task
   #     :update_e:          function to call at 'Update' task
   #     :get_e:             function to call at 'Get'    task
   #     :query_e:           function to call at 'Query'  task
   #   :params:              Defines CloudData (:data) or CloudObj (:CloudObj) needs by the <Object>
   #     :type:              :data or :CloudObj
   #     :mapping:           To automatically create a provider hash data mapped.
   #     :required:          True if this parameter is required.
   #     :setup:             True if this parameter will need to be asked during Forj Account setup.
   #
   @@meta_obj =  {}

   # meta data are defined in defaults.yaml and loaded in ForjDefault class definition
   # Cloud provider can redefine ForjData defaults and add some extra parameters.
   # To get Application defaults, read defaults.yaml, under :sections:
   @@meta_data = {}
   # <Section>:
   #   <CloudData>:          CloudData name. This symbol must be unique, across sections.
   #     :desc:              Description
   #     :readonly:          oForjConfig.set() will fail if readonly is true.
   #                         Can be set, only thanks to oForjConfig.setup()
   #                         or using private oForjConfig._set()
   #     :account_exclusive: Only oForjConfig.get/set() can handle the value
   #                         oConfig.set/get cannot.

      @@Context = {
      :oCurrentObj      => nil, # Defines the Current Object to manipulate
      :needs_optional   => nil, # set optional to true for any next needs declaration
      :needs_setup      => nil  # set setup needs to true for any next needs declaration
   }

   def self.obj_needs_setup
      @@Context[:needs_setup] = true
   end

   def self.obj_needs_NOsetup
      @@Context[:needs_setup] = false
   end

   def self.obj_needs_optional
      @@Context[:needs_optional] = true
   end

   def self.obj_needs_requires
      @@Context[:needs_optional] = false
   end

   # Defines Object and connect to functions events
   def self.define_obj(sCloudObj, hParam = nil)
      return nil if not sCloudObj
      return nil if not [String, Symbol].include?(sCloudObj.class)

      aCaller = caller
      aCaller.pop

      sCloudObj = sCloudObj.to_sym if sCloudObj.class == String
      @@Context[:oCurrentObj] = sCloudObj
      @@Context[:needs_optional] = false
      @@Context[:needs_setup] = false

      if not [Hash].include?(hParam.class)
         if rhExist?(@@meta_obj, sCloudObj) != 1
            raise ForjError.new(), "New undefined object '%s' requires at least one handler. Ex: define_obj :%s, :create_e => myhandler " % [sCloudObj, sCloudObj]
         end
         hParam = {}
      end

      oCloudObj = rhGet(@@meta_obj, sCloudObj)
      if not oCloudObj
         oCloudObj = {
            :lambdas => {:create_e => nil, :delete_e => nil, :update_e => nil, :get_e => nil, :query_e => nil},
            :params => {},
            :query_mapping => { :id => :id, :name => :name},
            :returns => {:id => :id, :name => :name}
         }
         msg = nil
      else
         msg = ""
      end

      sObjectName = "'%s.%s'" %  [self.class, sCloudObj]

      # Checking hParam data
      if not rhGet(hParam, :nohandler)
         hParam.each_key do | key |
            raise ForjError.new(), "'%s' parameter is invalid. Use '%s'" % [key, oCloudObj[:lambdas].keys.join(', ')], aCaller if rhExist?(oCloudObj, :lambdas, key)!= 2
         end
         msg = "%-28s object declared." %  [sObjectName] if not msg
      else
         msg = "%-28s meta object declared." %  [sObjectName] if not msg
      end
      Logging.debug(msg) if msg != ""

      # Setting procs
      rhGet(oCloudObj, :lambdas).each_key { |key|
         next if not hParam.key?(key)

         if self.methods.include?(hParam[key])
            raise ForjError.new(), "'%s' parameter requires a valid instance method." % [key], aCaller
         end
         if hParam[key] == :default
            # By default, we use the event name as default function to call.
            # Those function are predefined in ForjProvider
            # The Provider needs to derive from ForjProvider and redefine those functions.
            oCloudObj[:lambdas][key] = key
         else
            # If needed, ForjProviver redefined can contains some additionnal functions
            # to call.
            oCloudObj[:lambdas][key] = hParam[key]
         end
         }
      rhSet(@@meta_obj, oCloudObj, sCloudObj)
   end

   def self.def_query_attribute(key)
      self.query_mapping(key, key)
   end

   def self.query_mapping(key, map)
      return nil if not [String, Symbol].include?(key.class)
      return nil if not [NilClass, Symbol, String].include?(map.class)

      aCaller = caller
      aCaller.pop

      raise ForjError.new(), "%s: No Object defined. Missing define_obj?" % [ self.class], aCaller if @@Context[:oCurrentObj].nil?

      sCloudObj = @@Context[:oCurrentObj]
      key = key.to_sym if key.class == String

      @@Context[:oCurrentKey] = key

      rhSet(@@meta_obj, map, sCloudObj, :query_mapping, key)
   end

   def self.data_value_mapping(value, map)
      return nil if not [String, Symbol].include?(value.class)
      return nil if not [NilClass, Symbol, String].include?(map.class)

      aCaller = caller
      aCaller.pop

      sCloudObj = @@Context[:oCurrentObj]
      key = @@Context[:oCurrentKey]

      rhSet(@@meta_obj, map, sCloudObj, :value_mapping, key, value)
   end

   def self.def_attribute(key)
      self.get_attr_mapping(key, key)
   end

   def self.get_attr_mapping(key, map = key)
      return nil if not [String, Symbol].include?(key.class)
      return nil if not [NilClass, Symbol, String, Array].include?(map.class)

      aCaller = caller
      aCaller.pop

      raise ForjError.new(), "%s: No Object defined. Missing define_obj?" % [ self.class], aCaller if @@Context[:oCurrentObj].nil?

      sCloudObj = @@Context[:oCurrentObj]
      key = key.to_sym if key.class == String

      rhSet(@@meta_obj, map, sCloudObj, :returns, key)
   end

   # Defines Object CloudData/CloudObj dependency
   def self.obj_needs(sType, sParam, hParams = {})
      return nil if not [String, Symbol].include?(sType.class)
      return nil if not [String, Symbol].include?(sParam.class)

      hParams = {} if not hParams

      hParams[:setup] = @@Context[:needs_setup] if rhExist?(hParams, :setup) != 1
      hParams[:required] = not(@@Context[:needs_optional]) if rhExist?(hParams, :required) != 1

      aCaller = caller
      aCaller.pop

      raise ForjError.new(), "%s: No Object defined. Missing define_obj?" % [ self.class], aCaller if @@Context[:oCurrentObj].nil?

      sCloudObj = @@Context[:oCurrentObj]
      sType = sType.to_sym if sType.class == String
      sParam = sParam.to_sym if sParam.class == String

      @@Context[:oCurrentKey] = sParam

      raise ForjError.new(), "%s: '%s' not declared. Missing define_obj(%s)?" % [ self.class, sCloudObj, sCloudObj], aCaller if rhExist?(@@meta_obj, sCloudObj) != 1

      oCloudObjParam = rhGet(@@meta_obj, sCloudObj, :params, sParam)
      if not oCloudObjParam
         oCloudObjParam = {}
         sMsgAction = "Added"
      else
         sMsgAction = "Updated"
      end
      sObjectName = "'%s.%s'" %  [self.class, sCloudObj]
      case sType
         when :data
            if ForjDefault.meta_exist?(sParam)
               Logging.debug("%-28s: %s predefined config '%s'." % [sObjectName, sMsgAction, sParam])
            else
               Logging.debug("%-28s: %s runtime    config '%s'." % [sObjectName, sMsgAction, sParam])
            end
            oCloudObjParam = hParams.merge({:type => sType}) if not oCloudObjParam.key?(sParam)
         when :CloudObject
            raise ForjError.new(), "%s: '%s' not declared. Missing define_obj(%s)?" % [self.class, sParam, sParam], aCaller if not @@meta_obj.key?(sParam)
            oCloudObjParam = hParams.merge({:type => sType}) if not oCloudObjParam.key?(sParam)
         else
            raise ForjError.new(), "%s: Object parameter type '%s' unknown." % [ self.class, sType ], aCaller
      end
      rhSet(@@meta_obj, oCloudObjParam, sCloudObj, :params, sParam)
   end


   # Defines/update CloudData parameters
   def self.define_data(sCloudData, hMeta)
      return nil if not sCloudData or not hMeta
      return nil if not [String, Symbol].include?(sCloudData.class)
      return nil if hMeta.class != Hash

      aCaller = caller
      aCaller.pop

      sCloudData = sCloudData.to_sym if sCloudData.class == String
      raise ForjError.new(), "%s: Config meta '%s' unknown" % [self.class, sCloudData], aCaller if not ForjDefault.meta_exist?(sCloudData)

      section = ForjDefault.get_meta_section(sCloudData)
      if rhExist?(@@meta_data, section, sCloudData) == 2
         rhGet(@@meta_data, section, sCloudData).merge!(hMeta)
      else
         rhSet(@@meta_data, hMeta, section, sCloudData)
      end

   end

   def self.provides(aObjType)
      @aObjType = aObjType
   end

   def self.defined?(objType)
      @aObjType.include?(objType)
   end

end
