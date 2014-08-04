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
# SecurityGroup module
#
module SecurityGroup

  def get_or_create_security_group(name)
    Logging.info('getting or creating security group for %s' % [name])
    security_group = get_security_group(name)
    if security_group == nil
      security_group = create_security_group(name)
    end
    security_group
  end

  def create_security_group(name)
    sec_group = nil
    begin
      sec_groups = get_security_group(name)
      if sec_groups.length >= 1
        sec_group = sec_groups[0]
      else
        description = 'Security group for blueprint %s' % [name]
        Logging.info(description)
        sec_group = Connection.network.security_groups.create(
            :name => name,
            :description => description
        )
      end
    rescue => e
      Logging.error(e.message)
    end
    sec_group
  end

  def get_security_group(name)
    begin
      Connection.network.security_groups.all({:name => name})[0]
    rescue => e
      Logging.error(e.message)
    end
  end

  def delete_security_group(security_group)
    begin
      sec_group = get_security_group(security_group)
      Connection.network.security_groups.get(sec_group.id).destroy
    rescue => e
      Logging.error(e.message)
    end
  end

  def create_security_group_rule(security_group_id, protocol, port_min, port_max)
    begin
      Connection.network.security_group_rules.create(
          :security_group_id => security_group_id,
          :direction => 'ingress',
          :protocol => protocol,
          :port_range_min => port_min,
          :port_range_max => port_max,
          :remote_ip_prefix => '0.0.0.0/0'
      )
    rescue StandardError => e
      msg = 'error creating the rule for port %s' % [port_min]
      puts msg
      Logging.error(e.message)
    end
  end

  def delete_security_group_rule(rule_id)
    begin
      Connection.network.security_group_rules.get(rule_id).destroy
    rescue => e
      Logging.error(e.message)
    end
  end

  def get_security_group_rule(port)
    begin
      Connection.network.security_group_rules.all({:port_range_min => port, :port_range_max => port})[0]
    rescue => e
      Logging.error(e.message)
    end
  end

  def get_or_create_rule(security_group_id, protocol, port_min, port_max)
    Logging.info('getting or creating rule %s' % [port_min])
    rule = get_security_group_rule(port_min)
    if rule == nil
      rule = create_security_group_rule(security_group_id, protocol, port_min, port_max)
    end
    rule
  end

  def upload_existing_key(key_name, key_path)
    command = 'hpcloud keypairs:import %s %s' % [key_name, key_path]
    Kernel.system(command)
  end
end
