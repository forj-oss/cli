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

FORJCORE_PATH = File.expand_path(File.dirname(__FILE__))

require File.join(FORJCORE_PATH, 'process', 'ForjProcess.rb')

# Defines how to manage Maestro and forges
# create a maestro box. Identify a forge instance, delete it,...

# Define framework object on BaseDefinition
# See lib/core/definition.rb for function details usage.
class Lorj::BaseDefinition
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

  # ******************* metadata object
  define_obj :metadata,

             :create_e => :build_metadata

  obj_needs :data,   :instance_name
  obj_needs :data,   :network_name
  obj_needs :data,   :security_group
  obj_needs :data,   :keypair_name
  obj_needs :data,   :image_name
  obj_needs :data,   :bp_flavor
  obj_needs :data,   :compute
  obj_needs :data,   :branch
  obj_needs :data,   :domain_name
  obj_needs :data,   :tenant_name
  # sent in base64
  obj_needs :data,   :os_user
  obj_needs :data,   :os_enckey
  obj_needs :data,   :account_id
  obj_needs :data,   :account_key
  obj_needs_optional

  # If requested by user, ask Maestro to manage the DNS.
  obj_needs :data,   :dns_service
  obj_needs :data,   :dns_tenant_id

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

  obj_needs :CloudObject,  :compute_connection
  obj_needs :CloudObject,  :metadata,         :for => [:create_e]
  obj_needs :CloudObject,  :userdata,         :for => [:create_e]
  obj_needs :data,         :instance_name,    :for => [:create_e]

  obj_needs_optional
  obj_needs :CloudObject,  :server
  obj_needs :data,         :blueprint
end
