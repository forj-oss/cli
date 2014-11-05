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

# Defines how cli will control FORJ features
# boot/down/ssh/...

# Define framework object on BaseDefinition
# See lib/core/definition.rb for function details usage.

class ForjCliProcess
   def connect_to(sObjectType, hParams)
   end
end

class BaseDefinition
   # ************************************ SSH Object
   define_obj(:ssh,
      {
         :create_e      => :ssh_connection
      })
   obj_needs   :CloudObject,  :forge
   obj_needs   :data,         :instance_name
   obj_needs   :data,         :keypair_name
   obj_needs   :data,         :keypair_path

   obj_needs_optional
   obj_needs    :data,         :forge_server
   obj_needs    :data,         :ssh_user
end
