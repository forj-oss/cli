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

require File.join($PROVIDER_PATH, "compute.rb")
require File.join($PROVIDER_PATH, "network.rb")

# Defines Meta MyCloud object
class Mycloud

   # Defines Object structure and function stored on the Hpcloud class object.

   # ForjCloud has a list of predefined object, like compute_connection, network, ...
   # See lib/providers/core/cloud_data_pref.rb
   
   # Compute Object
   define_obj :compute_connection
   # Defines Data used by compute.
   obj_needs(:data, :account_id,  { :mapping => :user})
   obj_needs(:data, :account_key, { :mapping => :pwd})
   obj_needs(:data, :auth_uri,    { :mapping => :auth_uri})
   obj_needs(:data, :tenant,      { :mapping => :project})
   obj_needs(:data, :compute,     { :mapping => :compute_service})

   define_obj :network_connection
   obj_needs(:data, :account_id,  { :mapping => :user})
   obj_needs(:data, :account_key, { :mapping => :pwd})
   obj_needs(:data, :auth_uri,    { :mapping => :auth_uri})
   obj_needs(:data, :tenant,      { :mapping => :project})
   obj_needs(:data, :network,     { :mapping => :network_service})

   define_obj :network
   obj_needs(:CloudObject, :network_connection)
   obj_needs(:data,        :network_name)

   # defines setup Cloud data
   # This definition is required only if you need to change the predefined data.
   # To get details on what kind of parameters can be applied to a CloudData, see lib/defaults.yaml
   define_data(:account_id,  {:provisioned_by => :setup, :desc => 'MyCloud username'})
   define_data(:account_key, {:provisioned_by => :setup, :desc => 'HPCloud secret Key'})
   define_data(:auth_uri,    {:provisioned_by => :setup, :desc => 'HPCloud Authentication service URL'})
   define_data(:tenant,      {:provisioned_by => :setup, :desc => 'HPCloud Tenant ID'})
   define_data(:compute,     {:provisioned_by => :setup, :desc => 'HPCloud Compute service zone (Ex: region-a.geo-1)'})
   define_data(:network,     {:provisioned_by => :setup, :desc => 'HPCloud Network service zone (Ex: region-a.geo-1)'})

end
