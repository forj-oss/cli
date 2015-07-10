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

# Functions for ssh
class ForjCoreProcess
  def ssh_connection(sObjectType, hParams)
    # Get server information
    PrcLib.state('Getting server information')
    o_server = hParams[:server, :ObjectData]
    register(o_server)
    public_ip = ssh_server_public_ip(o_server)

    ssh_options = ssh_keypair(o_server)
    # Get ssh user
    image  = process_get(:image, o_server[:image_id])
    user = hParams[:ssh_user]

    user = image[:ssh_user] if user.nil?

    PrcLib.debug("Using account '%s'.", user)

    begin
      PrcLib.state("creating ssh connection with '%s' box", o_server[:name])
      ssh_login(ssh_options, user, public_ip)
   rescue => e
     PrcLib.fatal 1, <<-END
#{e.message}
You were not able to connect to this box. Please note that there is no
 garantuee that your local private key file '#{ssh_options[:keys]}' is the
 one that was used while building this box.
You have to check with the user who created that box.
         END
    end
    register({ :success => true }, sObjectType)
  end

  def ssh_keypair(o_server)
    if config[:identity].nil? || !config[:identity].is_a?(String)
      h_keys = keypair_detect(
        o_server[:key_name],
        File.join(Forj.keypairs_path, o_server[:key_name])
      )
    else
      h_keys = keypair_detect(
        o_server[:key_name],
        File.expand_path(config[:identity])
      )
    end

    private_key_file = File.join(
      h_keys[:keypair_path],
      h_keys[:private_key_name]
    )
    public_key_file = File.join(h_keys[:keypair_path], h_keys[:public_key_name])

    PrcLib.info("Found openssh private key file '%s'.",
                private_key_file) if h_keys[:private_key_exist?]

    if h_keys[:public_key_exist?]
      PrcLib.info("Found openssh public key file '%s'.", public_key_file)
    else
      PrcLib.warning("Openssh public key file '%s' not found. Unable to verify"\
                     ' keys coherence with remote server.', public_key_file)
    end
    ssh_options = ssh_options(h_keys, private_key_file, o_server)
    ssh_options
  end

  def ssh_options(h_keys, private_key_file, o_server)
    if h_keys[:private_key_exist?]
      ssh_options = { :keys => private_key_file }
      PrcLib.debug("Using private key '%s'.", private_key_file)
    else
      PrcLib.fatal 1, <<-END
The server '#{o_server[:name]}' has been configured with a keypair
 '#{o_server[:key_name]}' which is not found locally.
You won't be able to connect to that server without
 '#{o_server[:key_name]}' private key.
To connect to this box, you need to provide the appropriate private
 key file with option -i
      END
    end
    ssh_options
  end

  def ssh_server_public_ip(o_server)
    # Get Public IP of the server. Needs the server to be loaded.
    network_used = o_server[:meta_data, 'network_name']
    unless o_server[:pub_ip_addresses, network_used].nil?
      return o_server[:pub_ip_addresses, network_used]
    end
    o_address = process_query(:public_ip, :server_id => o_server[:id])

    if o_address.length == 0
      PrcLib.fatal(1, 'ip address for %s server was not found', o_server[:name])
    else
      public_ip = o_address[0][:public_ip]
    end
    public_ip
  end
end

# Functions for ssh
class ForjCoreProcess
  def setup_ssh_user(_sCloudObj, hParams)
    images  = process_query(:image,  :name => hParams[:image_name])
    result = { :list => config[:users] }
    if images.length >= 1 && !images[0, :ssh_user].nil?
      result[:default_value] = images[0, :ssh_user]
    end
    result
  end

  def ssh_login(options, user, public_ip)
    s_opts = '-o StrictHostKeyChecking=no -o ServerAliveInterval=180'
    s_opts += format(' -i %s', options[:keys]) if options[:keys]

    command = format('ssh %s %s@%s', s_opts, user, public_ip)
    PrcLib.debug("Running '%s'", command)
    system(command)
  end
end
