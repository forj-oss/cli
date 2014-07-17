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

require_relative '../lib/connection.rb'
include Connection

class TestClass
end

describe 'network' do
  it 'is connecting to hpcloud' do
    @test_class = TestClass.new
    @test_class.extend(Connection)

    Fog.mock!

    conn = @test_class.network
    expect(conn).to be

    Fog::Mock.reset
  end
end


describe 'compute' do
  it 'is connecting to hpcloud' do
    @test_class = TestClass.new
    @test_class.extend(Connection)

    Fog.mock!

    conn = @test_class.compute
    expect(conn).to be

    Fog::Mock.reset
  end
end