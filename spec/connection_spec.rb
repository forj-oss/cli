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
require 'spec_helper'

require 'fog'

$APP_PATH = File.dirname(__FILE__)
$LIB_PATH = File.expand_path(File.join(File.dirname($APP_PATH),'lib'))

$LOAD_PATH << $LIB_PATH

require 'appinit.rb' # Load generic Application level function

# Initialize forj paths
AppInit::forj_initialize()

# Initialize global Log object
$FORJ_LOGGER=ForjLog.new('forj-rspec.log', Logger::FATAL)

require 'forj-config.rb' # Load class ForjConfig
require 'connection.rb' # Load class ForjConnection
require 'forj-account.rb'


describe 'Module: forj-connection' do

  it 'should connect to hpcloud (smoke test)' do

    Fog.mock!
    conn = ForjConnection.new(ForjConfig.new())
    expect(conn).to be

    Fog::Mock.reset
  end
end
