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
require 'log.rb' # Load default loggers

include Logging

$FORJ_LOGGER=ForjLog.new('forj-rspec.log', Logger::FATAL)

describe "class: forj-config" do
    context "when creating a new instance" do

      it 'should be loaded' do
         @test_config=ForjConfig.new()
         expect(@test_config).to be
      end

    end

    context "when starting, forj-config" do
      before(:all) do
         @config=ForjConfig.new()
      end
      
      it 'should be able to create a key/value in local config' do
         @config.LocalSet('test1','value')
         expect(@config.yConfig['default']['test1']).to eq('value')
      end

      it 'should be able to remove the previously created key/value from local config' do
         @config.LocalDel('test1')
         expect(@config.yConfig['default'].key?('test1')).to equal(false)
      end
    end   

    
    context "while updating local config file, forj-config" do
      before(:all) do
         @config=ForjConfig.new() 
      end
      
      after(:all)  do
        @config.LocalDel('test1')
        @config.SaveConfig()
      end  

      it 'should save a key/value in local config' do
         @config.LocalSet('test1','value')
         expect(@config.SaveConfig()).to equal(true)
      end
      
      it 'should get the saved value from local config' do
         oConfig=ForjConfig.new()
         expect(@config.yConfig['default']['test1']).to eq('value')
      end
  
    end

    context "With another config file - test1.yaml, forj-config" do

      before(:all) do
        if File.exists?('~/.forj/test.yaml')
           File.delete(File.expand_path('~/.forj/test.yaml'))
        end
        File.open(File.expand_path('~/.forj/test1.yaml'), 'w+') { |file| file.write("default:\n") }
        @config=ForjConfig.new('test.yaml')
        @config2=ForjConfig.new('test1.yaml')
      end
      
      after(:all)  do
        File.delete(File.expand_path('~/.forj/test1.yaml'))
      end  

      it 'won\'t create a new file If we request to load \'test.yaml\'' do
         expect(File.exists?(File.expand_path('~/.forj/test.yaml'))).to equal(false)
      end
      
      it 'will load the default config file if we request to load \'test.yaml\'' do
         expect(File.basename(@config.sConfigName)).to eq('config.yaml')
      end

      it 'will confirm \'test1.yaml\' config to be loaded.' do
         expect(File.basename(@config2.sConfigName)).to eq('test1.yaml')
      end

      it 'can save \'test2=value\'' do
         @config2.LocalSet('test2','value')
         expect(@config2.SaveConfig()).to equal(true)
         config3=ForjConfig.new('test1.yaml')
         expect(config3.yConfig['default']['test2']).to eq('value')
      end

  
    end

end
