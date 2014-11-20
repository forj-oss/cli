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
   # ------------------------------------------------------
   # Class Definition internal function.
   # ------------------------------------------------------

   def _ask_encrypted(sDesc, sDefault)
      # Checking key file used to encrypt/decrypt passwords
      key_file = File.join($FORJ_CREDS_PATH, '.key')
      if not File.exists?(key_file)
         # Need to create a random key.
         entr = {
            :key => rand(36**10).to_s(36),
            :salt => Time.now.to_i.to_s,
            :iv => Base64::strict_encode64(OpenSSL::Cipher::Cipher.new('aes-256-cbc').random_iv)
         }

         ForjLib.debug(2, "Writing '%s' key file" % key_file)
         File.open(key_file, 'w') do |out|
            out.write(Base64::encode64(entr.to_yaml))
         end
      else
         ForjLib.debug(2, "Loading '%s' key file" % key_file)
         encoded_key = IO.read(key_file)
         entr = YAML.load(Base64::decode64(encoded_key))
      end

      enc_value = sDefault

      if not enc_value.nil?
         begin
            value_hidden = '*' * Encryptor.decrypt(
               :value => Base64::strict_decode64(enc_value),
               :key   => entr[:key],
               :iv    => Base64::strict_decode64(entr[:iv]),
               :salt  => entr[:salt]
            ).length
         rescue => e
            Logging.error("Unable to decrypt your %s. You will need to re-enter it." % sDesc)
            enc_value = ""
         else
            value_hidden="[%s]" % value_hidden
            Logging.message("%s is already set. If you want to keep it, just press Enter" %  [sDesc])
         end
      else
         value_hidden = ""
      end

      value_free = ""
      while value_free == ""
         # ask for encrypted data.
         value_free = ask("Enter %s: [%s]" % [sDesc, value_hidden]) do |q|
            q.echo = '*'
         end
         if value_free == "" and enc_value
            value_free = Encryptor.decrypt(
               :value => Base64::strict_decode64(enc_value),
               :key => entr[:key],
               :iv => Base64::strict_decode64(entr[:iv]),
               :salt => entr[:salt]
            )
         else
            Logging.message("%s cannot be empty." % sDesc) if value_free == ""
         end
      end
      enc_value = Base64::strict_encode64(
         Encryptor.encrypt(
            :value => value_free,
            :key => entr[:key],
            :iv => Base64::strict_decode64(entr[:iv]),
            :salt => entr[:salt]
         )
      )
   end

   def _ask(sDesc, sDefault, rValidate, bEncrypted, bRequired)
      if bEncrypted
         value = _ask_encrypted(sDesc, sDefault)
         if bRequired and value == ""
            say "%sThis information is required!%s" % [ANSI.bold, ANSI.clear]
            while value == ""
               value = _ask_encrypted(sDesc, sDefault)
            end
         end
      else
         value = ask('Enter %s:' % [sDesc]) do |q|
            q.default = sDefault unless sDefault.nil?
            q.validate = rValidate unless rValidate.nil?
         end
         if bRequired and value == ""
            say "%sThis information is required!%s" % [ANSI.bold, ANSI.clear]
            while value == ""
               value = ask('Enter %s:[%s]' % [sDesc, sDefault]) do |q|
                  q.default = sDefault unless sDefault.nil?
                  q.validate = rValidate unless rValidate.nil?
               end
            end
         end
      end
      value.to_s
   end

   # return Object data meta data.
   def _get_meta_data(sKey)

      hMetaDefault = ForjDefault.get_meta(sKey)
      return nil if hMetaDefault.nil?
      hMetaDefault = hMetaDefault.clone

      sSection = ForjDefault.get_meta_section(sKey)
      return hMetaDefault if sSection.nil?
      hMeta = rhGet(@@meta_data, sSection, sKey)
      return hMetaDefault if hMeta.nil?

      hMetaDefault.merge!(hMeta)
   end

   def _return_map(sCloudObj, oControlerObject)
      return nil if oControlerObject.nil?

      attr_value = {}

      pProc = rhGet(@@meta_obj, sCloudObj, :lambdas, :get_attr_e)
      bController = rhGet(@@meta_obj, sCloudObj, :options, :controller)
      return nil if not pProc and not bController

      hMap = rhGet(@@meta_obj, sCloudObj, :returns)
      hMap.each { |key, map|
         oKeyPath = KeyPath.new(key)
         oMapPath = KeyPath.new(map)
         next if not map
         if pProc
            ForjLib::debug(4, "Calling process function '%s' to retrieve/map Controller object '%s' data " % [pProc, sCloudObj])
            controller_attr_value = @oForjProcess.method(pProc).call(sCloudObj, oControlerObject)
         else
            ForjLib::debug(4, "Calling controller function 'get_attr' to retrieve/map Controller object '%s' data " % [sCloudObj])
            controller_attr_value = @oProvider.get_attr(oControlerObject, oMapPath.aTree) if bController
         end

         hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, oKeyPath.sFullPath)
         if hValueMapping and not controller_attr_value.nil?
            hValueMapping.each { | map_key, map_value |
               if controller_attr_value == map_value
                  rhSet(attr_value, map_key ,oKeyPath.aTree)
                  ForjLib::debug(5, "Object '%s' value mapped '%s': '%s' => '%s'" % [sCloudObj, oKeyPath.aTree, controller_attr_value, map_value])
                  break
               end
            }
            raise ForjError.new(), "'%s.%s': No controller value mapping for '%s'." % [sCloudObj, oKeyPath.sKey, controller_attr_value] if attr_value.nil?
         else
            ForjLib::debug(5, "Object '%s' value '%s' extracted: '%s'" % [sCloudObj, oKeyPath.aTree, controller_attr_value])
            rhSet(attr_value, controller_attr_value ,oKeyPath.aTree)
         end
      }
      attr_value
   end

   def _build_data(sCloudObj, oParam, oKeyPath, hParams, bController = false)

      sKey = oKeyPath.sKey
      sDefault = rhGet(hParams, :default_value)
      if rhExist?(hParams, :extract_from) == 1
         value = oParam[hParams[:extract_from]]
      end
      value = @oForjConfig.get(sKey, sDefault) if not value

      if bController
         hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, oKeyPath.sFullPath)

         # Mapping from Object/data definition
         if hValueMapping
            raise ForjError.new(), "'%s.%s': No value mapping for '%s'" % [sCloudObj, sKey, value] if rhExist?(hValueMapping, value) != 1
            value = hValueMapping[value]
# Will be moved to the setup section or while setting it for a controller attached account.
         #~ else
            #~ # Or mapping from Config/data definition
            #~ section = ForjDefault.get_meta_section(sKey)
            #~ section = :runtime if section.nil?
            #~ hValueMapping = rhGet(@@meta_data, section, sKey, :value_mapping)
            #~ if hValueMapping
               #~ raise ForjError.new(), "'%s.%s': No Config value mapping for '%s'" % [section, sKey, value] if rhExist?(hValueMapping, value) != 1
               #~ value = hValueMapping[value]
            #~ end
         end
         if rhExist?(hParams, :mapping) == 1
            # NOTE: if mapping is set, the definition subtree
            # is ignored.
            # if key map to mykey
            # [:section1][subsect][key] = value
            # oParam => [:hdata][mykey] = value
            # not oParam => [:hdata][:section1][subsect][mykey] = value
            rhSet(oParam[:hdata], value, rhGet(hParams, :mapping))
         end
      end
      oParam[oKeyPath.aTree] = value
   end

   def _get_object_params(sCloudObj, sEventType, fname, bController = false)

      oParams = ObjectData.new(not(bController)) # hdata is built for controller. ie, ObjectData is NOT internal.

      hTopParams= rhGet(@@meta_obj,sCloudObj, :params)
      hkeyPaths = rhGet(hTopParams, :keys)
      raise ForjError.new(), "'%s' Object data needs not set. Forgot obj_needs?" % [sCloudObj] if hkeyPaths.nil?

      if sEventType == :delete_e
        if @ObjectData.exist?(sCloudObj)
          oParams.add(@ObjectData[sCloudObj, :ObjectData])
        end
      end

      hkeyPaths.each { | sKeypath, hParams|
         next if not hParams[:for].include?(sEventType)
         oKeyPath = KeyPath.new(sKeypath)
         sKey = oKeyPath.sKey
         case hParams[:type]
            when :data
               _build_data(sCloudObj, oParams, oKeyPath, hParams, bController)
            when :CloudObject
               #~ if hParams[:required] and rhExist?(@CloudData, sKey, :object) != 2
               if hParams[:required] and @ObjectData.type?(sKey) != :DataObject
                  raise ForjError.new(), "Object '%s/%s' is not defined. '%s' requirement failed." % [ self.class, sKey, fname]
               end
               if @ObjectData.exist?(sKey)
                  oParams.add(@ObjectData[sKey, :ObjectData])
               else
                  ForjLib::debug(2, "The optional '%s' was not loaded" % sKey)
               end
            else
               raise ForjError.new(), "Undefined ObjectData '%s'." % [ hParams[:type]]
         end
      }
      oParams
   end

   def _get_controller_map_value(keypath, sProcessValue)
      section = ForjDefault.get_meta_section(sData)
      section = :runtime if section.nil?
      oKeypath = KeyPath.new(keypath)
      sKeyPath = oKeypath.sKeyPath
      return nil if rhExist?(@@meta_data, section, sKeyPath, :controller, sProcessValue) != 4
      rhGet(@@meta_data, section, sKeyPath, :controller, sProcessValue)
   end

   def _get_process_map_value(keypath, sControllerValue)
      section = ForjDefault.get_meta_section(sData)
      section = :runtime if section.nil?
      oKeypath = KeyPath.new(keypath)
      sKeyPath = oKeypath.sKeyPath
      return nil if rhExist?(@@meta_data, section, sKeyPath, :process, sControllerValue) != 4
      rhGet(@@meta_data, section, sKeyPath, :process, sControllerValue)
   end

   def _check_required(sCloudObj, sEventType, fname)
      aCaller = caller
      aCaller.pop

      oObjMissing=[]

      hTopParams= rhGet(@@meta_obj,sCloudObj, :params)
      hkeyPaths = rhGet(hTopParams, :keys)
      raise ForjError.new(), "'%s' Object data needs not set. Forgot obj_needs?" % [sCloudObj] if hkeyPaths.nil?

      if sEventType == :delete_e
        if @ObjectData.type?(sCloudObj) != :DataObject
          oObjMissing << sCloudObj
        end
      end

      hkeyPaths.each { | sKeypath, hParams|
         next if not hParams[:for].include?(sEventType)
         oKeyPath = KeyPath.new(sKeypath)

         sKey = oKeyPath.sKey
         case hParams[:type]
            when :data
               sDefault = rhGet(hParams, :default_value)
               if hParams[:required]
                  if hParams.key?(:extract_from)
                     if not @ObjectData.exist?(hParams[:extract_from])
                        raise ForjError.new(), "key '%s' was not extracted from '%s'. '%s' requirement failed." % [ sKey, hParams[:extract_from], fname], aCaller
                     end
                  elsif @oForjConfig.get(sKey, sDefault).nil?
                     sSection = ForjDefault.get_meta_section(sKey)
                     sSection = 'runtime' if not sSection
                     raise ForjError.new(), "key '%s/%s' is not set. '%s' requirement failed." % [ sSection, sKey, fname], aCaller
                  end
               end
            when :CloudObject
               #~ if hParams[:required] and rhExist?(@CloudData, sKey, :object) != 2
               if hParams[:required] and @ObjectData.type?(sKey) != :DataObject
                  oObjMissing << sKey
               end
         end
      }
      return oObjMissing
   end

end
