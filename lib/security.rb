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
require 'highline/import'

#
# SecurityGroup module
#

# TODO: Introduce most of HPCloud task in an hpcloud object.
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

  def keypair_detect(keypair_name, key_fullpath)
      # Build key data information structure.
      # Take care of priv with or without .pem and pubkey with pub.
	
      key_basename = File.basename(key_fullpath)
      key_path = File.expand_path(File.dirname(key_fullpath))
    
      mObj = key_basename.match(/^(.*?)(\.pem|\.pub)?$/)
      key_basename = mObj[1]
    
      private_key_ext = nil
      private_key_ext = "" if File.exists?(File.join(key_path, key_basename))
      private_key_ext = '.pem' if File.exists?(File.join(key_path, key_basename + '.pem'))
      if private_key_ext
         private_key_exist = true
         private_key_name = key_basename + private_key_ext
      else
         private_key_exist = false
         private_key_name = key_basename
      end
    
      public_key_exist = File.exists?(File.join(key_path, key_basename + '.pub'))
      public_key_name = key_basename + '.pub'
    
    
      result = {:keypair_name     => keypair_name,
                :keypair_path     => key_path,         :key_basename       => key_basename,
                :private_key_name => private_key_name, :private_key_exist? => private_key_exist,
                :public_key_name  => public_key_name,  :public_key_exist?  => public_key_exist,
               }
   end

  def hpc_import_key(oForjAccount)

    keys = keypair_detect(oForjAccount.get(:credentials, 'keypair_name'), oForjAccount.get(:credentials, 'keypair_path'))
    account = oForjAccount.get(:account, :name)

    Logging.fatal(1, "'keypair_path' undefined. check your config.yaml file.") if not keys[:keypair_path]
    Logging.fatal(1, "'keypair_name' undefined. check your config.yaml file.") if not keys[:keypair_name]
    Logging.fatal(1, "keypair '%s' are missing. Please call 'forj setup %s' to create the missing key pair required." % [keys[:keypair_name], account]) if not keys[:public_key_exist?]
    
    public_key_path = File.join(keys[:keypair_path], keys[:public_key_name])
    private_key_path = File.join(keys[:keypair_path], keys[:private_key_name])

    if not File.exists?(File.join($HPC_KEYPAIRS, keys[:keypair_name] + '.pub'))
       Logging.info("Importing your forj public key '%s' to hpcloud." % keys[:public_key_name])
       command = 'hpcloud keypairs:import %s %s -a %s' % [keys[:keypair_name], public_key_path , account]
       Logging.debug("Executing command '%s'" % command)
       Kernel.system(command)
    else
       Logging.info("Using '%s' as public key." % public_key_path)
    end
    
    if not File.exists?(File.join($HPC_KEYPAIRS, keys[:keypair_name] + '.pem'))
       if keys[:private_key_exist?]
          Logging.info("Importing your forj private key '%s' to hpcloud." % private_key_path)
          command = 'hpcloud keypairs:private:add %s %s' % [keys[:keypair_name], private_key_path]
          Logging.debug("Executing command '%s'" % command)
          Kernel.system(command)
       else   
          Logging.warning('Unable to find the private key. This will be required to access with ssh to Maestro and any blueprint boxes.')
       end
    else
       Logging.info("Using '%s' as private key." % private_key_path)
    end
  end
end
