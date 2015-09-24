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

# Internal functions for boot - build_userdata
class ForjCoreProcess
  def load_h_meta(hParams, hpcloud_priv)
    h_meta = {
      'flavor_name' => hParams['maestro#bp_flavor'],
      'cdksite' => hParams[:server_name],
      'cdkdomain' => hParams['dns#domain_name'],
      'eroip' => '127.0.0.1',
      'erosite' => hParams[:server_name],
      'erodomain' => hParams['dns#domain_name'],
      'gitbranch' => hParams['maestro#branch'],
      'security_groups' => hParams['maestro#security_group'],
      'tenant_name' => hParams['maestro#tenant_name'],
      'network_name' => hParams['maestro#network_name'],
      'hpcloud_os_region' => hParams['services#compute'],
      'PUPPET_DEBUG' => 'True',
      'image_name' => hParams['maestro#image_name'],
      'key_name' => hParams['credentials#keypair_name'],
      # The following is used by gardener
      # Remove pad
      'hpcloud_priv' => Base64.strict_encode64(hpcloud_priv).delete('='),
      'compute_os_auth_url' => hParams['gardener#os_auth_uri']
    }

    if hParams['dns#dns_service']
      h_meta['dns_zone'] = hParams['dns#dns_service']
      h_meta['dns_tenantid'] = hParams['dns#dns_tenant_id']
      h_meta['dns_auth_url'] = hParams['credentials#auth_uri']
    end
    # If requested by user, ask Maestro to instantiate a blueprint.
    h_meta['blueprint'] = hParams[:blueprint] if hParams[:blueprint]

    # Add init additionnal git clone steps.
    h_meta['repos'] = hParams[:repos] if hParams[:repos]
    # Add init bootstrap additionnal steps
    h_meta['bootstrap'] = hParams[:bootstrap] if hParams[:bootstrap]

    if hParams[:extra_metadata]
      hParams[:extra_metadata].split(/,/).each do |kv|
        k, v = kv.split(/=/)
        h_meta[k] = v
      end
    end

    tb_metadata(hParams, h_meta)
    ca_root_metadata(hParams, h_meta)
    proxy_metadata(hParams, h_meta)
    lorj_metadata(hParams, h_meta)

    h_meta
  end
end

# Functions for boot - build_userdata
class ForjCoreProcess
  def build_metadata(sObjectType, hParams)
    entr = load_encoded_key

    os_enckey = hParams['gardener#os_enckey']

    os_key = decrypt_key(os_enckey, entr)

    hpcloud_priv = load_hpcloud(hParams, os_key)

    h_meta = load_h_meta(hParams, hpcloud_priv)

    config.set(:meta_data, h_meta) # Used by :server object

    h_meta_printable = h_meta.clone
    h_meta_printable['hpcloud_priv'] = 'XXX - data hidden - XXX'
    m_print = ''
    max_key = 0
    h_meta_printable.keys.each { |k| max_key = [max_key, k.length].max }
    h_meta_printable.keys.sort.each do |k|
      m_print += format("%-#{max_key}s : %s\n",
                        k, ANSI.bold(h_meta_printable[k]))
    end
    PrcLib.info("Metadata set:\n%s", m_print)

    o_meta_data = register(h_meta, sObjectType)
    o_meta_data[:meta_data] = h_meta

    o_meta_data
  end

  def load_encoded_key
    key_file = File.join(PrcLib.pdata_path, '.key')
    if !File.exist?(key_file)
      # Need to create a random key.
      entr = {
        :key => rand(36**10).to_s(36),
        :salt => Time.now.to_i.to_s,
        :iv => Base64.strict_encode64(
          OpenSSL::Cipher::Cipher.new('aes-256-cbc').random_iv
        )
      }

      PrcLib.debug("Writing '%s' key file", key_file)
      File.open(key_file, 'w') do |out|
        out.write(Base64.encode64(entr.to_yaml))
      end
    else
      PrcLib.debug("Loading '%s' key file", key_file)
      encoded_key = IO.read(key_file)
      entr = YAML.load(Base64.decode64(encoded_key))
    end
    entr
  end

  def decrypt_key(os_enckey, entr)
    begin
      os_key = Encryptor.decrypt(
        :value => Base64.strict_decode64(os_enckey),
        :key => entr[:key],
        :iv => Base64.strict_decode64(entr[:iv]),
        :salt => entr[:salt]
      )
    rescue
      raise 'Unable to decript your password. You need to re-execute setup.'
    end
    os_key
  end

  def load_hpcloud(hParams, os_key)
    hpcloud_priv = nil
    IO.popen('gzip -c', 'r+') do|pipe|
      data = <<-END
HPCLOUD_OS_USER='#{hParams['gardener#os_user']}'
HPCLOUD_OS_KEY='#{os_key}'
DNS_KEY='#{hParams[:'credentials#account_id']}'
DNS_SECRET='#{hParams['credentials#account_key']}'
      END
      pipe.puts(data)
      pipe.close_write
      hpcloud_priv = pipe.read
    end
    hpcloud_priv
  end
end
