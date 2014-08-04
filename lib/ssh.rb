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
require 'require_relative'

require_relative 'log.rb'
include Logging

#
# ssh module
#
module Ssh
  def connect(name, server)
    msg = 'logging into %s : %s' % [name, server]
    Logging.info(msg)
    current_dir = Dir.pwd
    Dir.chdir(current_dir + '/lib')

    update = './ssh.sh -u'
    connection = './ssh.sh %s %s' % [name, server]

    # update the list of servers
    Kernel.system(update)

    # connect to the server
    Kernel.system(connection)
  end
end