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


#
# Network module
#
module Network

  # Network management
  def get_or_create_network(oFC, name)
    Logging.state("Searching for network '%s'" % [name])
    network = get_network(oFC, name)
    if not network 
      network = create_network(oFC, name)
    end
    network
  end

  def get_network(oFC, name)
    begin
      networks = oFC.oNetwork.networks.all(:name => name)
      case networks.length()
        when 0
          Logging.debug("No network found")
          nil
        when 1
          Logging.debug("Found network '%s'" % [networks[0].name])
          networks[0]
        else  
          Logging.warning("Several network was found with '%s'. Selecting the first one '%s'." % [name, networks[0].name])
          networks[0]
        end
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  def create_network(oFC, name)
    begin
      Logging.debug('creating network %s' % [name])
      oFC.oNetwork.networks.create(:name => name)
    rescue => e
      Logging.fatal(1, "%s\n%s" % [e.inspect, e.message])
    end
  end

  def delete_network(oFC, network_name)
    begin
      network = get_network(oFC, network_name)
      oFC.oNetwork.networks.get(network.id).destroy
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end


  # Subnet management
  def get_or_create_subnet(oFC, network_id, name)
    Logging.state("Searching for sub-network attached '%s'." % [name])
    begin
      subnets = oFC.oNetwork.subnets.all(:network_id => network_id)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
    if subnets 
      case subnets.length()
        when 0
          Logging.debug("No subnet found from '%s' network" % [name])
          subnet = nil
        when 1
          Logging.debug("Found '%s' subnet from '%s' network" % [subnets[0].name, name])
          subnet = subnets[0]
        else 
          Logging.warning("Several subnet was found on '%s'. Choosing the first one = '%s'" % [name, subnets[0].name])
          subnet = subnets[0]
        end
    end  
    if not subnet
      # Create the subnet with 'sub-' prefixing the network name.   
      begin
        subnet = create_subnet(oFC, network_id, 'sub-%s' % [name])
      rescue => e
        Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
    end
    return subnet
  end

  def create_subnet(oFC, network_id, name)
    Logging.debug("Creating subnet '%s'" % [name])
    begin
      oFC.oNetwork.subnets.create(
          :network_id => network_id,
          :name => name,
          :cidr => get_next_subnet(oFC),
          :ip_version => '4'
      )
    rescue => e
      Logging.fatal(1, "%s\n%s" % [e.class.name, e.message])
    end
  end

  def delete_subnet(oFC, subnet)
    Logging.debug("Deleting subnet '%s'" % [subnet.name])
    begin
      oFC.oNetwork.subnets.get(subnet.id).destroy
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  def get_subnet(oFC, name)
    begin
      oFC.oNetwork.subnets.all(:name => name)[0]
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end


  # Router management
  def get_or_create_router(oFC, network, subnet)
    port = get_router_interface_attached(oFC, network)
    if not port
       # Trying to get router 
       router = get_router(oFC, 'router-%s' % network.name)
       router = create_router(oFC, 'router-%s' % network.name) if not router
       create_router_interface(subnet, router) if router
    else
       routers = oFC.oNetwork.routers.all({:id => port.device_id})
       if routers.length() == 1
          if routers[0].external_gateway_info
             Logging.debug("Found router '%s' attached to an external gateway." % [ routers[0].name ] )
          else   
             Logging.debug("Found router '%s' but need to be attached to an external gateway. Attaching..." % [ routers[0].name ] )
             netty=search_gateway(oFC)
             if netty
               routers[0].external_gateway_info = { 'network_id' => netty.id }
               routers[0].save
               Logging.debug("Router '%s' attached to the external network '%s'." % [  routers[0].name, netty.name ] )
             else  
               Logging.fatal(1, "Unable to attach router '%s' to an external gateway. Required for boxes to get internet access. " % [ routers[0].name ] )
             end
          end   
          router = routers[0]
       else
          Logging.warning("Unable to found the router id '%s'" % [ port.device_id ])
          router = nil
       end    
    end
    router
  end

  def get_router(oFC, name)
    Logging.state("Searching for router '%s'..." % [name] )
    begin
      routers = oFC.oNetwork.routers.all({:name => name})
      if routers.length() == 1
         if routers[0].external_gateway_info.has_key?('id')
            Logging.debug("Found router '%s' attached to an external gateway." % [ routers[0].name ] )
         else   
            Logging.warning("Found router '%s' but not attached to an external." % [ routers[0].name ] )
         end   
         routers[0]
      else
         Logging.debug("Router '%s' not found." % [ name ] )
         nil
      end
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  def create_router(oFC, name)
    
    netty = search_gateway(oFC)
    
    begin
    if netty
        Logging.debug("Creating router '%s' attached to the external Network '%s'." % [name, netty.name])
        oFC.oNetwork.routers.create(
            :name => name,
            :admin_state_up => true,
            :external_gateway_info => { 'network_id' => netty.id }
        )
    else
        Logging.debug("Creating router '%s' without external Network." % [name])
        oFC.oNetwork.routers.create(
            :name => name,
            :admin_state_up => true
        )
    end    
    rescue => e
      Logging.fatal(1, "%s\n%s" % [e.inspect, e.message])
    end
  end

  def delete_router(oFC, router_id)
    Logging.debug("Deleting router '%s'" % [router.name])
    begin
      oFC.oNetwork.routers.get(router.id).destroy
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  
  # Router interface to connect to the network
  def create_router_interface(subnet, router)
    Logging.fatal(1, "Internal Error: subnet/router object not passed.") if not subnet or not router

    Logging.debug("Attaching subnet '%s' to router '%s'" % [subnet.name, router.name])
    begin
      router.add_interface(subnet.id, nil)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  def delete_router_interface(subnet_id, router)
    Logging.debug("Removing subnet '%s' from router '%s'" % [subnet.name, router.name])
    begin
      router.remove_interface(subnet_id)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end
  
  def get_router_interface(oFC, network_id, device_id)
    begin
      # Searching for router port attached
      ports=oFC.oNetwork.ports.all({:network_id => network_id, :device_id => device_id})
      case ports.length()
        when 0
          nil
        else  
          port[0]
      end  
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  def get_router_interface_attached(oFC, network)
    Logging.state("Searching for router port attached to the network '%s'" % [network.name] )
    begin
      # Searching for router port attached
      ports=oFC.oNetwork.ports.all({:network_id => network.id, :device_type => 'network:router_interface'})
      case ports.length()
        when 0
          Logging.debug("No router port attached to the network '%s'" % [network.name] )
          nil
        else  
          Logging.debug("Found a router port attached to the network '%s' " % [network.name] )
          ports[0]
      end  
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  # Gateway management  
  def get_gateway(oFC, name)

    return nil if not name or not oFC

    Logging.state("Getting gateway '%s'" % [name])
    networks = oFC.oNetwork
    begin
       netty = networks.get(name)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
    Logging.state("Found gateway '%s'" % [name]) if netty
    Logging.state("Unable to found gateway '%s'" % [name]) if not netty
    return netty
  end 
    
  def search_gateway(oFC)
    Logging.state("Identifying External gateway ...")
    begin
      # Searching for router port attached
      networks=oFC.oNetwork.networks.all({ :router_external => true })
      case networks.length()
        when 0
          Logging.debug("No external network")
          nil
        when 1
          Logging.debug("Found external network '%s'." % [networks[0].name] )
          networks[0]
        else  
          Logging.debug("Found several external networks. Selecting the first one '%s'" % [networks[0].name] )
          networks[0]
      end  
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end 

end


def get_next_subnet(oFC)
  begin
    subnet_values = Array.new
    subnets = oFC.oNetwork.subnets.all

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
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
  end
end
