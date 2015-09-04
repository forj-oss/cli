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
      cert_file = File.expand_path(res_found[1])
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

    server = hParams[:server, :ObjectData]

    cmd = "scp %s #{cert_file} %s:#{dest_file}"
    msg = "Copying local file '#{cert_file}' to #{server[:name]}:#{dest_file}"

    ok = run_ssh(server, hParams, cmd, msg
                ) do |_name, user, pubip, keypair, _ssh_options|
      msg = "Maestro is waiting for the CA root certificate.\n"\
            'But your local environment do not have the appropriate'\
            " ssh private key (#{keypair[:keys]}) to make "\
            "the connection.\nSo, manually, you have to send "\
            "the '#{cert_file}' to '#{pubip}:#{dest_file}' as '#{user}'.\n"\
            'Maestro will stay freezed until you copy this file'\
            ' as suggested.'
    end

    unless ok
      PrcLib.error("Unable to send the Root Certificate file '#{cert_file}' "\
                   "You will need install it yourself in #{server}:"\
                   "#{dest_file}"\
                   ".done' flag file\n#{res}")
      config[:cert_error] = true
      return
    end

    cmd = "ssh %s %s 'touch #{dest_file}.done'"
    msg = 'Flagging the server copy.'
    run_ssh(server, hParams, cmd, msg)
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
