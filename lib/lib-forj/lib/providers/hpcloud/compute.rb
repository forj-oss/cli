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

module HPCompute
   def HPCompute.get_server(oComputeConnect, sId)
      oComputeConnect.servers.get(sId)
   end

   def HPCompute.query_addresses(oComputeConnect, sQuery)
      oComputeConnect.addresses.all(sQuery)
   end

   def HPCompute.query_server(oComputeConnect, sQuery)
      oComputeConnect.servers.all(sQuery)
   end

   def HPCompute.query_image(oComputeConnect, sQuery)
      # HP Fog query is exact matching. No way to filter with a Regexp
      # Testing it and filtering it.
      # TODO: Be able to support Regexp in queries then extract all and filter.
      oComputeConnect.images.all(sQuery)
   end

   def HPCompute.query_flavor(oComputeConnect, sQuery)
     oComputeConnect.flavors.all(sQuery)
   end

   def HPCompute.create_server(oComputeConnect,
                               sServerName, oSecurity_groups,
                               oImage,      oNetwork,
                               oFlavor,     oKeypairs,
                               oUser_data,  oMeta_data)

      options = {
                :name => sServerName,
                :flavor_id => oFlavor.id,
                :image_id => oImage.id,
                :key_name => oKeypairs.name,
                :security_groups => [oSecurity_groups.name],
                :networks => [oNetwork.id]
                }
      options[:user_data] = oUser_data if oUser_data
      options[:metadata] = oMeta_data if oMeta_data
      server = oComputeConnect.servers.create(options)
      HPCompute.get_server(oComputeConnect, server.id ) if server
   end

   def HPCompute.query_server_assigned_addresses(oComputeConnect, oServer, sQuery)
      # CloudProcess used a simplified way to manage IPs.
      # Following is the translation to get the public IPs for the server

      result = []
      oAddresses = oComputeConnect.addresses.all()
      oAddresses.each { | oElem |
         bFound = true
         sQuery.each { | key, value |
            if not oElem.attributes.key?(key) or oElem.attributes[key] != value
               bFound = false
               break
            end
         }
         result << oElem if bFound
      }
      result
   end

   def HPCompute.server_assign_address(oComputeConnect, oServer)

      while oServer.state != 'ACTIVE'
         sleep(5)
         oServer = oComputeConnect.servers.get(oServer.id)
      end

      oAddresses = oComputeConnect.addresses.all()
      oAddress = nil
      # Search for an available IP
      oAddresses.each { | oElem |
         if oElem.fixed_ip.nil?
            oAddress = oElem
            break
         end
      }

      if oAddress.nil?
         # Create a new public IP to add in the pool.
         oAddress = oComputeConnect.addresses.create
      end
      raise "No Public IP to assign to server '%s'" % oServer.name if oAddress.nil?
      oAddress.server = oServer # associate the server
      oAddress.reload
      # This function needs to returns a list of object.
      # This list must support the each function.
      oAddress
   end
end
