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
    server = hParams[:server, :ObjectData]
    register(server)

    cmd = 'ssh %s %s'
    msg = "creating ssh connection with '#{server[:name]}' box"
    begin
      run_ssh(server, hParams, cmd,
              msg) do |_name, _user, _pubip, _keypair, ssh_options|
        run = format(cmd, ssh_options)
        PrcLib.error("Unable to connect to your box with '#{run}'")
      end
    rescue => e
      PrcLib.fatal 1, <<-END
#{e.message}
You were not able to connect to this box. Please note that there is no
 garantuee that your local private key file is the
 one that was used while building this box.
You have to check with the user who created that box.
         END
    end
    register({ :success => true }, sObjectType)
  end

  # Internal function to execute an SSH/SCP command
  #
  # * *args*:
  #   - server : Lorj::Data. Server to connect to
  #   - params : event parameters.
  #   - cmd    : String. Ssh command to execute. The string must contains
  #     one %s, which will be replaced by the ssh connections options.
  #   - msg    : Optional String. Info message printed out.
  def run_ssh(server, hParams, cmd, msg = nil)
    server_name, user, pubip, keypair = _server_info_params(server, hParams)

    identity = keypair[:keys]

    ssh_options = '-o StrictHostKeyChecking=no -o ServerAliveInterval=180'\
                  " -i #{identity} "
    ssh_connect = "#{user}@#{pubip}"
    if keypair[:coherent]
      PrcLib.warning('ssh config is currently not managed. You may '\
                     'need to configure it yourself, otherwise forj may not '\
                     'connect and transfert data to the box, if some options'\
                     ' are required for the connection.')
      # TODO: Implement testing branch warning. See build.sh lines 618 -> 632
      run_cmd = format cmd, ssh_options, ssh_connect

      PrcLib.info(msg) unless msg.nil?
      PrcLib.debug "Running following shell instructions:\n#{run_cmd}"

      return true if system(run_cmd)
    end

    return false unless block_given?
    yield(server_name, user, pubip, keypair, ssh_options)
  end
end
