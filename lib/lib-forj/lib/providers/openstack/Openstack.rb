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


# This class describes how to process some actions, and will do everything prior
# this task to make it to work.


class Openstack < BaseDefinition
   def initialize()
      superclass.provides([:compute, :network])
   end
   
   def compute()
      Fog::Compute.new({
         :provider            => :openstack,
         :openstack_api_key   => superclass.oForjAccount.get(:account_id),
         :openstack_username  => superclass.oForjAccount.get(:account_key),
         :openstack_auth_url  => superclass.oForjAccount.get(:auth_uri),
         :openstack_tenant    => superclass.oForjAccount.get(:tenant_id),
         :openstack_region    => superclass.oForjAccount.get(:compute)
         })
   end
   def network()
      Fog::Network.new({
         :provider            => :openstack,
         :openstack_api_key   => superclass.oForjAccount.get(:account_id),
         :openstack_username  => superclass.oForjAccount.get(:account_key),
         :openstack_auth_url  => superclass.oForjAccount.get(:auth_uri),
         :openstack_tenant    => superclass.oForjAccount.get(:tenant_id),
         :openstack_region    => superclass.oForjAccount.get(:network)
         })
   end
end
