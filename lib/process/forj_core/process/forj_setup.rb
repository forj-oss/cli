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

require 'git'
require 'fileutils'
require 'find'
require 'digest'
require 'json'
require 'encryptor' # gem install encryptor
require 'base64'
require 'net/ssh'

# Functions for setup - DNS management
class ForjCoreProcess
  def create_directory(base_dir)
    return true if FIle.directory?(base_dir)
    if agree("'#{base_dir}' doesn't exist. Do you want to create it?")
      PrcLib.ensure_dir_exists(base_dir)
    else
      return false
    end
  end

  def forj_dns_settings
    config[:dns_settings] = false

    return true unless forj_dns_supported?

    s_ask = 'Optionally, you can ask Maestro to use/manage a domain name on' \
      " your cloud. It requires your DNS cloud service to be enabled.\nDo" \
      ' you want to configure it?'
    config[:dns_settings] = agree(s_ask)
    true
  end

  def forj_dns_settings?(key)
    # Return true to ask the question. false otherwise
    unless config[:dns_settings]
      section, key = Lorj.data.first_section(key)
      config.del(key, :name => 'account', :section => section)
      return false # Do not ask
    end
    true
  end

  def forj_dns_supported?
    unless config[:provider] == 'hpcloud'
      PrcLib.message("maestro running under '%s' provider currently do "\
                     "support DNS setting.\n", config.get(:provider))
      config[:dns_settings] = false
      return false # Do not ask
    end
    true
  end
end

# Functions for setup
class ForjCoreProcess
  def setup_tenant_name
    # TODO: To re-introduce with a Controller call instead.
    o_ssl_error = SSLErrorMgt.new # Retry object
    PrcLib.debug('Getting tenants from hpcloud cli libraries')
    begin
      tenants = Connection.instance.tenants(@sAccountName)
    rescue => e
      retry unless o_ssl_error.ErrorDetected(e.message, e.backtrace, e)
      PrcLib.fatal(1, 'Network: Unable to connect.')
    end
    tenant_id = @oConfig.ExtraGet(:hpc_accounts, @sAccountName,
                                  :credentials).rh_get(:tenant_id)
    tenant_name = nil
    tenants.each do |elem|
      tenant_name = elem['name'] if elem['id'] == tenant_id
    end
    if tenant_name
      PrcLib.debug("Tenant ID '%s': '%s' found.", tenant_id, tenant_name)
      @hAccountData.rh_set(tenant_name, :maestro, :tenant_name)
    else
      PrcLib.error("Unable to find the tenant Name for '%s' ID.", tenant_id)
    end
    @oConfig.set('tenants', tenants)
  end

  # Setup query call
  def setup_ssh_user(_sCloudObj, hParams)
    images = process_query(:image, :name => hParams[:image_name])
    result = { :list => config[:users] }
    if images.length >= 1 && !images[0, :ssh_user].nil?
      result[:default_value] = images[0, :ssh_user]
    end
    result
  end
end
