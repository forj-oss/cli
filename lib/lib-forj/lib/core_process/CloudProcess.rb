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

# It requires Core objects to be defined + default ForjProcess functions.

require File.join($CORE_PROCESS_PATH, "global_process.rb")
require File.join($CORE_PROCESS_PATH, "network_process.rb")

# Define framework object on BaseDefinition
class BaseDefinition

   # predefined list of objects.
   # Links between objects is not predefined. To do it, use needs declaration in your provider class.

   # object to get list of services
   # Defines Process handler to call
   define_obj(:services,
      {
         :create_e => :connect
      })
   obj_needs   :data, :auth_uri
   obj_needs   :data, :account_id
   obj_needs   :data, :account_key
   obj_needs   :data, :tenant

   get_attr_mapping :id, nil    # Do not return any predefined ID
   get_attr_mapping :name, nil  # Do not return any predefined NAME


   # compute_connection
   define_obj(:compute_connection,
      {
         :create_e => :connect # Will call ForjProcess connect
      })
   obj_needs   :data, :account_id
   obj_needs   :data, :account_key
   obj_needs   :data, :auth_uri
   obj_needs   :data, :tenant
   obj_needs   :data, :compute

   get_attr_mapping :id, nil    # Do not return any predefined ID
   get_attr_mapping :name, nil  # Do not return any predefined NAME

   # network_connection
   define_obj(:network_connection,
      {
         :create_e => :connect
      })
   obj_needs   :data, :account_id
   obj_needs   :data, :account_key
   obj_needs   :data, :auth_uri
   obj_needs   :data, :tenant
   obj_needs   :data, :network

   get_attr_mapping :id, nil    # Do not return any predefined ID
   get_attr_mapping :name, nil  # Do not return any predefined NAME

   # Identify the network
   define_obj(:network,
              :create_e    => :forj_get_or_create_network,
              :query_e     => :forj_query_network,
              :get_e       => :forj_get_network,
              :delete_e    => :forj_delete_network
             )
   obj_needs   :CloudObject,  :network_connection
   obj_needs   :data,         :network_name,       { :for => [:create_e] }

   obj_needs_optional
   obj_needs   :data,         :subnetwork_name,    { :for => [:create_e] }

   def_query_attribute :external # true if network is external or not.

   # Identify subnetwork as part of network.
   define_obj(:subnetwork,    :nohandler => true)

   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :network

   def_query_attribute :network_id

   # Identify port attached to network
   define_obj   :port,    :nohandler => true

   def_attribute :device_id

   def_query_attribute :network_id
   def_query_attribute :device_owner

   # Identify the router of a network.
   define_obj(:router,
      {
         :create_e   => :forj_get_or_create_router,
         :query_e    => :forj_query_router,
         :get_e      => :forj_get_router,
         :update_e   => :forj_update_router,
         :delete_e   => :forj_delete_router
      })
   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :network,            { :for => [:create_e] }
   obj_needs   :CloudObject,  :subnetwork,         { :for => [:create_e] }
   obj_needs_optional
   obj_needs   :data,         :router_name,        { :for => [:create_e] }

   def_attribute :gateway_network_id

   # Identify an external network thanks to the network router.
   define_obj(:external_network,
      {
         :create_e   => :forj_get_or_create_ext_net,
         :query_e    => :forj_query_external_network
      })

   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :router


   # Identify security_groups
   define_obj(:security_groups,
      {
         :create_e   => :forj_get_or_create_sg,
         :query_e    => :forj_query_sg,
         :delete_e   => :forj_delete_sg
      })

   obj_needs   :CloudObject,  :network_connection
   obj_needs   :data,         :security_group,     { :for => [:create_e] }
   obj_needs_optional
   obj_needs   :data,         :sg_desc,            { :for => [:create_e] }

   # Identify Rules attached to the security group
   define_obj(:rule,
      {
         :create_e   => :forj_get_or_create_rule,
         :query_e    => :forj_query_rule,
         :delete_e   => :forj_delete_rule
      })

   get_attr_mapping :name, nil  # Do not return any predefined name attribute

   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :security_groups,    { :for => [:create_e] }
   obj_needs   :data,         :sg_id,              { :for => [:create_e], :extract_from => [:security_groups, :attrs, :id] }
   obj_needs   :data,         :dir,                { :for => [:create_e] }
   predefine_data_value :IN,  { :desc => "Input NAT/firewall rule map type" }
   predefine_data_value :OUT, { :desc => "Output NAT/firewall rule map type" }
   obj_needs   :data,         :proto,              { :for => [:create_e] }
   obj_needs   :data,         :port_min,           { :for => [:create_e] }
   obj_needs   :data,         :port_max,           { :for => [:create_e] }
   obj_needs   :data,         :addr_map,           { :for => [:create_e] }

   # Identify keypair
   define_obj(:keypairs,
      {
         :create_e   => :forj_get_or_create_keypair,
         :query_e    => :forj_query_keypair,
         :delete_e   => :forj_delete_keypair
      })

   obj_needs   :CloudObject,  :compute_connection
   obj_needs   :data,         :keypair_name,       { :for => [:create_e] }
   obj_needs   :data,         :keypair_path,       { :for => [:create_e] }

   # Identify image
   define_obj(:image,
      {
         :create_e   => :forj_get_or_create_image,
         :query_e    => :forj_query_image,
         :get_e      => :forj_get_image,
         :update_e   => :forj_update_image,
         :delete_e   => :forj_delete_image
      })

   obj_needs   :CloudObject,  :compute_connection
   obj_needs   :data,         :image_name,         { :for => [:create_e] }

   # Identify flavor
   define_obj(:flavor,
      {
         :create_e   => :forj_get_or_create_flavor,
         :query_e    => :forj_query_flavor,
         :get_e      => :forj_get_flavor,
         :update_e   => :forj_update_flavor,
         :delete_e   => :forj_delete_flavor
      })

   obj_needs   :CloudObject,  :compute_connection

   obj_needs   :data,         :flavor_name,        { :for => [:create_e] }
   # Cloud provider will need to map to one of those predefined flavors.
   # limitation values may match exactly or at least ensure those limitation
   # are under provider limitation
   # ie, at least the CloudProcess limitation can less than the Cloud provider defines.
   # CloudProcess EHD = 160, then Provider EHD = 200 is ok
   # but Provider EHD = 150 is not ok.
   predefine_data_value('tiny',   { :desc => "VCU: 1,  RAM:512M, HD:1G,   EHD: 0G,   Swap: 0G" })
   predefine_data_value('xsmall', { :desc => "VCU: 1,  RAM:1G,   HD:10G,  EHD: 10G,  Swap: 0G" })
   predefine_data_value('small',  { :desc => "VCU: 2,  RAM:2G,   HD:30G,  EHD: 10G,  Swap: 0G" })
   predefine_data_value('medium', { :desc => "VCU: 2,  RAM:4G,   HD:30G,  EHD: 50G,  Swap: 0G" })
   predefine_data_value('large',  { :desc => "VCU: 4,  RAM:8G,   HD:30G,  EHD: 100G, Swap: 0G" })
   predefine_data_value('xlarge', { :desc => "VCU: 8,  RAM:16G,  HD:30G,  EHD: 200G, Swap: 0G" })

   # Define Internet network
   #
   # This object contains the logic to ensure the router's network has a gateway to the external network (internet)
   # is capable to connect to internet
   # And to create this connection if possible.

   define_obj(:internet_network,    :nohandler => true )

   obj_needs   :CloudObject,  :external_network # External network to connect if needed.

   # Identify the server to use/build on the network/...
   define_obj(:server,
      {
         :create_e   => :forj_get_or_create_server,
         :query_e    => :forj_query_server,
         :get_e      => :forj_get_server,
         :update_e   => :forj_update_server,
         :delete_e   => :forj_delete_server
      })

   obj_needs   :CloudObject,  :compute_connection
   obj_needs   :CloudObject,  :flavor,             { :for => [:create_e] }
   obj_needs   :CloudObject,  :network,            { :for => [:create_e] }
   obj_needs   :CloudObject,  :security_groups,    { :for => [:create_e] }
   obj_needs   :CloudObject,  :keypairs,           { :for => [:create_e] }
   obj_needs   :CloudObject,  :image,              { :for => [:create_e] }
   obj_needs   :data,         :server_name,        { :for => [:create_e] }

   obj_needs_optional
   obj_needs   :data,         :user_data,          { :for => [:create_e] }
   obj_needs   :data,         :meta_data,          { :for => [:create_e] }

   # internet server is a server connected to the internet network.
   define_obj(:internet_server,    :nohandler => true )

   obj_needs   :CloudObject,  :internet_network
   obj_needs   :CloudObject,  :server

end
