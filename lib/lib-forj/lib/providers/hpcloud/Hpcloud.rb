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

require 'fog' # We use fog to access HPCloud

$HPCLOUD_PATH = File.expand_path(File.dirname(__FILE__))

require File.join($HPCLOUD_PATH, "compute.rb")
require File.join($HPCLOUD_PATH, "network.rb")
require File.join($HPCLOUD_PATH, "security_groups.rb")

# Defines Meta HPCloud object
class Hpcloud < BaseDefinition

   define_obj :services
   obj_needs   :data, :account_id,      :mapping => :hp_access_key
   obj_needs   :data, :account_key,     :mapping => :hp_secret_key
   obj_needs   :data, :auth_uri,        :mapping => :hp_auth_uri
   obj_needs   :data, :tenant,          :mapping => :hp_tenant_id
   obj_needs   :data, ":excon_opts/:connect_timeout", :default_value => 30
   obj_needs   :data, ":excon_opts/:read_timeout",    :default_value => 240
   obj_needs   :data, ":excon_opts/:write_timeout",   :default_value => 240

   # Defines Object structure and function stored on the Hpcloud class object.
   # Compute Object
   define_obj :compute_connection
   # Defines Data used by compute.

   obj_needs   :data, :account_id,  :mapping => :hp_access_key
   obj_needs   :data, :account_key, :mapping => :hp_secret_key
   obj_needs   :data, :auth_uri,    :mapping => :hp_auth_uri
   obj_needs   :data, :tenant,      :mapping => :hp_tenant_id
   obj_needs   :data, :compute,     :mapping => :hp_avl_zone

   define_obj  :network_connection
   obj_needs   :data, :account_id,  :mapping => :hp_access_key
   obj_needs   :data, :account_key, :mapping => :hp_secret_key
   obj_needs   :data, :auth_uri,    :mapping => :hp_auth_uri
   obj_needs   :data, :tenant,      :mapping => :hp_tenant_id
   obj_needs   :data, :network,     :mapping => :hp_avl_zone

   # Forj predefine following query mapping, used by ForjProcess
   # id => id, name => name
   # If we need to add another mapping, add
   # query_mapping :id => :MyID
   # If the query is not push through and Hash object, the Provider
   # will needs to create his own mapping function.
   define_obj  :network
   query_mapping :external, :router_external

   define_obj  :rule
   obj_needs   :data, :dir,        :mapping => :direction
   attr_value_mapping  :IN,  'ingress'
   attr_value_mapping  :OUT, 'egress'

   obj_needs   :data, :proto,      :mapping => :protocol
   obj_needs   :data, :port_min,   :mapping => :port_range_min
   obj_needs   :data, :port_max,   :mapping => :port_range_max
   obj_needs   :data, :addr_map,   :mapping => :remote_ip_prefix
   obj_needs   :data, :sg_id,      :mapping => :security_group_id

   get_attr_mapping :dir,      :direction
   get_attr_mapping :proto,    :protocol
   get_attr_mapping :port_min, :port_range_min
   get_attr_mapping :port_max, :port_range_max
   get_attr_mapping :addr_map, :remote_ip_prefix
   get_attr_mapping :sg_id,    :security_group_id

   define_obj :keypairs

   undefine_attribute :id    # Do not return any predefined ID

   # ************************************ Router Object
   define_obj  :router

   obj_needs_optional
   obj_needs   :data,   :router_name,           :mapping => :name
   # The FORJ gateway_network_id is extracted from Fog::HP::Network::Router[:external_gateway_info][:network_id]
   obj_needs   :data,   :external_gateway_id,   :mapping => [:external_gateway_info, 'network_id' ]

   get_attr_mapping :gateway_network_id, [:external_gateway_info, 'network_id']

   # ************************************ SERVER Object
   define_obj  :server
   get_attr_mapping :status, :state
   attr_value_mapping :create, "BUILD"
   attr_value_mapping :boot,   :boot
   attr_value_mapping :active, "ACTIVE"
   get_attr_mapping :image_id, :image_id
   get_attr_mapping :key_name, :key_name
   # ************************************ SERVER log Object
   define_obj  :server_log

   # Excon::Response object type
   get_attr_mapping :output,  "output"

   # ************************************* Public IP Object
   define_obj  :public_ip
   get_attr_mapping :server_id, :instance_id
   get_attr_mapping :public_ip, :ip

   # defines setup Cloud data (:account => true for setup)
   define_data(:account_id, {
      :account => true,
      :desc => 'HPCloud Access Key (From horizon, user drop down, manage keys)',
      :validate => /^[A-Z0-9]*$/
   })
   define_data(:account_key, {
      :account => true,
      :desc => 'HPCloud secret Key (From horizon, user drop down, manage keys)',
      :encrypted => false,
      :validate => /^.+/
   })
   define_data(:auth_uri, {
      :account => true,
      :desc => 'HPCloud Authentication service URL (default is HP Public cloud)',
      :validate => /^http(s)?:\/\/.*$/,
      :default_value => "https://region-a.geo-1.identity.hpcloudsvc.com:35357/v2.0/"
   })
   define_data(:tenant, {
      :account => true,
      :desc => 'HPCloud Tenant ID (from horizon, identity, projecs, Project ID)',
      :validate => /^[0-9]+$/
   })

   define_data(:compute, {
      :account => true,
      :desc => 'HPCloud Compute service zone (Ex: region-a.geo-1)',
      :depends_on => [:account_id, :account_key, :auth_uri,:tenant ],
      :list_values => {
         :query_type  => :controller_call,
         :object       => :services,
         :query_call   => :get_services,
         :query_params => { :list_services => [:Compute, :compute] },
         :validate     => :list_strict
      }
   })

   define_data(:network, {
      :account => true,
      :desc => 'HPCloud Network service zone (Ex: region-a.geo-1)',
      :depends_on => [:account_id, :account_key, :auth_uri,:tenant ],
      :list_values => {
         :query_type  => :controller_call,
         :object       => :services ,
         :query_call   => :get_services,
         :query_params => { :list_services => [:Networking, :network] },
         :validate     => :list_strict
      }
   })

   data_value_mapping 'xsmall', "standard.xsmall"
   data_value_mapping 'small',  "standard.small"
   data_value_mapping 'medium', "standard.medium"
   data_value_mapping 'large',  "standard.large"
   data_value_mapping 'xlarge', "standard.xlarge"


end

# Following class describe how FORJ should handle HP Cloud objects.
# Except Cloud connection, all HPCloud objects management are described/called in HP* modules.
class HpcloudController < BaseController

   def connect(sObjectType, hParams)
      case sObjectType
         when :services
            Fog::HP.authenticate_v2(hParams[:hdata], hParams[:excon_opts])
         when :compute_connection
            Fog::Compute.new(hParams[:hdata].merge({:provider => :hp,:version => 'v2'}))
         when :network_connection
            Fog::HP::Network.new(hParams[:hdata])
         else
            forjError "'%s' is not a valid object for 'connect'" % sObjectType
      end
   end

   def create(sObjectType, hParams)
      case sObjectType
         #when :ssh
            #required?(hParams, :compute_connection)
            #HPCompute.get_server(hParams[:compute_connection], sUniqId)
         when :public_ip
            required?(hParams, :compute_connection)
            required?(hParams, :server)
            HPCompute.server_assign_address(hParams[:compute_connection], hParams[:server])
         when :server
            required?(hParams, :compute_connection)
            required?(hParams, :image)
            required?(hParams, :network)
            required?(hParams, :flavor)
            required?(hParams, :keypairs)
            required?(hParams, :security_groups)
            required?(hParams, :server_name)
            HPCompute.create_server(
               hParams[:compute_connection],
               hParams[:server_name], hParams[:security_groups],
               hParams[:image],       hParams[:network],
               hParams[:flavor],      hParams[:keypairs],
               hParams[:user_data],   hParams[:meta_data]
            )
         when :image
            required?(hParams, :compute_connection)
            required?(hParams, :image_name)
            HPCompute.get_image(hParams[:compute_connection], hParams[:image_name])
         when :network
            required?(hParams, :network_connection)
            required?(hParams, :network_name)
            HPNetwork.create_network(hParams[:network_connection], hParams[:network_name])
         when :subnetwork
            required?(hParams, :network_connection)
            required?(hParams, :network)
            required?(hParams, :subnetwork_name)
            HPNetwork.create_subnetwork(hParams[:network_connection], hParams[:network], hParams[:subnetwork_name])
         when :security_groups
            required?(hParams, :network_connection)
            required?(hParams, :security_group)
            HPSecurityGroups.create_sg(hParams[:network_connection], hParams[:security_group], hParams[:sg_desc])
         when :keypairs
            required?(hParams, :compute_connection)
            required?(hParams, :keypair_name)
            required?(hParams, :public_key)
            HPKeyPairs.create_keypair(hParams[:compute_connection], hParams[:keypair_name], hParams[:public_key])
         when :router
            required?(hParams, :network_connection)
            required?(hParams, :router_name)
            #~ if hParams[:external_gateway_id]
               #~ hParams[:hdata][:external_gateway_info] = { 'network_id' => hParams[:external_gateway_id] }
            #~ end
            hParams[:hdata] = hParams[:hdata].merge(:admin_state_up => true) # Forcelly used admin_status_up to true.

            HPNetwork.create_router(hParams[:network_connection], hParams[:hdata])
         when :rule
            required?(hParams, :network_connection)
            required?(hParams, :security_groups)
            HPSecurityGroups.create_rule(hParams[:network_connection], hParams[:hdata])
         when :router_interface
            required?(hParams, :router)
            required?(hParams, :subnetwork)
            HPNetwork.add_interface(hParams[:router], hParams[:subnetwork])
         else
            forjError "'%s' is not a valid object for 'create'" % sObjectType
      end
   end

   # This function return a collection which have to provide:
   # functions: [], length, each
   # Used by network process.
   def query(sObjectType, sQuery, hParams)
      case sObjectType
         #when :ssh
            #required?(hParams, :compute_connection)
            #HPCompute.query_server(hParams[:compute_connection], sQuery)
         when :public_ip
            required?(hParams, :compute_connection)
            HPCompute.query_server_assigned_addresses(hParams[:compute_connection], sQuery)
         when :server
            required?(hParams, :compute_connection)
            HPCompute.query_server(hParams[:compute_connection], sQuery)
         when :image
            required?(hParams, :compute_connection)
            HPCompute.query_image(hParams[:compute_connection], sQuery)
         when :network
            required?(hParams, :network_connection)
            HPNetwork.query_network(hParams[:network_connection], sQuery)
         when :subnetwork
            required?(hParams, :network_connection)
            HPNetwork.query_subnetwork(hParams[:network_connection], sQuery)
         when :router
            required?(hParams, :network_connection)
            HPNetwork.query_router(hParams[:network_connection], sQuery)
         when :port
            required?(hParams, :network_connection)
            HPNetwork.query_port(hParams[:network_connection], sQuery)
         when :security_groups
            required?(hParams, :network_connection)
            HPSecurityGroups.query_sg(hParams[:network_connection], sQuery)
         when :rule
            required?(hParams, :network_connection)
            HPSecurityGroups.query_rule(hParams[:network_connection], sQuery)
         when :keypairs
            required?(hParams, :compute_connection)
            HPKeyPairs.query_keypair(hParams[:compute_connection], sQuery)
         when :flavor
            required?(hParams, :compute_connection)
            HPCompute.query_flavor(hParams[:compute_connection], sQuery)
         else
            forjError "'%s' is not a valid object for 'query'" % sObjectType
      end
   end

   def delete(sObjectType, hParams)
      case sObjectType
         when :network
            HPNetwork.delete_network(hParams[:network_connection], hParams[:network])
         when :rule
            HPSecurityGroups.delete_rule(hParams[:network_connection], hParams[:id])
            hParams[:network_connection].security_group_rules.get(hParams[:id]).destroy
        when :server
            required?(hParams, :compute_connection)
            required?(hParams, :server)
            HPCompute.delete_server(hParams[:compute_connection], hParams[:server] )
        else
            nil
      end
   end

   def get(sObjectType, sUniqId, hParams)
      case sObjectType
        #when :ssh
            #required?(hParams, :compute_connection)
            #HPCompute.get_server(hParams[:compute_connection], sUniqId)
        when :server_log
            required?(hParams, :server)
            hParams[:server].console_output(sUniqId)
        when :server
            required?(hParams, :compute_connection)
            HPCompute.get_server(hParams[:compute_connection], sUniqId)
        when :image
            required?(hParams, :compute_connection)
            HPCompute.get_image(hParams[:compute_connection], sUniqId)
        when :network
            required?(hParams, :network_connection)
            HPNetwork.get_network(hParams[:network_connection], sUniqId)
        when :keypairs
            required?(hParams, :compute_connection)
            HPKeyPairs.get_keypair(hParams[:compute_connection], sUniqId)
        else
            forjError "'%s' is not a valid object for 'get'" % sObjectType
      end
   end

   def query_each(oFogObject)
      case oFogObject.class.to_s
         when "Fog::HP::Network::Networks"
            oFogObject.each { | value |
               yield(value)
            }
         else
            forjError "'%s' is not a valid list for 'each'" % oFogObject.class
      end
   end

   def get_attr(oControlerObject, key)
      begin
         if oControlerObject.is_a?(Excon::Response)
            rhGet(oControlerObject.data, :body, key)
         else
            attributes = oControlerObject.attributes
            raise "attribute '%s' is unknown in '%s'. Valid one are : '%s'" % [key[0], oControlerObject.class, oControlerObject.class.attributes ] unless oControlerObject.class.attributes.include?(key[0])
            rhGet(attributes, key)
         end
      rescue => e
         forjError "Unable to map '%s'. %s" % [key, e.message]
      end
   end

   def set_attr(oControlerObject, key, value)
      begin
         raise "No set feature for '%s'" % oControlerObject.class if oControlerObject.is_a?(Excon::Response)
         attributes = oControlerObject.attributes
         raise "attribute '%s' is unknown in '%s'. Valid one are : '%s'" % [key[0], oControlerObject.class, oControlerObject.class.attributes ] unless oControlerObject.class.attributes.include?(key[0])
         rhSet(attributes, value, key)
      rescue => e
         forjError "Unable to map '%s' on '%s'" % [key, sObjectType]
      end
   end


   def update(sObjectType, oObject, hParams)
      case sObjectType
         when :router
            forjError "Object to update is nil" if oObject.nil?

            HPNetwork.update_router(oObject[:object])
         else
            forjError "'%s' is not a valid list for 'update'" % oFogObject.class
      end
   end

   # This function requires to return an Array of values or nil.
   def get_services(sObjectType, oParams)
      case sObjectType
         when :services
            # oParams[sObjectType] will provide the controller object.
            # This one can be interpreted only by controller code,
            # except if controller declares how to map with this object.
            # Processes can deal only process mapped data.
            # Currently there is no services process function. No need to map.
            hServices = oParams[:services]
            if not oParams[:list_services].is_a?(Array)
               hServiceToFind = [oParams[:list_services]]
            else
               hServiceToFind = oParams[:list_services]
            end
            # Search for service. Ex: Can be :Networking or network. I currently do not know why...
            hSearchServices= rhGet(hServices, :service_catalog)
            sService = nil
            hServiceToFind.each { | sServiceElem |
               if hSearchServices.key?(sServiceElem)
                  sService = sServiceElem
                  break
               end
            }

            forjError "Unable to find services %s" % hServiceToFind if sService.nil?
            result = rhGet(hServices, :service_catalog, sService).keys
            result.delete("name")
            result.each_index { | iIndex |
               result[iIndex] = result[iIndex].to_s if result[iIndex].is_a?(Symbol)
            }
            return result
         else
            forjError "'%s' is not a valid object for 'get_services'" % sObjectType
      end
   end
end
