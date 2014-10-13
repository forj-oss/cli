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

class SSLErrorMgt

   def initialize(iMaxRetry = 5)
      @iRetry = 0
      @iMaxRetry = iMaxRetry
   end

   def ErrorDetected(message,backtrace)
      if message.match('SSLv2/v3 read server hello A: unknown protocol')
         if @iRetry <@iMaxRetry
            sleep(2)
            @iRetry+=1
            print "%s/%s try...\r" % [@iRetry, @iMaxRetry] if $FORJ_LOGGER.level == 0
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


class CloudProcess < BaseProcess
   def connect(sCloudObj, hParams)
      oSSLError = SSLErrorMgt.new # Retry object
      Logging.debug("%s:%s Connecting to '%s' - Project '%s'" % [self.class, sCloudObj, config.get(:provider), hParams[:tenant]])
      begin
         controler.connect(sCloudObj)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
         Logging.error('%s:%s: Unable to connect.\n%s' % [self.class, sCloudObj, e.message ])
         nil
      end
   end
end

class CloudProcess
   def forj_get_or_create_keypair(sCloudObj, hParams)
      sKeypair_name = hParams[:keypair_name]
      Logging.state("Searching for keypair '%s'..." % [sKeypair_name] )

      keypair = forj_query_keypair(sCloudObj, {:name => sKeypair_name}, hParams)
      keypair = create_keypair(sCloudObj,hParams) if not keypair
      keypair
   end

   def forj_query_keypair(sCloudObj, sQuery, hParams)
      key_name = hParams[:keypair_name]
      oSSLError = SSLErrorMgt.new
      begin
         query_single(sCloudObj, sQuery, key_name)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
      end

   end

   def keypair_create(sCloudObj,hParams)
      key_name = hParams[:keypair_name]
      Logging.debug("Importing keypair '%s'" % [key_name])
      oSSLError=SSLErrorMgt.new
      begin
         controler.create(sCloudObj)
      rescue StandardError => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
         Logging.error "error importing keypair '%s'" % [key_name]
      end
   end

   def keypair_detect(keypair_name, key_fullpath)
      # Build key data information structure.
      # Take care of priv with or without .pem and pubkey with pub.

      key_basename = File.basename(key_fullpath)
      key_path = File.expand_path(File.dirname(key_fullpath))

      mObj = key_basename.match(/^(.*?)(\.pem|\.pub)?$/)
      key_basename = mObj[1]

      private_key_ext = nil
      private_key_ext = "" if File.exists?(File.join(key_path, key_basename))
      private_key_ext = '.pem' if File.exists?(File.join(key_path, key_basename + '.pem'))
      if private_key_ext
         private_key_exist = true
         private_key_name = key_basename + private_key_ext
      else
         private_key_exist = false
         private_key_name = key_basename
      end

      public_key_exist = File.exists?(File.join(key_path, key_basename + '.pub'))
      public_key_name = key_basename + '.pub'


      {:keypair_name     => keypair_name,
       :keypair_path     => key_path,         :key_basename       => key_basename,
       :private_key_name => private_key_name, :private_key_exist? => private_key_exist,
       :public_key_name  => public_key_name,  :public_key_exist?  => public_key_exist,
      }
   end

   def hpc_import_key(oForjAccount)

      keys = keypair_detect(oForjAccount.get('keypair_name'), oForjAccount.get('keypair_path'))
      account = oForjAccount.getAccountData(:account, :name)

      Logging.fatal(1, "'keypair_path' undefined. check your config.yaml file.") if not keys[:keypair_path]
      Logging.fatal(1, "'keypair_name' undefined. check your config.yaml file.") if not keys[:keypair_name]
      Logging.fatal(1, "keypair '%s' are missing. Please call 'forj setup %s' to create the missing key pair required." % [keys[:keypair_name], account]) if not keys[:public_key_exist? ]

      public_key_path = File.join(keys[:keypair_path], keys[:public_key_name])
      private_key_path = File.join(keys[:keypair_path], keys[:private_key_name])

      if not File.exists?(File.join($HPC_KEYPAIRS, keys[:keypair_name] + '.pub'))
         Logging.info("Importing your forj public key '%s' to hpcloud." % keys[:public_key_name])
         command = 'hpcloud keypairs:import %s %s -a %s' % [keys[:keypair_name], public_key_path , account]
         Logging.debug("Executing command '%s'" % command)
         Kernel.system(command)
      else
         Logging.info("Using '%s' as public key." % public_key_path)
      end

      if not File.exists?(File.join($HPC_KEYPAIRS, keys[:keypair_name] + '.pem'))
         if keys[:private_key_exist? ]
            Logging.info("Importing your forj private key '%s' to hpcloud." % private_key_path)
            command = 'hpcloud keypairs:private:add %s %s' % [keys[:keypair_name], private_key_path]
            Logging.debug("Executing command '%s'" % command)
            Kernel.system(command)
         else
            Logging.warning('Unable to find the private key. This will be required to access with ssh to Maestro and any blueprint boxes.')
         end
      else
         Logging.info("Using '%s' as private key." % private_key_path)
      end
   end

   # Depending on clouds/rights, we can create flavor or not.
   # Usually, flavor records already exists, and the controller may map them
   # CloudProcess predefines some values. Consult CloudProcess.rb for details
   def forj_get_or_create_flavor(sCloudObj, hParams)
      sFlavor_name = hParams[:flavor_name]
      Logging.state("Searching for flavor '%s'..." % [sFlavor_name] )

      flavor = forj_query_flavor(sCloudObj, {:name => sFlavor_name}, hParams)
      if not flavor
         if not hParams[:create]
            Logging.error("Unable to create %s '%s'. Creation is not supported." % [sCloudObj, sFlavor_name])
         else
            flavor = create_flavor(sCloudObj,hParams)
         end
      end
      flavor
   end

   # Should return 1 or 0 flavor.
   def forj_query_flavor(sCloudObj, sQuery, hParams)
      sFlavor_name = hParams[:flavor_name]
      oSSLError = SSLErrorMgt.new
      begin
         query_single(sCloudObj, sQuery, sFlavor_name)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
      end

   end
end


class CloudProcess < BaseProcess
  def forj_get_or_create_image(sCloudObj, hParams)
    sImage_name = hParams[:image]
    Logging.state("Searching for image '%s'..." % [sImage_name] )

    forj_query_image(sCloudObj, {:name => sImage_name}, hParams)
  end

  def forj_query_image(sCloudObj, sQuery, hParams)
    image_name = hParams[:image]
    oSSLError = SSLErrorMgt.new
    begin
      images = controler.query(sCloudObj, sQuery)
      case images[:list].length()
        when 0
          Logging.debug("No image '%s' found" % [ image_name ] )
          nil
        else
          Logging.debug("Found image '%s'." % [ image_name ])
          images[:list][0]
      end
    rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
        retry
      end
    end
  end
end

class CloudProcess < BaseProcess
   # Process Handler functions
   def forj_get_or_create_server(sCloudObj, hParams)
      sServer_name = hParams[:server_name]
      Logging.state("Searching for server '%s'..." % [sServer_name] )

      server = forj_query_server(sCloudObj, {:name => sServer_name}, hParams)
      create_server(sCloudObj, hParams) if not server
   end

   def forj_query_server(sCloudObj, sQuery, hParams)
      server_name = "Undefined"
      server_name = sQuery[:name] if sQuery.key?(:name)
      oSSLError = SSLErrorMgt.new
      begin
         query_single(sCloudObj, sQuery, server_name)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
           retry
         end
      end
   end

   # Internal Process function
   def create_server(sCloudObj, hParams)
      name = hParams[:server_name]
      begin
         Logging.debug('creating server %s' % [name])
         controler.create(sCloudObj)
      rescue => e
         Logging.fatal(1, "Unable to create server '%s'" % name, e)
      end
   end

end
