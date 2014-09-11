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

$APP_PATH = File.dirname(__FILE__)
$LIB_PATH = File.expand_path(File.join(File.dirname($APP_PATH),'lib'))
$FORJ_DATA_PATH= File.expand_path('~/.forj')

$LOAD_PATH << './lib'

require 'forj-config.rb' # Load class ForjConfig
require 'forj-account.rb' # Load class ForjAccount
require 'log.rb' # Load default loggers
require 'ansi'

include Logging

$FORJ_LOGGER=ForjLog.new('forj-rspec.log', Logger::FATAL)

# Initialize forj paths
ensure_forj_dirs_exists()

describe "class: forj-account," do
    context "when creating a new instance" do

      it 'should be loaded' do
         oConfig=ForjConfig.new()
         oForjAccount = ForjAccount.new(oConfig)
         expect(oForjAccount).to be
      end

    end

    context "when starting" do
      before(:all) do
         File.open(File.expand_path('~/.forj/test1.yaml'), 'w+') { |file| file.write("default:\n  keypair_name: nova_local\n") }
         File.open(File.expand_path('~/.forj/accounts/test1'), 'w+') { |file| file.write("credentials:\n  keypair_name: nova_test1\n  :tenant_name: test\n") }

         config=ForjConfig.new('test1.yaml')
         config.set(:account_name, 'test1')
         @ForjAccount = ForjAccount.new(config)
         @ForjAccount.ac_load()
      end
      
      after(:all)  do
        File.delete(File.expand_path('~/.forj/test1.yaml'))
        File.delete(File.expand_path('~/.forj/accounts/test1'))
      end

      it 'should be able to read account data' do
         expect(@ForjAccount.get(:keypair_name)).to eq('nova_test1')
      end

      it 'should be able to create a key/value in the account config' do
         @ForjAccount.set(:test1, 'value')
         expect(@ForjAccount.get(:test1)).to equal(nil)
         @ForjAccount.set(:keypair_name, 'value')
         expect(@ForjAccount.get(:keypair_name)).to eq('value')
      end

      it 'should be able to delete a key/value in the account config and get default back.' do
         @ForjAccount.del(:keypair_name)
         expect(@ForjAccount.get(:keypair_name)).to eq('nova_local')
      end

   end
end
