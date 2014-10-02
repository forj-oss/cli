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

# This file is given as an example.

class Mycloud # This class is automatically derived from ForjCloudBase and ForjProcess

   def provider_compute_new
      # My fog connection
      # hget_cloudObjMapping() is a ForjCloudBase function which will build a
      # hash from data required with needed mapped keys(see core.rb)
      Fog::Compute.new({:provider  => :mycloud}.merge(hget_cloudObjMapping()))

      # If you do not want to get data mapped automatically, you can use
      # @oForjAccount.get()
      # This means in following declaration in your core.rb:
      # obj_needs(:data, :<CloudDataKey},{:mapping => :<MyCloudKeyMapped>})
      # can be updated by removing the mapping => <Value>
      Fog::Compute.new({
         :provider         => :mycloud,
         :user             => @oForjAccount.get(:account_id),
         :pwd              => @oForjAccount.get(:account_key),
         :auth_uri         => @oForjAccount.get(:auth_uri),
         :project          => @oForjAccount.get(:tenant),
         :compute_service  => @oForjAccount.get(:compute),
         })

   end
end
