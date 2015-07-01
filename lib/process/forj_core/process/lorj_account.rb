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

# Process to call lorj_export

require 'lorj'

# lorj_account process functions
class ForjCoreProcess
  def build_lorj_account(sObjectType, hParams)
    map = {}

    Lorj.data.meta_each do |section, key, data|
      section_key = "#{section}##{key}"

      next if data.nil? || data[:export].nil?

      if data[:export].boolean?
        map[section_key] = {} if data[:export]
        next
      end

      map[section_key] = { :keys => data[:export] }
    end
    data = {}
    data[:key], data[:data] = account_export(map, true, true,
                                             :exclude => ['forj_core'])
    data_registered = register(data, sObjectType)
    data_registered[:key] = Base64.strict_encode64(data[:key].to_yaml)
    data_registered[:data] = data[:data]
    enabled = !hParams['maestro#lorj_disabled'].is_a?(TrueClass)
    data_registered[:enabled] = enabled
    data_registered
  end

  def lorj_metadata(hParams, h_meta)
    h_meta['lorj_enabled'] = hParams[:lorj_account, :enabled].to_s
  end

  def lorj_detect(hParams, log_output, keypair)
    return unless hParams.exist?(:lorj_account, :data)

    # the server must wait with 4 last lines in server log:
    # [...] - forj-cli: lorj_tmp_file=[...] lorj_tmp_key=[...] flag_file=[...]
    # [...] - build.sh: [...]
    # [...] - forj-cli: Waiting for [...]
    # [...] - On your workstation, [...]

    re = /forj-cli: lorj_tmp_file=(.*) lorj_tmp_key=(.*) flag_file=(.*)/
    res = log_output.split("\n")[-4].match(re)

    return unless res
    PrcLib.info('lorj: your box is waiting for your cloud data. '\
                'One moment.')

    # TODO : Add tb_ensure_ssh_config task to set this server in ~/.ssh/config.
    # unless tb_ensure_ssh_config(hParams)
    #  PrcLib.info('test-box: Unable to configure ssh config with this server.'\
    #               ' You needs to do it yourself manually. Remote box boot '\
    #               "process is waiting for #{test_box_dir}")
    #   return
    # end
    PrcLib.warning('lorj: ssh config is currently not managed. You may '\
                   "need to configure it yourself, otherwise forj won't "\
                   'connect and transfert the data to the box.')

    pubip = hParams[:public_ip, :public_ip]
    user = hParams[:image, :ssh_user]
    identity = File.join(keypair[:keypair_path], keypair[:private_key_name])

    if keypair[:coherent]
      ssh_options = '-o StrictHostKeyChecking=no -o ServerAliveInterval=180'
      ssh_options += " -i #{identity}"
      ssh_options += " #{user}@#{pubip}"
      ssh_cmd = "echo \"#{hParams[:lorj_account, :data]}\" > #{res[1]}"
      ssh_cmd += "; echo \"#{hParams[:lorj_account, :key]}\" > #{res[2]}"
      ssh_cmd += "; touch \"#{res[3]}\""

      # TODO: Implement testing branch warning. See build.sh lines 618 -> 632
      cmd = "ssh #{ssh_options} '#{ssh_cmd}'"

      PrcLib.info "Running following shell instructions:\n#{cmd}"

      return if system(cmd)
    end

    msg <<-EOF
Unable to copy Lorj data to the server '#{pubip}'. You need to do it yourself
manually, now. To do it, execute following instructions:
1. Connect to server #{pubip} as #{user}.
   You need to find the proper way to connect to '#{pubip}' as the cloud keypair
   found is not coherent with some local SSH keys in
   #{PrcLib.data_path}/keypairs

   Ex: ssh #{ssh_options}

2. Create 2 files with the following data:
   $ echo '#{hParams[:lorj_account, :data]}' > '#{res[1]}'
   $ echo '#{hParams[:lorj_account, :key]}' > '#{res[2]}'

3. touch the flag file
   $ touch '#{res[3]}'

4. Disconnect.
   $ exit

As soon as those instructions are done, Maestro should go on.
    EOF

    PrcLib.error msg
    loop do
      break if ask("When you are done, type 'DONE'") == 'DONE'
    end
  end
end
