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

# Defines how to manage Maestro and forges
# create a maestro box. Identify a forge instance, delete it,...

# Define framework object on BaseDefinition
# See lib/core/definition.rb for function details usage.
class Lorj::BaseDefinition # rubocop: disable Style/ClassAndModuleChildren
  process_default :use_controller => false

  # ******************* Maestro Repository object
  define_obj :maestro_repository,

             :create_e => :clone_or_use_maestro_repo

  obj_needs :data,   :maestro_url

  obj_needs_optional
  obj_needs :data,   :maestro_repo

  # ******************* Infra Repository object
  define_obj :infra_repository,

             :create_e => :create_or_use_infra

  obj_needs :CloudObject,  :maestro_repository
  obj_needs :data,         :infra_repo
  obj_needs :data,         :branch

  # ******************* Lorj_cloud account
  define_obj :lorj_account,
             :create_e => :build_lorj_account

  obj_needs :data, 'maestro#lorj_disabled'

  # ******************* metadata object
  define_obj :metadata,
             :create_e => :build_metadata

  obj_needs :data,   :instance_name
  obj_needs :data,   'maestro#network_name'
  obj_needs :data,   'maestro#security_group'
  obj_needs :data,   'credentials#keypair_name'
  obj_needs :data,   'maestro#image_name'
  obj_needs :data,   'maestro#bp_flavor'
  obj_needs :data,   'services#compute'
  obj_needs :data,   'maestro#branch'
  obj_needs :data,   'dns#domain_name'
  obj_needs :data,   'maestro#tenant_name'
  # sent in base64
  obj_needs :data,   'gardener#os_user'
  obj_needs :data,   'gardener#os_enckey'
  obj_needs :data,   'gardener#os_auth_uri'
  obj_needs :data,   'credentials#account_id'
  obj_needs :data,   'credentials#account_key'
  obj_needs :data,   'credentials#auth_uri'
  obj_needs :data,   :server_name
  obj_needs :CloudObject, :lorj_account
  obj_needs_optional

  obj_needs :data,   'network#webproxy'
  # If requested by user, ask Maestro to manage the DNS.
  obj_needs :data,   'dns#dns_service'
  obj_needs :data,   'dns#dns_tenant_id'
  obj_needs :data,   :test_box
  obj_needs :data,   :test_box_path
  obj_needs :data,   'certs#ca_root_cert'

  # If requested by user, ask Maestro to instantiate a blueprint.
  obj_needs :data,   :blueprint
  # Add init bootstrap additional steps
  obj_needs :data,   :bootstrap
  # Add init additional git clone steps.
  obj_needs :data,   :repos
  # Add extra metadata
  obj_needs :data,   :extra_metadata

  # ******************* userdata object
  define_obj :userdata,

             :create_e => :build_userdata

  obj_needs :CloudObject,  :maestro_repository
  obj_needs :CloudObject,  :metadata
  obj_needs :CloudObject,  :infra_repository

  # ******************* forge object
  define_obj :forge,
             :create_e => :build_forge,
             :delete_e => :delete_forge,
             :get_e => :get_forge

  obj_needs :CloudObject, :compute_connection
  obj_needs :CloudObject, :metadata,                :for => [:create_e]
  obj_needs :CloudObject, :userdata,                :for => [:create_e]
  obj_needs :data,        :instance_name,           :for => [:create_e]
  obj_needs :data,        'maestro#image_name',     :for => [:create_e]
  obj_needs :data,        'maestro#flavor_name',    :for => [:create_e]
  obj_needs :data,        'maestro#network_name',   :for => [:create_e]
  obj_needs :data,        'maestro#security_group', :for => [:create_e]
  obj_needs :data,        :ports,                   :for => [:create_e]
  obj_needs :CloudObject, :lorj_account,            :for => [:create_e]

  obj_needs_optional
  obj_needs :CloudObject,  :server
  obj_needs :CloudObject,  :image,            :for => [:create_e]
  obj_needs :CloudObject,  :public_ip,        :for => [:create_e]
  obj_needs :CloudObject,  :keypairs,         :for => [:create_e]
  obj_needs :data,         :blueprint
  obj_needs :data,         :forge_server,     :for => [:delete_e]

  # Adding support of test-box script
  obj_needs :data,        :test_box,          :for => [:create_e]
  obj_needs :data,        :test_box_path,     :for => [:create_e]

  # Adding support of ca-root-cert file to send out.
  obj_needs :data,      'certs#ca_root_cert', :for => [:create_e]

  # Lorj_disabled support
  obj_needs :data,   'maestro#lorj_disabled', :for => [:create_e]

  # Defines how cli will control FORJ features
  # boot/down/ssh/...

  # Define framework object on BaseDefinition
  # See lib/core/definition.rb for function details usage.
  # ************************************ SSH Object
  define_obj(:ssh,

             :create_e => :ssh_connection
            )
  obj_needs :data,  :server

  obj_needs_optional
  obj_needs :data,         :ssh_user
end
