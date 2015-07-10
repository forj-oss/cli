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
  def get_forge(sCloudObj, sForgeId, hParams)
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
    PrcLib.info('%s server(s) were found under instance name %s ',
                servers.count, sForgeId)

    o_forge = register({}, sCloudObj)
    o_forge[:servers] = servers
    o_forge[:name] = sForgeId
    if hParams[:info].is_a?(TrueClass)
      maestro = servers['maestro']
      unless maestro.nil?
        msg = server_connect_info(maestro, nil, nil, nil)
        PrcLib.info(msg)
        PrcLib.high_level_msg(msg)
      end
      read_blueprint_implemented(o_forge, hParams)
    end
    o_forge
  end
end

# Information Functions for boot - build_forge
class ForjCoreProcess
  def _server_info_params(server, image, address, ssh_key, status)
    image = server_get_image(server) if image.nil?
    image_user = image.nil? ? 'undefined' : image[:ssh_user]
    public_ip = 'undefined'
    server_name = 'undefined'
    ssh_key = boot_keypairs(server) if ssh_key.nil?
    unless server.nil?
      server_name = server[:name]
      network_used = server[:meta_data, 'network_name']
      public_ip = server[:pub_ip_addresses, network_used]
      status = server[:status] if status.nil?
    end

    if public_ip.nil?
      public_ip = address.nil? ? 'undefined' : address[:public_ip]
    end

    [server_name, image_user, public_ip, ssh_key, status]
  end

  # function to print out the ssh connection information to the user
  #
  # * *args*:
  #   - server : Server object with :name
  #   - image  : Image object with :ssh_user
  #   - address: Server address with :public_ip
  #   - ssh_key: Server ssh keys with :keys
  #   - status : Boot status. If boot status is :active
  #     the msg will simply display how to connect to.
  #     otherwise, it display, how to show instant log.
  #
  # * *returns*:
  #   - msg : A composite message to display
  def server_connect_info(server, image, address, ssh_key, status = nil)
    server_name, image_user, public_ip, ssh_key,
      status = _server_info_params(server, image, address, ssh_key, status)

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
      "Maestro is accessible through http://#{public_ip}. This will provide"\
      " you access to your complete forge implemented by your blueprint.\n\n"\
      'If you want to access your server through ssh, you have several '\
      "options:\n- using `forj ssh`\n- using ssh cli with:\n"\
      "  ssh #{image_user}@#{public_ip} -o StrictHostKeyChecking=no -i "\
      "#{private_key}\n\n"\
      "  You can also create a new host in your ssh config with:\n"\
      "  echo 'host c_#{server_name}\n"\
      "      hostname #{public_ip}\n"\
      "      identity_file #{private_key}\n"\
      "      User #{image_user}\n"\
      "      # If you need to set a proxy to access this server\n"\
      "      # ProxyCommand corkscrew web-proxy 8080 %%h %%p' >> "\
      "~/.ssh/config\n"\
      "\n  So, you will be able to connect to your server with:\n"\
      "  ssh c_#{server_name}#{more}\n"
    else
      "Your forge is still building...\n"\
      "Now, as soon as the server respond to the ssh port,\n"\
      "you will be able to get a tail of the build with:\n"\
      "while [ 1 = 1 ]\n"\
      "do\n"\
      " ssh #{image_user}@#{public_ip} -o StrictHostKeyChecking=no -i "\
      "#{private_key} tail -f /var/log/cloud-init.log\n"\
      " sleep 5\n"\
      "done#{more}"
    end
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
