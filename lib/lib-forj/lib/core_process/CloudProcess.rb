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

   # All objects used by this process are built from a Controller
   process_default :use_controller => true

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

   undefine_attribute :id    # Do not return any predefined ID
   undefine_attribute :name  # Do not return any predefined NAME


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

   undefine_attribute :id    # Do not return any predefined ID
   undefine_attribute :name  # Do not return any predefined NAME

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

   undefine_attribute :id    # Do not return any predefined ID
   undefine_attribute :name  # Do not return any predefined NAME

   # ************************************ Network Object
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

   # ************************************ SubNetwork Object
   # Identify subnetwork as part of network.
   define_obj(:subnetwork,
              :create_e    => :forj_get_or_create_subnetwork
             )

   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :network
   obj_needs   :data,         :subnetwork_name

   def_query_attribute :network_id

   # ************************************ Port Object
   # Identify port attached to network
   define_obj  :port,   :nohandler => true

   obj_needs   :CloudObject,  :network_connection
   def_attribute :device_id

   def_query_attribute :network_id
   def_query_attribute :device_owner


   # ************************************ Router Object
   # Identify the router of a network.
   define_obj(:router,
      {
         :create_e   => :forj_get_or_create_router,
#         :query_e    => :forj_query_router,
#         :get_e      => :forj_get_router,
         :update_e   => :forj_update_router
#         :delete_e   => :forj_delete_router
      })
   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :network,            { :for => [:create_e] }
   obj_needs   :CloudObject,  :subnetwork,         { :for => [:create_e] }
   obj_needs_optional
   obj_needs   :data,         :router_name,        { :for => [:create_e] }

   def_attribute :gateway_network_id

   # ************************************ Router interface Object
   # Identify interface attached to a router
   # This object will probably be moved to controller task
   # To keep the network model more generic.

   # No process handler defined. Just Controller object
   define_obj  :router_interface,   :nohandler => true

   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :router,             { :for => [:create_e] }
   obj_needs   :CloudObject,  :subnetwork,         { :for => [:create_e] }

   undefine_attribute   :name
   undefine_attribute   :id

   # Identify an external network thanks to the network router.
   define_obj(:external_network,
      {
         :create_e   => :forj_get_or_create_ext_net,
         :query_e    => :forj_query_external_network
      })

   obj_needs   :CloudObject,  :network_connection
   obj_needs   :CloudObject,  :router


   # ************************************ Security groups Object
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

   # ************************************ Security group rules Object
   # Identify Rules attached to the security group
   define_obj(:rule,
      {
         :create_e   => :forj_get_or_create_rule,
         :query_e    => :forj_query_rule
#         :delete_e   => :forj_delete_rule
      })

   undefine_attribute :name  # Do not return any predefined name attribute

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

   # ************************************ keypairs Object
   # Identify keypairs
   define_obj(:keypairs,
      {
         :create_e   => :forj_get_or_create_keypair,
         :query_e    => :forj_query_keypair,
         :get_e      => :forj_get_keypair
#         :delete_e   => :forj_delete_keypair
      })

   obj_needs   :CloudObject,  :compute_connection
   obj_needs   :data,         :keypair_name,       { :for => [:create_e] }
   obj_needs   :data,         :keypair_path,       { :for => [:create_e] }

   obj_needs_optional
   obj_needs   :data,         :public_key,         { :for => [:create_e] }

   def_attribute :public_key

   # ************************************ Image Object
   # Identify image
   define_obj(:image,
      {
         :create_e   => :forj_get_or_create_image,
         :query_e    => :forj_query_image,
         :get_e      => :forj_get_image
#         :update_e   => :forj_update_image
#         :delete_e   => :forj_delete_image
      })

   obj_needs   :CloudObject,  :compute_connection
   obj_needs   :data,         :image_name,         { :for => [:create_e] }

   obj_needs_optional
   obj_needs   :data,         :image_id

   # ************************************ Flavor Object
   # Identify flavor
   define_obj(:flavor,
      {
         :create_e   => :forj_get_or_create_flavor,
         :query_e    => :forj_query_flavor
#         :get_e      => :forj_get_flavor,
#         :update_e   => :forj_update_flavor,
#         :delete_e   => :forj_delete_flavor
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

   # ************************************ Internet network Object
   # Define Internet network
   #
   # This object contains the logic to ensure the router's network has a gateway to the external network (internet)
   # is capable to connect to internet
   # And to create this connection if possible.

   define_obj(:internet_network,    :nohandler => true )

   obj_needs   :CloudObject,  :external_network # External network to connect if needed.

   # ************************************ SERVER Object
   # Identify the server to use/build on the network/...
   define_obj(:server,
      {
         :create_e   => :forj_get_or_create_server,
         :query_e    => :forj_query_server,
         :get_e      => :forj_get_server,
#         :update_e   => :forj_update_server,
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

   def_attribute  :status
   predefine_data_value :create,  { :desc => "Server is creating." }
   predefine_data_value :boot,    { :desc => "Server is booting." }
   predefine_data_value :active,  { :desc => "Server is started." }
   def_attribute  :private_ip_address
   def_attribute  :public_ip_address

   def_attribute  :image_id
   def_attribute  :key_name
   # ************************************ SERVER Addresses Object
   # Object representing the list of IP addresses attached to a server.
   define_obj(:public_ip,
      :create_e   => :forj_get_or_assign_public_address,
      :query_e    => :forj_query_public_address
#      :get_e      => :forj_get_address
#      :update_e   => :forj_update_address
#      :delete_e   => :forj_delete_address
   )

   obj_needs   :CloudObject,  :compute_connection
   obj_needs   :CloudObject,  :server

   def_attribute :server_id
   def_attribute :public_ip
   undefine_attribute :name # No name to extract

   # ************************************ SERVER Console Object
   # Object representing the console log attached to a server

   define_obj(:server_log,
      {
         :get_e      => :forj_get_server_log
      })

   obj_needs   :CloudObject,  :server
   obj_needs   :data,         :log_lines
   undefine_attribute  :name
   undefine_attribute  :id
   def_attribute  :output

   # ************************************ Internet SERVER Object
   # internet server is a server connected to the internet network.
   define_obj(:internet_server,    :nohandler => true )

   obj_needs   :CloudObject,  :internet_network
   obj_needs   :CloudObject,  :server
   obj_needs   :CloudObject,  :public_ip

end
