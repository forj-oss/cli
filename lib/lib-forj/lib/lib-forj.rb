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


# This is the ForjCloud base library.

# To use it, add require 'forj-cloud.rb'

slib_forj = File.dirname(__FILE__)
$FORJ_LIB = File.expand_path(File.join(File.dirname(slib_forj),'lib'))


raise "$FORJ_LIB is missing. Please set it." if not $FORJ_LIB

$PROVIDERS_PATH = File.expand_path(File.join($FORJ_LIB,  "providers"))
$CORE_PROCESS_PATH = File.join($FORJ_LIB, "core_process")

require 'forj-config.rb'   # Load class ForjConfig
require 'forj-account.rb'  # Load class ForjAccount

require File.join($FORJ_LIB, "core", "core.rb")
require File.join($FORJ_LIB, "core", "definition.rb")
require File.join($FORJ_LIB, "core", "definition_internal.rb")
