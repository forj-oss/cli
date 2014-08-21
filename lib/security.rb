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

#
# SecurityGroup module
#
module SecurityGroup

  def get_or_create_security_group(oFC, name)
    Logging.debug('getting or creating security group for %s' % [name])
    security_group = get_security_group(oFC, name)
    if security_group == nil
      security_group = create_security_group(oFC, name)
    else
      Logging.debug('Security Group %s found.' % [name])
    end
    security_group
    
  end

  def create_security_group(oFC, name)
    sec_group = nil
    begin
      sec_groups = get_security_group(oFC, name)
      if sec_groups.length >= 1
        sec_group = sec_groups[0]
      else
        description = 'Security group for blueprint %s' % [name]
        Logging.info(description)
        sec_group = oFC.oNetwork.security_groups.create(
            :name => name,
            :description => description
        )
      end
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
    sec_group
  end

  def get_security_group(oFC, name)
    oSSLError=SSLErrorMgt.new
    begin
      oFC.oNetwork.security_groups.all({:name => name})[0]
    rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
    end
  end

  def delete_security_group(oFC, security_group)
    oSSLError=SSLErrorMgt.new
    begin
      sec_group = get_security_group(oFC, security_group)
      oFC.oNetwork.security_groups.get(sec_group.id).destroy
    rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
    end
  end

  def create_security_group_rule(oFC, security_group_id, protocol, port_min, port_max)
    oSSLError=SSLErrorMgt.new
    begin
      oFC.oNetwork.security_group_rules.create(
          :security_group_id => security_group_id,
          :direction => 'ingress',
          :protocol => protocol,
          :port_range_min => port_min,
          :port_range_max => port_max,
          :remote_ip_prefix => '0.0.0.0/0'
      )
    rescue StandardError => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
      msg = 'error creating the rule for port %s' % [port_min]
      Logging.error msg
    end
  end

  def delete_security_group_rule(oFC, rule_id)
    oSSLError=SSLErrorMgt.new
    begin
      oFC.oNetwork.security_group_rules.get(rule_id).destroy
    rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
    end
  end

  def get_security_group_rule(oFC, port)
    oSSLError=SSLErrorMgt.new
    begin
      oFC.oNetwork.security_group_rules.all({:port_range_min => port, :port_range_max => port})[0]
    rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
    end
  end

  def get_or_create_rule(oFC, security_group_id, protocol, port_min, port_max)
    Logging.debug('getting or creating rule %s' % [port_min])
    rule = get_security_group_rule(oFC, port_min)
    if rule == nil
      rule = create_security_group_rule(oFC, security_group_id, protocol, port_min, port_max)
    end
    rule
  end

  def upload_existing_key(key_name, key_path)
    command = 'hpcloud keypairs:import %s %s' % [key_name, key_path]
    Kernel.system(command)
  end
end
