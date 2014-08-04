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

require_relative 'connection.rb'
include Connection
require_relative 'log.rb'
include Logging

#
# Network module
#
module Network
  def get_or_create_network(name)
    network = get_network(name)
    if network == nil
      network = create_network(name)
    end
    network
  end

  def get_network(name)
    begin
      info = 'getting network %s' % [name]
      Logging.info(info)
      Connection.network.networks.all(:name => name)[0]
    rescue => e
      puts e.message
      Logging.error(e.message)
    end
  end

  def create_network(name)
    begin
      info = 'creating network %s' % [name]
      Logging.info(info)
      Connection.network.networks.create(:name => name)
    rescue => e
      Logging.error(e.message)
    end
  end

  def delete_network(network_name)
    begin
      network = get_network(network_name)
      Connection.network.networks.get(network.id).destroy
    rescue => e
      Logging.error(e.message)
    end
  end

  def get_or_create_subnet(network_id, name)
    begin
      subnet = get_subnet(name)
      if subnet == nil
        subnet = create_subnet(network_id, name)
      end
      subnet
    rescue => e
      Logging.error(e.message)
    end
  end

  def create_subnet(network_id, name)
    begin
      Connection.network.subnets.create(
          :network_id => network_id,
          :name => name,
          :cidr => get_next_subnet,
          :ip_version => '4'
      )
    rescue => e
      Logging.error(e.message)
    end
  end

  def delete_subnet(subnet_id)
    begin
      Connection.network.subnets.get(subnet_id).destroy
    rescue => e
      Logging.error(e.message)
    end
  end

  def get_subnet(name)
    begin
      Connection.network.subnets.all(:name => name)[0]
    rescue => e
      Logging.error(e.message)
    end
  end

  def get_router(name)
    begin
      routers = Connection.network.routers.all({:name => name})
      router = nil

      routers.each do|r|
        router = r
      end

      router
    rescue => e
      Logging.error(e.message)
    end
  end

  def create_router_interface(subnet_id, router)
    begin
      router.add_interface(subnet_id, nil)
    rescue => e
      Logging.error(e.message)
    end
  end

  def delete_router_interface(subnet_id, router)
    begin
      router.remove_interface(subnet_id)
    rescue => e
      Logging.error(e.message)
    end
  end

  def create_router(name)
    begin
      Connection.network.routers.create(
          :name => name,
          :admin_state_up => true
      )
    rescue => e
      Logging.error(e.message)
    end
  end

  def delete_router(router_id)
    begin
      Connection.network.routers.get(router_id).destroy
    rescue => e
      Logging.error(e.message)
    end
  end
end


def get_next_subnet
  begin
    subnet_values = Array.new
    subnets = Connection.network.subnets.all

    subnets.each do|s|
      subnet_values.push(s.cidr)
    end

    gap = false
    count = 0
    range_used = Array.new
    new_subnet = 0
    new_cidr = ''

    subnet_values = subnet_values.sort!

    subnet_values.each do|value|
      range_used.push(value[5])
    end

    range_used.each do |n|
      if count.to_i == n.to_i
      else
        new_subnet = count
        gap = true
        break
      end
      count += 1
    end

    if gap
      new_cidr = '10.0.%s.0/24' % [count]
    else
      max_value = range_used.max
      new_subnet = max_value.to_i + 1
      new_cidr  = '10.0.%s.0/24' % [new_subnet]
    end
    new_cidr
  rescue => e
    Logging.error(e.message)
  end
end
