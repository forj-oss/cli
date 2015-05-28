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

# Functions for test-box
class ForjCoreProcess
  # This function detects if the server requires the certificate file to be sent

  def ca_root_detect(hParams, log_output)
    return unless hParams['certs#ca_root_cert'] && !config.exist?(:cert_error)
    cert_file = hParams['certs#ca_root_cert']

    re = /forj-cli: ca-root-cert=(.*)/
    res = log_output.split("\n")[-4].match(re)

    return unless res

    res_found = cert_file.match(/^(.*)#(.*)$/)

    if res_found
      cert_file =  File.expand_path(res_found[1])
      dest_file = "/tmp/#{File.basename(res_found[2])}"
    else
      cert_file = File.expand_path(cert_file)
      dest_file = File.basename(cert_file)
    end

    unless File.readable?(cert_file)
      PrcLib.error("Unable to read the Root Certificate file '%s'"\
                   "You will need install it yourself in /tmp + '"\
                   ".done' flag file", cert_file)
      config[:cert_error] = true
      return
    end

    server = hParams[:server, :name]
    public_ip = hParams[:public_ip, :public_ip]
    identity = File.join(hParams[:keypairs, :keypair_path],
                         hParams[:keypairs, :private_key_name])
    # Get ssh user
    user = hParams[:image, :ssh_user]

    PrcLib.info("Copying local file '#{cert_file}' to #{server}:#{dest_file}")

    ssh_options = '-o StrictHostKeyChecking=no -o ServerAliveInterval=180'
    ssh_options += " -i #{identity}"

    cmd = "scp #{ssh_options} #{cert_file} #{user}@#{public_ip}:#{dest_file}"
    PrcLib.debug("Running command '%s'", cmd)
    res = `#{cmd}`

    # For any reason, $CHILD_STATUS is empty, while $? is not.
    # Ruby bug. tested with:
    # ruby 2.0.0p353 (2013-11-22 revision 43784) [x86_64-linux]
    # rubocop: disable Style/SpecialGlobalVars
    unless $?.exitstatus == 0
      # rubocop: enable Style/SpecialGlobalVars
      PrcLib.error("Unable to send the Root Certificate file '%s' "\
                   "You will need install it yourself in /tmp + '"\
                   ".done' flag file\n%s", cert_file, res)
      config[:cert_error] = true
      return
    end

    PrcLib.debug('Flagging the server copy.')
    `ssh #{ssh_options} #{user}@#{public_ip} touch #{dest_file}.done`
  end

  # function to add extra meta data to support ca_root_cert
  #
  # * *Args*:
  #   - metadata : Hash. Hash structure to update.
  #
  # * * returns*:
  #   - nothing
  def ca_root_metadata(hParams, metadata)
    return unless hParams.exist?('certs#ca_root_cert')

    res_found = hParams['certs#ca_root_cert'].match(/^(.*)#(.*)$/)

    if res_found
      dest_file = "#{res_found[2]}"
    else
      dest_file = File.basename(hParams['certs#ca_root_cert'])
    end

    metadata['CA_ROOT_CERT'] = dest_file
  end
end
