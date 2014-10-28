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


module HPNetwork
   # Network driver
   def HPNetwork.query_network(oNetworkConnect, sQuery)
      oNetworkConnect.networks.all(sQuery)
   end

   def HPNetwork.create_network(oNetworkConnect, name)
      oNetworkConnect.networks.create(:name => name)
   end

   def HPNetwork.delete_network(oNetworkConnect, oNetwork)
      oNetworkConnect.networks.get(oNetwork.id).destroy
   end

   # SubNetwork driver
   def HPNetwork.query_subnetwork(oNetworkConnect, sQuery)
      oNetworkConnect.subnets.all(sQuery)
   end

   def HPNetwork.create_subnetwork(oNetworkConnect, oNetwork, name)
      oNetworkConnect.subnets.create(
         :network_id => oNetwork.id,
         :name => name,
         :cidr => get_next_subnet(oNetworkConnect),
         :ip_version => '4'
      )
   end

   def HPNetwork.delete_subnetwork(oNetworkConnect, oSubNetwork)
      oNetworkConnect.subnets.get(oSubNetwork.id).destroy
   end

   def HPNetwork.get_next_subnet(oNetworkConnect)
      begin
         subnet_values = Array.new
         subnets = oNetworkConnect.subnets.all

         subnets.each do|s|
            subnet_values.push(s.cidr)
         end

         gap = false
         count = 0
         range_used = Array.new
         new_subnet = 0
         new_cidr = ''

         subnet_values = subnet_values.sort!

         subnet_values.each do|value|
            range_used.push(value[5])
         end

         range_used.each do |n|
            if count.to_i == n.to_i
               else
            new_subnet = count
               gap = true
            break
            end
            count += 1
         end

         if gap
            new_cidr = '10.0.%s.0/24' % [count]
         else
            max_value = range_used.max
            new_subnet = max_value.to_i + 1
            new_cidr  = '10.0.%s.0/24' % [new_subnet]
         end
         new_cidr
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end

   # router driver
   def HPNetwork.query_router(oNetworkConnect, sQuery)
      oNetworkConnect.routers.all(sQuery)
   end

   def HPNetwork.update_router(oRouters)
      oRouters.save
   end

   def HPNetwork.create_router(oNetwork, hOptions)
      oNetwork.routers.create(hOptions)
   end

   # router interface

   def HPNetwork.add_interface(oRouter, oSubNetwork)
      oRouter.add_interface(oSubNetwork.id, nil)
   end

   # Port driver
   def HPNetwork.query_port(oNetworkConnect, sQuery)
      oNetworkConnect.ports.all(sQuery)
   end
end
