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
    Logging.state("Searching for security group '%s'..." % [name])
    security_group = get_security_group(oFC, name)
    security_group = create_security_group(oFC, name) if not security_group
    security_group
  end

  def create_security_group(oFC, name)
    Logging.debug("creating security group '%s'" % [name])
    begin
      description = "Security group for blueprint '%s'" % [name]
      oFC.oNetwork.security_groups.create(
            :name => name,
            :description => description
        )
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  def get_security_group(oFC, name)
    Logging.state("Searching for security group '%s'" % [name])
    oSSLError=SSLErrorMgt.new
    begin
      sgroups = oFC.oNetwork.security_groups.all({:name => name})
    rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
    end
    case sgroups.length()
      when 0
        Logging.debug("No security group '%s' found" % [name] )
        nil
      when 1
        Logging.debug("Found security group '%s'" % [sgroups[0].name])
        sgroups[0]  
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
    Logging.debug("Creating ingress rule '%s:%s - %s to 0.0.0.0/0'" % [protocol, port_min, port_max])
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

  def get_security_group_rule(oFC, security_group_id, port_min, port_max)
    Logging.state("Searching for rule '%s - %s'" % [ port_min, port_max])
    oSSLError = SSLErrorMgt.new
    begin
      sgroups = oFC.oNetwork.security_group_rules.all({:port_range_min => port_min, :port_range_max => port_max, :security_group_id => security_group_id})
      case sgroups.length()
        when 0
          Logging.debug("No security rule '%s - %s' found" % [ port_min, port_max ] )
          nil
        else
          Logging.debug("Found security rule '%s - %s'." % [ port_min, port_max ])
          sgroups
      end      
   rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
    end
  end

  def get_or_create_rule(oFC, security_group_id, protocol, port_min, port_max)
    rule = get_security_group_rule(oFC, security_group_id, port_min, port_max)
    if not rule
      rule = create_security_group_rule(oFC, security_group_id, protocol, port_min, port_max)
    end
    rule
  end

  def upload_existing_key(key_name, key_path)
    command = 'hpcloud keypairs:import %s %s' % [key_name, key_path]
    Kernel.system(command)
  end
end
