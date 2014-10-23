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
#
# This file describe generic process to create/query/get/delete Cloud objects.
# forj_* function are handler, predefined by cloud_data_pref.rb
# The process functions communicates with config, object or controler(provider controler)
#
# 'config' is the configuration system which implements:
# - get(key):        Get the value to the associated key
#   [key]            is the 'set' equivalent
# - set(key, value): Set a value to a key.
#   [key] = value    Is the 'set' equivalent
#
# 'object' contains Object definition, Object manipulation. It implements:
# - query_map(sCloudObj, sQuery): transform Forj Object query request to
#                                 a Provider controler query request
#                                 The result of this function is usually sent to
#                                 the controler query function.
#
# - get_attr(oObject, key): Read the object key from the object.
#
# Providers can redefine any kind of handler if needed.

# ---------------------------------------------------------------------------
# Network/Subnetwork Management
# ---------------------------------------------------------------------------
class CloudProcess < BaseProcess
   # Process Query handler
   def forj_query_network(sCloudObj, sQuery, hParams)


      # Call Provider query function
      controler.query(sObjectType, sControlerQuery)
   end

   # Process Create handler
   def forj_get_or_create_network(sCloudObj, hParams)

      Logging.state("Searching for network '%s'" % [hParams[:network_name]])
      networks = find_network(sCloudObj, hParams)
      if networks.length == 0
         network = create_network(sCloudObj, hParams)
      else
         network = networks[0]
      end
      register(network)

      # Attaching if missing the subnet.
      # Creates an object subnet, attached to the network.
      if not hParams[:subnetwork_name]
         hParams[:subnetwork_name] = 'sub-' + hParams[:network_name]
         config.set(:subnetwork_name, hParams[:subnetwork_name])
      end

      get_or_create_subnet(hParams)

      network

   end

   # Process Delete handler
   def forj_delete_network(sCloudObj, hParams)
      begin
         oProvider.delete(sCloudObj, hParams)
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end

   def forj_get_network(sCloudObj, sID, hParams)
      begin
         oProvider.get(sCloudObj, sID, hParams)
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end

   # Network Process internal functions #
   #------------------------------------#

   # Network creation
   # It returns:
   # nil or Provider Object
   def create_network(sCloudObj, hParams)
      begin
         Logging.debug('creating network %s' % [name])
         controler.create(sCloudObj)
      rescue => e
         Logging.fatal(1, "Unable to create network '%s'" % name, e)
      end
   end

   # Search for a network from his name.
   # Name may be unique in project context, but not in the cloud system
   # It returns:
   # nil or Provider Object
   def find_network(sCloudObj, hParams)
      begin
         # retrieve the Provider collection object.
         sQuery = {:name => hParams[:network_name]}
         oList = controler.query(sCloudObj, sQuery)
         query_single(sCloudObj, sQuery, hParams[:network_name])
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end

   def get_or_create_subnet(hParams)

      Logging.state("Searching for sub-network attached '%s'" % [hParams[:network_name]])
      #######################
      begin
         sQuery = { :network_id => get_data(:network, :id) }
         subnets = controler.query(:subnetwork, sQuery)
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
      if subnets
         case subnets.length()
            when 0
               Logging.info("No subnet found from '%s' network" % [hParams[:network_name]])
               subnet = ForjLib::Data.new
            when 1
               Logging.info("Found '%s' subnet from '%s' network" % [subnets[0, :name], hParams[:network_name]])
               subnet = subnets[0]
            else
               Logging.warning("Several subnet was found on '%s'. Choosing the first one = '%s'" % [hParams[:network_name], subnets[0, :name]])
               subnet = subnets[0]
         end
      end
      if not subnet
         # Create the subnet
         subname = hParams[:subnetwork_name]
         begin
            subnet = create_subnet(hParams[:network_connection], hParams[:network], subname)
         rescue => e
            Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
         end
      end
      register(subnet)
      subnet
   end

  def create_subnet(oNetworkConnect, oNetwork, network_name)
    Logging.state("Creating subnet '%s'" % [network_name])
    begin
      subnet = provider_create_subnetwork(oNetworkConnect, oNetwork, network_name)
      Logging.info("Subnet '%s' created." % [network_name])
    rescue => e
      Logging.fatal(1, "Unable to create '%s' subnet." % network_name, e)
    end
    subnet
  end

   def delete_subnet()

      oNetworkConnect = get_cloudObj(:network_connection)
      oSubNetwork = get_cloudObj(:subnetwork)

      Logging.state("Deleting subnet '%s'" % [oSubNetwork.name])
      begin
         provider_delete_subnetwork(oNetworkConnect, oSubNetwork)
         oNetworkConnect.subnets.get(oSubNetwork.id).destroy
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end
end

# ---------------------------------------------------------------------------
# Router management
# ---------------------------------------------------------------------------
class CloudProcess
   # Process Create handler
   def forj_get_or_create_router(sCloudObj, hParams)
      oNetwork = hParams.get(:network)
      oSubNetwork = hParams[:subnetwork]

      router_name = rhGet(hParams, :router_name)
      if not router_name
         router_name = 'router-%s' % router_name
      end

      router_port = get_router_interface_attached(:port, hParams)

      if not router_port
         # Trying to get router
         router = get_router(router_name)
         router = create_router(router_name) if not router
         create_router_interface(oSubNetwork, router) if router
      else
         sQuery = {:id => get_data(router_port, :device_id)}
         routers = controler.query(:router, sQuery)
         case routers.length()
            when 1
               Logging.info("Found router '%s' attached to the network '%s'." % [
                  routers[0, :name],
                  get_data(:network, :name)
               ])
               router = routers[:list][0]
            else
               Logging.warning("Unable to find the router id '%s'" % [ get_data(router_port, :device_id) ])
               router = ForjLib::Data.new

         end
      end
      router
   end

   def forj_update_router(sCloudObj, hParams)
      controler.update(sObjectType)
            ################################
            #routers[0].external_gateway_info = { 'network_id' => external_network.id }
            #routers[0].save

   end

   # Router Process internal functions  #
   #------------------------------------#

   def get_router(name)
      Logging.state("Searching for router '%s'" % [name] )
      begin
         routers = controler.query(:router, {:name => name})
         case routers.length()
            when 1
               routers[0]
            else
               Logging.warning("Router '%s' not found." % [ name ] )
               ForjLib::Data.new
         end
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end

   def create_router(router_name, oExternalNetwork = nil)

      sExtNet = nil
      sExtNet = get_data(oExternalNetwork, :name) if oExternalNetwork

      begin
         hRouter = {
            :router_name => router_name,
            :external_gateway_id => get_data(oExternalNetwork, :id)
         }
         if oExternalNetwork
            Logging.state("Creating router '%s' attached to the external Network '%s'" % [router_name, sExtNet])

            hRouter[:external_gateway_id] = get_data(oExternalNetwork, :id)
         else
            Logging.state("Creating router '%s' without external Network" % [router_name])
         end
         controler.create(:router)
      rescue => e
         raise ForjError.new(), "Unable to create '%s' router\n%s" % [router_name, e.message]
      end
   end

   def delete_router(oNetworkConnect, oRouter)
      Logging.state("Deleting router '%s'" % [router.name])
      begin
         #################
         provider_delete_router(oNetworkConnect, oRouter)
         # oNetworkConnect.routers.get(router.id).destroy
      rescue => e
         Logging.error("Unable to delete '%s' router ID" % router_id, e)
      end
   end

  # Router interface to connect to the network
  def create_router_interface(oSubnet, oRouter)
    Logging.fatal(1, "Internal Error: subnet/router object not passed.") if not oSubnet or not oRouter

    Logging.state("Attaching subnet '%s' to router '%s'" % [oSubnet.name, oRouter.name])
    begin
      #################
      provider_add_interface()
      # oRouter.add_interface(oSubnet.id, nil)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  def delete_router_interface(oSubnet, oRouter)
    Logging.state("Removing subnet '%s' from router '%s'" % [oSubnet.name, oRouter.name])
    subnet_id = oSubnet.id
    begin
      #################
      oRouter.remove_interface(subnet_id)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

  #~ def get_router_interface(oNetworkConnect, network_id, device_id)
    #~ begin
      #~ # Searching for router port attached
      #~ #################
      #~ ports=oNetworkConnect.ports.all({:network_id => network_id, :device_id => device_id})
      #~ case ports.length()
        #~ when 0
          #~ nil
        #~ else
          #~ port[0]
      #~ end
    #~ rescue => e
      #~ Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    #~ end
  #~ end

  def get_router_interface_attached(sCloudObj, hParams)

      oNetwork = hParams[:network]
      Logging.state("Searching for router port attached to the network '%s'" % [hParams[:network, :name]] )
      begin
         # Searching for router port attached
         #################
         sQuery = {:network_id => get_data(:network, :id), :device_owner => 'network:router_interface'}
         ports = controler.query(sCloudObj, sQuery)
         case ports.length()
            when 0
               Logging.info("No router port attached to the network '%s'" % [hParams[:network, :name] ])
               ForjLib::Data.new
            else
               Logging.info("Found a router port attached to the network '%s' " % [hParams[:network, :name] ] )
               ports[0]
         end
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
  end

  # Gateway management
  def get_gateway(oNetworkConnect, name)

    return nil if not name or not oNetworkConnect

    Logging.state("Getting gateway '%s'" % [name])
    networks = oNetworkConnect
    begin
       netty = networks.get(name)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
    Logging.state("Found gateway '%s'" % [name]) if netty
    Logging.state("Unable to find gateway '%s'" % [name]) if not netty
    return netty
  end

  def query_external_network(hParams)
    Logging.state("Identifying External gateway")
    begin
      # Searching for router port attached
      #################
      sQuery = { :router_external => true }
      networks = controler.query(:network, sQuery)
      case networks.length()
        when 0
          Logging.info("No external network")
          ForjLib::Data.new
        when 1
          Logging.info("Found external network '%s'." % [networks[0, :name] ] )
          networks[0]
        else
          Logging.warn("Found several external networks. Selecting the first one '%s'" % [networks[0, :name]] )
          networks[0]
      end
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

end

# ---------------------------------------------------------------------------
# SecurityGroups management
# ---------------------------------------------------------------------------

class CloudProcess

   # Process Create handler
   def forj_get_or_create_sg(sCloudObj, hParams)
      sSGName = hParams[:security_group]
      Logging.state("Searching for security group '%s'" % [sSGName] )

      security_group = forj_query_sg(sCloudObj, {:name => sSGName}, hParams)
      security_group = create_security_group(sCloudObj, hParams) if not security_group
      register(security_group)

      Logging.info('Configuring Security Group \'%s\'' % [sSGName])
      ports = config.get(:ports)

      ports.each do |port|
         port = port.to_s if port.class != String
         if not (/^\d+(-\d+)?$/ =~ port)
            Logging.error("Port '%s' is not valid. Must be <Port> or <PortMin>-<PortMax>" % [port])
         else
            mPortFound = /^(\d+)(-(\d+))?$/.match(port)
            portmin = mPortFound[1]
            portmax = (mPortFound[3]) ? (mPortFound[3]) : (portmin)
            # Need to set runtime data to get or if missing create the required rule.
            config[:dir]        = :IN
            config[:proto] = 'tcp'
            config[:port_min]   = portmin.to_i
            config[:port_max]   = portmax.to_i
            config[:addr_map]   = '0.0.0.0/0'

            object.Create(:rule)
         end
      end
      security_group
   end

   # Process Delete handler
   def forj_delete_sg(oFC, security_group)
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

   # Process Query handler
   def forj_query_sg(sCloudObj, sQuery, hParams)
      oSSLError=SSLErrorMgt.new

      begin
         sgroups = controler.query(sCloudObj, sQuery)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
         Logging.fatal(1, "Unable to get list of security groups.", e)
      end
      case sgroups.length()
         when 0
            Logging.info("No security group '%s' found" % [ hParams[:name] ] )
            nil
         when 1
            Logging.info("Found security group '%s'" % [sgroups[0, :name]])
            sgroups[0]
      end
   end

   # SecurityGroups Process internal functions #
   #-------------------------------------------#
  def create_security_group(sCloudObj, hParams)
    Logging.state("creating security group '%s'" % hParams[:name])
    begin
      controler.create(sCloudObj)
    rescue => e
      Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
    end
  end

   # Rules handler #
   #---------------#

   # Process Delete handler
  def forj_delete_security_group_rule(sCloudObj, hParams)

    oSSLError=SSLErrorMgt.new
    begin
      controler.delete(sCloudObj)
    rescue => e
      if not oSSLError.ErrorDetected(e.message,e.backtrace)
         retry
      end
    end
  end

   # Process Query handler
  def forj_query_rule(sCloudObj, sQuery, hParams)
      sRule = '%s %s:%s - %s to %s' % [ hParams[:dir], hParams[:rule_proto], hParams[:port_min], hParams[:port_max], hParams[:addr_map] ]
      Logging.state("Searching for rule '%s'" % [ sRule ])
      oSSLError = SSLErrorMgt.new
      begin
         sInfo = {
            :items      => [:dir, :rule_proto, :port_min, :port_max, :addr_map],
            :items_form => '%s %s:%s - %s to %s'
         }
         oList = controler.query(sCloudObj, sQuery)
         query_single(sCloudObj, oList, sQuery, sRule, sInfo)
      rescue => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
      end
   end

   # Process Create handler
   def forj_get_or_create_rule(sCloudObj, hParams)

      sQuery = {
         :dir            => hParams[:dir],
         :proto          => hParams[:proto],
         :port_min       => hParams[:port_min],
         :port_max       => hParams[:port_max],
         :addr_map       => hParams[:addr_map],
         :sg_id          => hParams[:sg_id]
      }

      rules = forj_query_rule(sCloudObj, sQuery, hParams)
      if rules.length == 0
         create_rule(sCloudObj, hParams)
      else
         rules[0]
      end
   end

   # Rules internal #
   #----------------#
   def create_rule(sCloudObj, hParams)

      sRule = '%s %s:%s - %s to %s' % [ hParams[:dir], hParams[:rule_proto], hParams[:port_min], hParams[:port_max], hParams[:addr_map] ]
      Logging.debug("Creating rule '%s'" % [sRule])
      oSSLError=SSLErrorMgt.new
      begin
         controler.create(sCloudObj)
      rescue StandardError => e
         if not oSSLError.ErrorDetected(e.message,e.backtrace)
            retry
         end
         Logging.error 'error creating the rule for port %s' % [sRule]
      end
   end

end

# ---------------------------------------------------------------------------
# External network process attached to a network
# ---------------------------------------------------------------------------
class CloudProcess
   def forj_get_or_create_ext_net(sCloudObj, hParams)

      Logging.state("Checking router's gateway'")

      oRouter = hParams.get(:router)
      sRouterName = get_data(:router, :name)
      sNetworkId = get_data(:router, :gateway_network_id)
      if sNetworkId
         Logging.info("Found router '%s' attached to an external gateway." % [ sRouterName ] )
         forj_query_external_network(sCloudObj, {:id => sNetworkId}, hParams)
      else
         #byebug
         Logging.info("Found router '%s' but need to be attached to an external gateway. Attaching" % [ sRouterName ] )
         external_network = forj_query_external_network(:network, {}, hParams)
         if external_network
            oRouter[:attrs][:gateway_network_id] = get_data(external_network, :id)
            forj_update_router(:router, hParams)
            Logging.info("Router '%s' attached to the external network '%s'." % [routers[:list][0][:attrs][:name], get_data(external_network, :name) ])
         else
            Logging.fatal(1, "Unable to attach router '%s' to an external gateway. Required for boxes to get internet access. " % [ get_data(:router, :name) ] )
         end
      end
   end

   def forj_query_external_network(sCloudObj, sQuery, hParams)
      Logging.state("Identifying External gateway")
      begin
         # Searching for external network
         networks = controler.query(:network, sQuery.merge({ :external => true }))

         case networks[:list].length()
         when 0
            Logging.info("No external network")
            nil
         when 1
            Logging.info("Found external network '%s'." % [networks[:list][0][:attrs][:name] ])
            networks[:list][0]
         else
            Logging.warning("Found several external networks. Selecting the first one '%s'" % [networks[:list][0][:attrs][:name]])
            networks[:list][0]
         end
      rescue => e
         Logging.error("%s\n%s" % [e.message, e.backtrace.join("\n")])
      end
   end

end

# ---------------------------------------------------------------------------
# Internet network process
# ---------------------------------------------------------------------------
class CloudProcess


end
