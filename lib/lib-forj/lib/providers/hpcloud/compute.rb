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
   def HPCompute.query_server(oComputeConnect, sQuery)
      oComputeConnect.servers.all(sQuery)
   end

   def HPCompute.query_image(oComputeConnect, sQuery)
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
      oComputeConnect.servers.create(options)
   end

end
