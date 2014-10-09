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

module HPSecurityGroups
   def HPSecurityGroups.query_sg(oNetworkConnect, sQuery)
      oNetworkConnect.security_groups.all(sQuery)
   end

   def HPSecurityGroups.create_sg(oNetwork, name, description)
      params = {:name => name}
      params[:description] = description if description
      oFC.oNetwork.security_groups.create( params )
   end

   def HPSecurityGroups.create_rule(oNetwork, hData)
      oNetwork.security_group_rules.create( hData )
   end

   def HPSecurityGroups.query_rule(oNetwork, sQuery)
      oNetwork.security_group_rules.all(sQuery)
   end

   def HPSecurityGroups.delete_rule(oNetwork, rule_id)
      oNetwork.security_group_rules.get(rule_id).destroy
   end
end

module HPKeyPairs
   def HPKeyPairs.query_keypair(oComputeConnect, sQuery)
      cKeyPairs = oComputeConnect.key_pairs.all()
      aResults = []
      cKeyPairs.each { |sElem|
         bSelect = true
         attributes = sElem.instance_variable_get(:@attributes)
         sQuery.each { | key, value |
            if attributes[key] != value
               bSelect = false
               break
            end
         }
         aResults.push sElem if bSelect
      }
      aResults
   end

   def HPKeyPairs.get_keypair(oComputeConnect, sId)
      #byebug
      oComputeConnect.key_pairs.get(sId)
   end

   def HPKeyPairs.create_sg(oComputeConnect, params)
      oComputeConnect.key_pairs.create( params )
   end
end
