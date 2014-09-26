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

raise "$LIB_PATH is missing. Please set it." if not $LIB_PATH

$PROVIDERS_PATH = File.expand_path(File.join($LIB_PATH, "forj-cloud", "providers"))
$CORE_PROCESS_PATH = File.join($LIB_PATH, "forj-cloud", "core_process")

require 'forj-config.rb'   # Load class ForjConfig
require 'forj-account.rb'  # Load class ForjAccount

require File.join($LIB_PATH, "forj-cloud", "core.rb")
