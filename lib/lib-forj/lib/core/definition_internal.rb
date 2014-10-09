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

         Logging.debug("Writing '%s' key file" % key_file)
         File.open(key_file, 'w') do |out|
            out.write(Base64::encode64(entr.to_yaml))
         end
      else
         Logging.debug("Loading '%s' key file" % key_file)
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
         raise ForjError.new(), "Attribute '%s' mapped to '%s' is unknown in Controller object '%s'." % [key, map, oControlerObject] if oCoreObject[:attrs][key].nil?
      }
      oCoreObject
   end

   def _build_data(sCloudObj, oParam, sKeypath, hParams)

      aKeyPath = _2tree_array(sKeypath)
      sKey = aKeyPath[-1]
      hValueMapping = rhGet(@@meta_obj, sCloudObj, :value_mapping, sKey)
      sDefault = rhGet(hParams, :default_value)
      value = @oForjConfig.get(sKey, sDefault)
      if hValueMapping
         raise ForjError.new(), "'%s.%s': No value mapping for '%s'" % [sCloudObj, key, value] if rhExist?(hValueMapping, value) != 1
         value = hValueMapping[value]
      end

      oParam[aKeyPath] = value
      if rhExist?(hParams, :mapping) == 1
         # NOTE: if mapping is set, the definition subtree
         # is ignored.
         # if key map to mykey
         # [:section1][subsect][key] = value
         # oParam => [:hdata][mykey] = value
         # not oParam => [:hdata][:section1][subsect][mykey] = value
         oParam[:hdata][rhGet(hParams, :mapping)] = value
      end
   end

   def _get_object_params(sCloudObj, fname)

      oParams = ObjectParams.new # hdata is built from scratch everytime

      hTopParams= rhGet(@@meta_obj,sCloudObj, :params)
      hkeyPaths = rhGet(hTopParams, :list)
      raise ForjError.new(), "'%s' Object data needs not set. Forgot obj_needs?" % [sCloudObj] if hkeyPaths.nil?

      hkeyPaths.each { | sKeypath|
         hParams = rhGet(hTopParams, :keys, sKeypath)
         sKey = _2tree_array(sKeypath)[-1]
         case hParams[:type]
            when :data
               _build_data(sCloudObj, oParams, sKeypath, hParams)
            when :CloudObject
               if hParams[:required] and rhExist?(@CloudData, sKey, :object) != 2
                  raise ForjError.new(), "Object '%s/%s' is not defined. '%s' requirement failed." % [ self.class, sKey, fname]
               end
               oParams[sKey] = get_object(sKey)
            else
               raise ForjError.new(), "Undefined ObjectData '%s'." % [ hParams[:type]]
         end
      }
      oParams
   end

   def _2tree_array(sKeyPath)
      return sKeyPath if sKeyPath.is_a?(Array)
      return nil if not sKeyPath.is_a?(String)

      aResult = sKeyPath.split('/')
      aResult.each_index { | iIndex |
         next if not aResult[iIndex].is_a?(String)
         aResult[iIndex] = aResult[iIndex][1..-1].to_sym if aResult[iIndex][0] == ":"
      }
   end

   def _2path(aArray)

      aKeyAccess = aArray.clone
      aKeyAccess.each_index { |iIndex|
         next if not sParam[iIndex].is_a?(Symbol)
         aKeyAccess[iIndex] = ":" + aKeyAccess[iIndex].to_s
      }
      aKeyAccess.join('/')
   end

   def _check_required(sCloudObj, fname)
      aCaller = caller
      aCaller.pop

      oObjMissing=[]

      hTopParams= rhGet(@@meta_obj,sCloudObj, :params)
      hkeyPaths = rhGet(hTopParams, :list)
      raise ForjError.new(), "'%s' Object data needs not set. Forgot obj_needs?" % [sCloudObj] if hkeyPaths.nil?

      hkeyPaths.each { | sKeypath|
         hParams = rhGet(hTopParams, :keys, sKeypath)
         sKey = _2tree_array(sKeypath)[-1]
         case hParams[:type]
            when :data
               sDefault = rhGet(hParams, :default_value)
               if hParams[:required] and @oForjConfig.get(sKey, sDefault).nil?
                  sSection = ForjDefault.get_meta_section(sKey)
                  sSection = 'runtime' if not sSection
                  raise ForjError.new(), "key '%s/%s' is not set. '%s' requirement failed." % [ sSection, sKey, fname], aCaller
               end
            when :CloudObject
               if hParams[:required] and rhExist?(@CloudData, sKey, :object) != 2
                  oObjMissing << sKey
               end
         end
      }
      return oObjMissing
   end

end
