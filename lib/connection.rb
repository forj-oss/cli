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

require 'rubygems'
require 'fog'

#
# Connection module
#

class SSLErrorMgt

   def initialize()
      @iRetry=0
   end

   def ErrorDetected(message,backtrace)
      if message.match('SSLv2/v3 read server hello A: unknown protocol')
         if @iRetry <5
            sleep(2)
            @iRetry+=1
            print "%s/5 try...\r" % @iRetry if $FORJ_LOGGER.level == 0
            return false
         else
            Logging.error('Too many retry. %s' % message)
            return true
         end
      else
         Logging.error("%s\n%s" % [message,backtrace.join("\n")])
         return true
      end
   end

end

class ForjConnection

   attr_accessor :oCompute
   attr_accessor :oNetwork
   attr_accessor :sAccountName

   def initialize(oConfig, bAutoConnect = true)

     Logging.fatal(1, 'Internal Error: Missing global $HPC_ACCOUNTS') if not $HPC_ACCOUNTS

     @oConfig = oConfig
     @sAccountName = @oConfig.get(:account_name)
     @provider='HP' # TODO: Support multiple provider. (Generic Provider object required)
     @sAccountName = @oConfig.get(:provider) if not @sAccountName
     @sAccountName = 'hpcloud' if not @sAccountName

     @credentials = get_credentials()

     # Trying to get Compute object
     compute_connect if bAutoConnect

     # Trying to get Network object
     network_connect if bAutoConnect

   end

   def compute_connect

     oSSLError=SSLErrorMgt.new # Retry object

     Logging.debug("compute: Connecting to '%s' - Project '%s'" % [@provider, @credentials['tenant_id']])
     begin
        @oCompute=Fog::Compute.new({
          :provider        => @provider,
          :hp_access_key   => @credentials['access_key'],
          :hp_secret_key   => @credentials['secret_key'],
          :hp_auth_uri     => @credentials['auth_uri'],
          :hp_tenant_id    => @credentials['tenant_id'],
          :hp_avl_zone     => @credentials['availability_zone'],
          :version         => 'v2'
        })
     rescue => e
       if not oSSLError.ErrorDetected(e.message,e.backtrace)
          retry
       end
       Logging.fatal(1, 'Compute: Unable to connect.', e)
     end
   end

   def network_connect
     # Trying to get Network object
     oSSLError=SSLErrorMgt.new # Retry object
     Logging.debug("HP network: Connecting to '%s' - Project '%s'" % [@provider, @credentials['tenant_id']])
     begin
       @oNetwork=Fog::HP::Network.new({
          :hp_access_key   => @credentials['access_key'],
          :hp_secret_key   => @credentials['secret_key'],
          :hp_auth_uri     => @credentials['auth_uri'],
          :hp_tenant_id    => @credentials['tenant_id'],
          :hp_avl_zone     => @credentials['availability_zone']
       })
     rescue => e
       if not oSSLError.ErrorDetected(e.message,e.backtrace)
          retry
       end
       Logging.fatal(1, 'Network: Unable to connect.', e)
     end

   end

   def get_credentials()
     # TODO: Should support forj credentials. not hpcloud credentials.

     creds = File.join($HPC_ACCOUNTS, @sAccountName)
     if not File.exists?(creds)
        Logging.fatal(1, "'%s' was not configured. Did you executed 'forj setup %s'? Please do it and retry." % [@sAccountName, @sAccountName])
     end
     @oConfig.oConfig.ExtraLoad(creds, :hpc_accounts, @sAccountName)

     template = @oConfig.oConfig.ExtraGet(:hpc_accounts, @sAccountName)
     credentials = {}
     begin
       credentials['access_key'] = template[:credentials][:account_id]
       credentials['secret_key'] = template[:credentials][:secret_key]
       credentials['auth_uri'] = template[:credentials][:auth_uri]
       credentials['tenant_id'] = template[:credentials][:tenant_id]
       credentials['availability_zone'] = template[:regions][:compute]
     rescue => e
       Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
       puts 'your credentials are not configured, delete the file %s and run forj setup again' % [creds]
     end
     credentials
   end

end
