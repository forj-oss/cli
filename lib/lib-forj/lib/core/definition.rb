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


class BaseDefinition

   private
   
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
   #     :list:              Array defining a list of key path (array)
   #     :keys:              Contains keys in a tree of hash.
   #       <keypath>:        One element (string with : and /) of :list defining the key
   #         :type:          :data or :CloudObj
   #         :mapping:       To automatically create a provider hash data mapped.
   #         :required:      True if this parameter is required.
   #
   @@meta_obj =  {}

   # meta data are defined in defaults.yaml and loaded in ForjDefault class definition
   # Cloud provider can redefine ForjData defaults and add some extra parameters.
   # To get Application defaults, read defaults.yaml, under :sections:
   @@meta_data = {}
   # <Section>:
   #   <Data>:               Data name. This symbol must be unique, across sections.
   #     :desc:              Description
   #     :readonly:          oForjConfig.set() will fail if readonly is true.
   #                         Can be set, only thanks to oForjConfig.setup()
   #                         or using private oForjConfig._set()
   #     :account_exclusive: Only oForjConfig.get/set() can handle the value
   #                         oConfig.set/get cannot.
   #     :account:           If exists, setup will ask value
   #     :depends_on:        Identify :data type required to be set before the current one.
   #     :list_values:       Defines a list of valid values for the current data.
   #       :object:          if set, setup will create that object to get data
   #       :query:           or setup will query that object to get a list of data.
   #                         the query string provided is transmitted to the query function.
   #       :values:          when :object/:query is defined, identify the data
   #                         to retrieve from.
   #                         otherwise define simply a list of possible values.

   @@Context = {
      :oCurrentObj      => nil, # Defines the Current Object to manipulate
      :needs_optional   => nil  # set optional to true for any next needs declaration
   }

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
      return nil if not [String, Symbol, Array].include?(sParam.class)

      hParams = {} if not hParams

      hParams[:required] = not(@@Context[:needs_optional]) if rhExist?(hParams, :required) != 1

      aCaller = caller
      aCaller.pop

      raise ForjError.new(), "%s: No Object defined. Missing define_obj?" % [ self.class], aCaller if @@Context[:oCurrentObj].nil?

      sCloudObj = @@Context[:oCurrentObj]
      sType = sType.to_sym if sType.class == String


      raise ForjError.new(), "%s: '%s' not declared. Missing define_obj(%s)?" % [ self.class, sCloudObj, sCloudObj], aCaller if rhExist?(@@meta_obj, sCloudObj) != 1

      oObjTopParam = rhGet(@@meta_obj, sCloudObj, :params)
      if not oObjTopParam.key?(:list)
         # Initialize top structure

         oObjTopParam.merge!({ :list => [], :keys => {} })
      end
      oKeysList = oObjTopParam[:list]
      # Identify, key, path and key access.
      if not sParam.is_a?(Array)
         sKeyAccess = sParam
         sKeyAccess = ":" + sParam.to_s if sParam.is_a?(Symbol)
      else
         aKeyAccess = sParam.clone
         aKeyAccess.each_index { |iIndex|
            next if not sParam[iIndex].is_a?(Symbol)
            aKeyAccess[iIndex] = ":" + aKeyAccess[iIndex].to_s
         }
         sKeyAccess = aKeyAccess.join('/')
      end

      @@Context[:oCurrentKey] = sKeyAccess

      oCloudObjParam = rhGet(oObjTopParam, :keys, sKeyAccess)
      if oCloudObjParam.nil?
         sMsgAction = "New"
         oObjTopParam[:keys][sKeyAccess] = {}
         oCloudObjParam = oObjTopParam[:keys][sKeyAccess]
      else
         sMsgAction = "Upd"
      end
      sObjectName = "'%s.%s'" %  [self.class, sCloudObj]
      case sType
         when :data
            if ForjDefault.meta_exist?(sParam)
               Logging.debug("%-28s: %s predefined config '%s'." % [sObjectName, sMsgAction, sParam])
            else
               Logging.debug("%-28s: %s runtime    config '%s'." % [sObjectName, sMsgAction, sParam])
            end
            oCloudObjParam.merge!( hParams.merge({:type => sType}) ) # Merge from predefined params, but ensure type is never updated.
         when :CloudObject
            raise ForjError.new(), "%s: '%s' not declared. Missing define_obj(%s)?" % [self.class, sParam, sParam], aCaller if not @@meta_obj.key?(sParam)
            oCloudObjParam.merge!( hParams.merge({:type => sType}) ) # Merge from predefined params, but ensure type is never updated.
         else
            raise ForjError.new(), "%s: Object parameter type '%s' unknown." % [ self.class, sType ], aCaller
      end
      oKeysList << sKeyAccess unless oKeysList.include?(sKeyAccess)
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
