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

# Forj Process solution

class ForjCoreProcess

   def build_metadata(sObjectType, hParams)
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
      os_enckey = config.get(:os_enckey)

      begin
         os_key = Encryptor.decrypt(
            :value => Base64::strict_decode64(os_enckey),
            :key => entr[:key],
            :iv => Base64::strict_decode64(entr[:iv]),
            :salt => entr[:salt]
         )
      rescue => e
         raise "Unable to decript your password. You need to re-execute setup."
      end

      hpcloud_priv = nil
      IO.popen('gzip -c' , 'r+') {|pipe|
         pipe.puts('HPCLOUD_OS_USER=%s' % [config.get(:os_user)] )
         pipe.puts('HPCLOUD_OS_KEY=%s' % [os_key] )
         pipe.puts('DNS_KEY=%s' % [config.get(:account_id)] )
         pipe.puts('DNS_SECRET=%s' % [config.get(:account_key)])
         pipe.close_write
         hpcloud_priv = pipe.read
      }

      hMeta = {
         'cdksite' => hParams[:instance_name],
         'cdkdomain' => hParams[:domain_name],
         'eroip' => '127.0.0.1',
         'erosite' => hParams[:instance_name],
         'erodomain' => hParams[:domain_name],
         'gitbranch' => hParams[:branch],
         'security_groups' => config.get('security_group'),
         'dns_zone' => hParams[:dns, :service],
         'dns_tenantid' => hParams[:dns, :tenant_id],
         'tenant_name' => hParams[:tenant_name],
         'network_name' => hParams[:network_name],
         'bootstrap' => "git/infra/bootstrap/maestro",
         'hpcloud_os_region' => config.get([:compute]),
         'PUPPET_DEBUG' => 'True',
         'image_name' => config.get('image'),
         'key_name' => config.get('keypair_name'),
         'hpcloud_priv' => Base64.strict_encode64(hpcloud_priv).gsub('=', '') # Remove pad
      }
      config.set(:meta_data, hMeta)

      format_object(sObjectType, hMeta)
   end

   def build_forge(sObjectType, hParams)
      config.set(:server_name, "maestro.%s" % hParams[:instance_name])
      object.Create(:server)
   end
end
