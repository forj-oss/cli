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

require 'rubygems'

require 'security.rb'
include SecurityGroup
#
# ssh module
#
module Ssh
   def connect(name, server, oConfig)
      # Following line to remove as soon as ssh function is implemented with forj-lib framework
      Logging.warning("This function may not work appropriately. Currenty under development. Thank you for your understanding.")

      msg = 'logging into %s : %s' % [name, server]
      Logging.info(msg)

      oForjAccount = ForjAccount.new(oConfig)

      oForjAccount.ac_load()

      oKey = SecurityGroup.keypair_detect(oForjAccount.get(:keypair_name), oForjAccount.get(:keypair_path))

      update = '%s/ssh.sh -u %s' % [ $LIB_PATH, oConfig.get(:account_name)]
      connection = '%s/ssh.sh %s %s %s' % [$LIB_PATH, name, server, File.join(oKey[:keypair_path],oKey[:private_key_name]) ]

      # update the list of servers
      Logging.debug("Executing '%s'" % update)
      Kernel.system(update)

      # connect to the server
      Logging.debug("Executing '%s'" % connection)
      Kernel.system(connection)
   end
end
