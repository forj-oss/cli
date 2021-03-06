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

# Define model

lorj_objects = %w(forj_setup forj_setup_keypairs
                  ssh
                  forge_boot status test_box ca_root_cert proxy
                  forge_get forge_destroy
                  lorj_account maestro_repository infra_repository
                  metadata userdata
                  declare)

lorj_objects.each do |name|
  load File.join(FORJCORE_PATH, 'forj_core', 'process', name + '.rb')
end
