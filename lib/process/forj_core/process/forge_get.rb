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

# Functions for :forge get
class ForjCoreProcess
  def get_forge(sCloudObj, sForgeId, hParams = Lorj::ObjectData.new(true))
    s_query = {}
    servers = {}
    s_query[:name] = Regexp.new("\\.#{sForgeId}$")

    o_servers = process_query(:server, s_query,
                              :search_for => "for instance #{sForgeId}")

    o_servers.each do |o_server|
      type = o_server[:name].clone
      type['.' + sForgeId] = ''
      servers[type] = o_server
    end
    PrcLib.info('%s server(s) found under instance name %s ',
                servers.count, sForgeId)

    forge = register({}, sCloudObj)
    forge[:servers] = servers
    forge[:name] = sForgeId

    _server_show_info(forge, hParams) if hParams[:info].is_a?(TrueClass)

    forge
  end

  def refresh_forge(object_type, forge)
    query_cache_cleanup object_type
    s_query = {}
    servers = forge[:servers]
    forgeid = forge[:name]
    s_query[:name] = Regexp.new("\\.#{forgeid}$")

    o_servers = process_query(:server, s_query,
                              :search_for => "for instance #{forgeid}")

    o_servers.each do |o_server|
      type = o_server[:name].clone
      type['.' + forgeid] = ''
      servers[type] = o_server
    end
    PrcLib.info('%s server(s) found under instance name %s ',
                servers.count, forgeid)

    forge[:servers] = servers
  end
end

# Information Functions for boot - build_forge
class ForjCoreProcess
  def _server_show_info(forge, hParams)
    maestro = forge[:servers, 'maestro']
    forge_info(maestro, hParams)
    read_blueprint_implemented(forge, hParams)
  end

  def _server_info_params(server, params)
    image = params[:image]
    image = server_get_image(server) if image.nil?
    image_user = image.nil? ? 'undefined' : image[:ssh_user]

    public_ip = _server_info_ip(server, params)

    ssh_key = params[:keypairs]
    ssh_key = boot_keypairs(server) if ssh_key.nil? || ssh_key[:keys].nil?

    server_name = 'undefined'
    server_name = server[:name] unless server.nil?

    [server_name, image_user, public_ip, ssh_key]
  end

  def _server_info_ip(server, params)
    public_ip = nil
    public_ip = _server_info_ip_from_server(server, params) unless server.nil?

    return public_ip unless public_ip.nil?

    public_ip = params[:public_ip, :public_ip] unless params[:public_ip].nil?
    return public_ip unless public_ip.nil?

    unless server.nil?
      query = { :server_id => server[:id] }
      addresses = process_query(:public_ip, query, params)
      register(addresses[0]) if addresses.length > 0
      public_ip = addresses[0, :public_ip]
    end
    public_ip.nil? ? 'undefined' : public_ip
  end

  def _network_used(server, params)
    return params[:network_used] unless params[:network_used].nil?
    return server[:meta_data, 'network_name'] if /maestro\./ =~ server[:name]
    '//0'
  end

  def _server_info_ip_from_server(server, params)
    public_ip = server[:pub_ip_addresses, _network_used(server, params)]

    return public_ip unless public_ip.is_a?(Array)

    if public_ip.length > 1
      PrcLib.warning('Network name used not provided: So, multiple public IPs '\
                     " was found '%s'. Selecting the first one.", public_ip)
      return public_ip[0]
    end
    nil
  end

  # function to print out the ssh connection information to the user
  # and return the forge status.
  #
  # * *args*:
  #   - server : Server object with :name
  #   - hParams: List of object to get data.
  #     - image  : Image object with :ssh_user
  #     - address: Server address with :public_ip
  #     - ssh_key: Server ssh keys with :keys
  #     - status : Boot status. If boot status is :active
  #       the msg will simply display how to connect to.
  #       otherwise, it display, how to show instant log.
  #   - forge_status: Provide the forge status
  #
  # * *returns*:
  #   - status : Symbol. The Forge status.
  def forge_info(server, params, status = nil)
    if server.nil?
      PrcLib.warning 'Maestro was not found in this forge!!!'
      return :incomplete
    end

    server_name, image_user, public_ip,
      ssh_key = _server_info_params(server, params)

    status = forge_status(server).status if status.nil?

    if ssh_key[:coherent]
      private_key = ssh_key[:keys]
    else
      private_key = ANSI.red(ANSI.bold('<no valid private key found>'))
      more = "\n\n" +
             ANSI.bold('Unfortunatelly') + ', Forj was not able to find a '\
             'valid keypair to connect to your server.' \
             "\nYou need to fix this issue to gain access to your server."
    end

    if status == :active
      msg = <<-END
Maestro is accessible through http://#{public_ip}. This will provide
you access to your complete forge implemented by your blueprint.

If you want to access your server through ssh, you have several options:

- using `forj ssh`\n- using ssh cli with:
  ssh #{image_user}@#{public_ip} -o StrictHostKeyChecking=no -i #{private_key}

  You can also create a new host in your ssh config with:
  echo 'host c_#{server_name}
      hostname #{public_ip}
      identity_file #{private_key}
      User #{image_user}
      # If you need to set a proxy to access this server
      # ProxyCommand corkscrew web-proxy 8080 %%h %%p' >> ~/.ssh/config

  So, you will be able to connect to your server with:
  ssh c_#{server_name}#{more}
      END
    else
      msg = <<-END
Your forge is still building...
Now, as soon as the server respond to the ssh port,
you will be able to get a tail of the build with:
while [ 1 = 1 ]
do
 ssh #{image_user}@#{public_ip} -o StrictHostKeyChecking=no -i #{private_key} \
tail -f /var/log/cloud-init.log
 sleep 5
done#{more}
      END
    end
    PrcLib.info(msg)
    PrcLib.high_level_msg(msg) if status == :active
    status
  end

  def read_blueprint_implemented(o_forge, _params)
    maestro = o_forge[:servers, 'maestro']
    return if maestro.nil?
    network_used = maestro[:meta_data, 'network_name']
    public_ip = maestro[:pub_ip_addresses, network_used]
    blueprint = maestro[:meta_data, 'blueprint']
    instance_name = o_forge[:name]
    s_msg = "Your Forge '#{instance_name}' is ready and accessible from" \
            " IP #{public_ip}."

    # TODO: read the blueprint/layout to identify which services
    # are implemented and can be accessible.
    if blueprint
      s_msg += "\nMaestro has implemented the following server(s) for your"\
               " blueprint '#{blueprint}':"
      s_msg = display_servers_with_ip(o_forge, blueprint, network_used, s_msg)
    else
      s_msg += "\nMaestro has NOT implemented any servers, because you did" \
        ' not provided a blueprint. Connect to Maestro, and ask Maestro to' \
        ' implement any kind of blueprint you need. (Feature currently' \
        ' under development)'
    end
    PrcLib.info(s_msg)
    PrcLib.high_level_msg("\n%s\nEnjoy!\n", s_msg)
  end

  def display_servers_with_ip(o_forge, blueprint, network_used, msg)
    i_count = 0
    o_forge[:servers].each do |_type, server|
      next if /^maestro\./ =~ server[:name]

      if server[:pub_ip_addresses, network_used].nil?
        # Required as the server may not be refreshed.
        register(server)
        o_ip = process_query(:public_ip, :server_id => server[:id])
        ip = o_ip[0][:public_ip] unless o_ip.length == 0
      else
        ip = server[:pub_ip_addresses, network_used]
      end
      if ip.nil?
        msg += format("\n- %s (No public IP)", server[:name])
      else
        msg += format("\n- %s (%s)", server[:name], ip)
      end
      i_count += 1
    end

    if i_count > 0
      msg += format("\n%d server(s) identified.\n", i_count)

    else
      msg = 'No servers found except maestro'
      PrcLib.warning('Something went wrong, while creating nodes for blueprint'\
                     " '#{blueprint}'. check maestro logs "\
                     "(Usually /var/log/cloud-init.log).\n"\
                     'Consider Lorj Gardener by setting :default/:lorj: '\
                     'false in /opt/config/lorj/config.yaml if puppet'\
                     ' returned some strange ruby error.')
    end

    msg
  end
end
