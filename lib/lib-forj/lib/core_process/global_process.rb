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
      # setup has configured and copied the appropriate key to forj keypairs.

      hKeys = keypair_detect(sKeypair_name, File.expand_path(hParams[:keypair_path]))
      if hKeys[:private_key_exist? ]
         hParams[:private_key_file] = File.join(hKeys[:keypair_path], hKeys[:private_key_name])
         Logging.info("Openssh private key file '%s' exists." % hParams[:private_key_file])
      end
      if hKeys[:public_key_exist? ]
         hParams[:public_key_file] = File.join(hKeys[:keypair_path], hKeys[:public_key_name])
      else
         Logging.fatal("Public key file is not found. Please run 'forj setup %s'" % config[:account_name])
      end


      Logging.state("Searching for keypair '%s'" % [sKeypair_name] )

      keypairs = forj_query_keypair(sCloudObj, {:name => sKeypair_name}, hParams)
      if keypairs.length > 0
         keypair = keypairs[0]
      else
         keypair = create_keypair(sCloudObj,hParams)
      end
      # Adding information about key files.
      keypair[:private_key_file] = hParams[:private_key_file]
      keypair[:public_key_file] = hParams[:public_key_file]
      keypair
   end

   def forj_query_keypair(sCloudObj, sQuery, hParams)
      key_name = hParams[:keypair_name]
      oSSLError = SSLErrorMgt.new
      begin
         oList = controler.query(sCloudObj, sQuery)
         query_single(sCloudObj, oList, sQuery, key_name)
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

   # Depending on clouds/rights, we can create flavor or not.
   # Usually, flavor records already exists, and the controller may map them
   # CloudProcess predefines some values. Consult CloudProcess.rb for details
   def forj_get_or_create_flavor(sCloudObj, hParams)
      sFlavor_name = hParams[:flavor_name]
      Logging.state("Searching for flavor '%s'" % [sFlavor_name] )

      flavors = forj_query_flavor(sCloudObj, {:name => sFlavor_name}, hParams)
      if flavors.length == 0
         if not hParams[:create]
            Logging.error("Unable to create %s '%s'. Creation is not supported." % [sCloudObj, sFlavor_name])
            ForjLib::Data.new.set(nil, sCloudObj)
         else
            create_flavor(sCloudObj,hParams)
         end
      else
         flavors[0]
      end
   end

   # Should return 1 or 0 flavor.
   def query_flavor(sCloudObj, sQuery, hParams)
      sFlavor_name = hParams[:flavor_name]
      forj_query_flavor(sCloudObj, sQuery, hParams)
      query_single(sCloudObj, oList, sQuery, sFlavor_name)
   end

   # Should return 1 or 0 flavor.
   def forj_query_flavor(sCloudObj, sQuery, hParams)
      sFlavor_name = hParams[:flavor_name]
      oSSLError = SSLErrorMgt.new
      begin
         oList = controler.query(sCloudObj, sQuery)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
      end
      oList
   end
end


class CloudProcess < BaseProcess
   def forj_get_or_create_image(sCloudObj, hParams)
      sImage_name = hParams[:image_name]
      Logging.state("Searching for image '%s'" % [sImage_name] )

      search_the_image(sCloudObj, {:name => sImage_name}, hParams)
      # No creation possible.
   end

   def search_the_image(sCloudObj, sQuery, hParams)
      image_name = hParams[:image_name]
      images = forj_query_image(sCloudObj, sQuery, hParams)
      case images.length()
        when 0
          Logging.info("No image '%s' found" % [ image_name ] )
          nil
        else
          Logging.info("Found image '%s'." % [ image_name ])
          images[0]
      end
   end

   def forj_query_image(sCloudObj, sQuery, hParams)
      oSSLError = SSLErrorMgt.new
      begin
         controler.query(sCloudObj, sQuery)
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
      Logging.state("Searching for server '%s'" % [sServer_name] )
      servers = forj_query_server(sCloudObj, {:name => sServer_name}, hParams)
      if servers.length > 0
         # Get server details
         forj_get_server(sCloudObj, servers[0][:attrs][:id], hParams)
      else
         create_server(sCloudObj, hParams)
      end
   end

   def forj_query_server(sCloudObj, sQuery, hParams)
      server_name = "Undefined"
      server_name = sQuery[:name] if sQuery.key?(:name)
      oSSLError = SSLErrorMgt.new
      begin
         oList = controler.query(sCloudObj, sQuery)
         query_single(sCloudObj, oList, sQuery, server_name)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
           retry
         end
      end
   end

   def forj_get_server(sCloudObj, sId, hParams)
      oSSLError = SSLErrorMgt.new
      begin
         controler.get(sCloudObj, sId)
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
         Logging.state('creating server %s' % [name])
         server = controler.create(sCloudObj)
         Logging.info("%s '%s' created." % [sCloudObj, name])
      rescue => e
         Logging.fatal(1, "Unable to create server '%s'" % name, e)
      end
      server
   end

   def forj_get_server_log(sCloudObj, sId, hParams)
      oSSLError = SSLErrorMgt.new
      begin
         controler.get(sCloudObj, sId)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
           retry
         end
      end
   end
end

class CloudProcess < BaseProcess
   # Process Handler functions
   def forj_get_or_assign_public_address(sCloudObj, hParams)
      # Function which to assign a public IP address to a server.
      sServer_name = hParams[:server, :name]

      Logging.state("Searching public IP for server '%s'" % [sServer_name] )
      addresses = controler.query(sCloudObj, {:server_id => hParams[:server, :id]})
      if addresses.length == 0
         assign_address(sCloudObj, hParams)
      else
         addresses[0]
      end
   end

   def forj_query_public_address(sCloudObj, sQuery, hParams)
      server_name = hParams[:server, :name]
      oSSLError = SSLErrorMgt.new
      begin
         sInfo = {
         :notfound   => "No %s for '%s' found",
         :checkmatch => "Found 1 %s. checking exact match for server '%s'.",
         :nomatch    => "No %s for '%s' match",
         :found      => "Found %s '%s' for #{server_name}.",
         :more       => "Found several %s. Searching for '%s'.",
         :items      => :public_ip
         }
         oList = controler.query(sCloudObj, sQuery)
         query_single(sCloudObj, oList, sQuery, server_name, sInfo)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
           retry
         end
      end
   end

   def forj_get_public_address(sCloudObj, sId, hParams)
      oSSLError = SSLErrorMgt.new
      begin
         controler.get(sCloudObj, sId)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
           retry
         end
      end
   end

   # Internal Process function
   def assign_address(sCloudObj, hParams)
      name = hParams[:server, :name]
      begin
         Logging.state('Getting public IP for server %s' % [name])
         ip_address = controler.create(sCloudObj)
         Logging.info("Public IP '%s' for server '%s' assigned." % [ip_address[:public_ip], name])
      rescue => e
         Logging.fatal(1, "Unable to assign a public IP to server '%s'" % name, e)
      end
      ip_address
   end
end
