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

require 'ansi'
require 'fog'

$APP_PATH = File.dirname(__FILE__)
$LIB_PATH = File.expand_path(File.join(File.dirname($APP_PATH),'lib'))
$FORJ_DATA_PATH= File.expand_path('~/.forj')

$LOAD_PATH << './lib'

require 'forj-config.rb' # Load class ForjConfig
require 'log.rb' # Load default loggers
include Logging
$FORJ_LOGGER=ForjLog.new('forj-rspec.log', Logger::FATAL)

require_relative '../lib/repositories.rb'
include Repositories

class TestClass
end

describe 'repositories' do
  it 'should clone the repo' do
    @test_class = TestClass.new
    @test_class.extend(Repositories)
    oConfig = ForjConfig.new
    repo = @test_class.clone_repo('https://github.com/forj-oss/cli', oConfig)
    expect(repo).to be
  end
end
