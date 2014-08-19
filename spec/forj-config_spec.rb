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

class TestClass
end

require_relative '../lib/forj-config.rb'
$APP_PATH = File.dirname(__FILE__)
$LIB_PATH = File.expand_path(File.join(File.dirname($APP_PATH),'lib'))
$FORJ_DATA_PATH= File.expand_path('~/.forj')

describe 'forj cli' do
  describe ".forj-config" do
    context "new instance" do

      it 'should be loaded' do
         @test_config=ForjConfig.new()
         expect(@test_config).to be
      end

    end

    context "Config in memory" do
      before(:all) do
         @config=ForjConfig.new()
      end
      
      it 'should be able to create a key/value in local config' do
         @config.ConfigSet('test1','value')
         @config.yConfig['default']['test1'].should == 'value'
      end

      it 'should be able to remove the previously created key/value from local config' do
         @config.ConfigDel('test1')
         @config.yConfig['default'].key?('test1').should == false
      end
    end   

    
    context "Updating local config file" do
      before(:all) do
         @config=ForjConfig.new() 
      end
      
      after(:all)  do
        @config.ConfigDel('test1')
        @config.SaveConfig()
      end  

      it 'should save a key/value in local config' do
         @config.ConfigSet('test1','value')
         @config.SaveConfig().should == true
      end
      
      it 'should get the saved value from local config' do
         oConfig=ForjConfig.new()
         @config.yConfig['default']['test1'].should == 'value'
      end
  
    end

    context "Updating another config file from .forj" do

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

      it 'If file do not exist, warning! and file is not created.' do
         File.exists?(File.expand_path('~/.forj/test.yaml')).should == false
      end
      
      it 'Then, default config is loaded.' do
         File.basename(@config.sConfigName).should == 'config.yaml'
      end

      it 'test1.yaml config is loaded.' do
         File.basename(@config2.sConfigName).should == 'test1.yaml'
      end

      it 'should save a key/value in test2 config' do
         @config2.ConfigSet('test2','value')
         @config2.SaveConfig().should == true
      end

  
    end
  end

end
