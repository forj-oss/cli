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

# Forj Process solution

require 'git'
require 'fileutils'
require 'find'
require 'digest'
require 'json'
require 'encryptor' # gem install encryptor
require 'base64'
require 'net/ssh'

INFRA_VERSION = '0.0.37'

# Functions for boot - build_forge
class ForjCoreProcess
  def build_forge(sObjectType, hParams)
    # TODO: To be replaced by a migration task at install phase.
    update_keypair_config

    o_forge = forge_get_or_create(sObjectType, hParams)

    # Refresh full data on the server found or created.
    server = controller_get(:server, o_forge[:servers, 'maestro'][:id])
    o_forge[:servers, 'maestro'] = server

    boot_options = boot_keypairs(server)

    # Define the log lines to get and test.
    config.set(:log_lines, 5)

    PrcLib.info("Maestro server '%s' id is '%s'.",
                server[:name], server[:id])
    # Waiting for server to come online before assigning a public IP.

    s_status = :checking
    maestro_create_status(s_status)

    o_address = hParams.refresh[:public_ip, :ObjectData]
    o_address = Lorj::Data.new if o_address.nil?

    s_status = active_server?(server, o_address, boot_options[:keys],
                              boot_options[:coherent], s_status)

    till_server_active(s_status, hParams, o_address, boot_options)

    o_forge = get_forge(sObjectType, config[:instance_name], hParams)

    read_blueprint_implemented(o_forge, hParams)
    o_forge
  end

  def forge_get_or_create(sObjectType, hParams)
    o_forge = process_get(sObjectType, config[:instance_name])
    if o_forge.empty? || o_forge[:servers].length == 0
      PrcLib.high_level_msg("\nBuilding your forge...\n")
      process_create(:internet_server)
      o_forge[:servers, 'maestro'] = hParams.refresh[:server]
    else
      o_forge = load_existing_forge(o_forge, hParams)
    end
    o_forge
  end

  def load_existing_forge(o_forge, hParams)
    PrcLib.high_level_msg("\nChecking your forge...\n")

    o_server = o_forge[:servers, 'maestro']
    if o_server
      query = { :server_id => o_server[:id] }
      register(o_server)
      o_ip = process_query(:public_ip, query,
                           :network_name   => hParams['maestro#network_name'])
      register(o_ip[0]) if o_ip.length > 0
    else
      PrcLib.high_level_msg("\nYour forge exist, without maestro." \
        " Building Maestro...\n")
      process_create(:internet_server)
      o_forge[:servers, 'maestro'] = hParams.refresh[:server]

      PrcLib.high_level_msg("\nBuilding your forge...\n")
    end
    o_forge
  end
end

# Functions for boot - build_forge
class ForjCoreProcess
  def boot_keypairs(server)
    h_keys = process_create(:keypairs)
    keypair = process_get(:keypairs, server[:key_name])

    h_keys = choose_best_kp(h_keys, keypair, server[:name])

    h_keys[:keys] = File.join(h_keys[:keypair_path],
                              h_keys[:private_key_name])

    unless h_keys[:coherent]
      PrcLib.warning("The local keypair '%s' public key and '%s' server's "\
                     "public key are different.\n"\
                     "You won't be able to access it until "\
                     'you get a copy of the key used to create the server.'\
                     "\nPublic key found in the cloud:\n%s",
                     h_keys[:name], server[:name], keypair[:public_key])
      return h_keys
    end

    unless h_keys[:private_key_exist?]
      PrcLib.warning("The local keypair '%s' private key '%s' is not found. "\
                     "You won't be able to access '%s' until you get a copy"\
                     'of the private key use to create the server.'\
                     "\nPublic key found in the cloud:\n%s",
                     h_keys[:keys], server[:name], keypair[:public_key])
    end

    h_keys
  end

  def choose_best_kp(predef_keypair, server_keypair, server_name)
    if server_keypair[:name] != predef_keypair[:name]
      if coherent_keypair?(predef_keypair, server_keypair)
        PrcLib.warning("Server '%s' is using keypair name '%s' instead of the"\
                       " your account keypair name '%s'.\n"\
                       'Your predefined keypair name is compatible with '\
                       'that server. (public key identical), so Forj will use'\
                       " '%s' by default",
                       server_name, server_keypair[:name],
                       server_keypair[:name], server_keypair[:name])
        return predef_keypair
      end
      PrcLib.warning("Server '%s' is using keypair name '%s' instead of the "\
                     "your account keypair name '%s'.\n"\
                     "Forj will try to find and use a local keypair name '%s'"\
                     ' instead.', server_name, server_keypair[:name],
                     predef_keypair[:name], server_keypair[:name])
      return server_keypair
    end
    predef_keypair
  end

  def active_server?(o_server, o_address, private_key_file,
                     keypair_coherent, s_status
                    )
    if o_server[:attrs][:status] == :active
      return :assign_ip if o_address[:public_ip].nil?

      image = server_get_image o_server

      s_msg = format('Your forj Maestro server is up and running and is '\
                     "publically accessible through IP '%s'.\n\n"\
                     "You can connect to '%s' with:\n"\
                     'ssh %s@%s -o StrictHostKeyChecking=no -i ',
                     o_address[:public_ip], o_server[:name],
                     image[:ssh_user], o_address[:public_ip])

      if keypair_coherent
        s_msg += private_key_file
      else
        s_msg += ANSI.red(ANSI.bold('<no valid private key found>')) + "\n\n" +
                 ANSI.bold('Unfortunatelly') + ', Forj was not able to find a '\
                 'valid keypair to connect to your server.' \
                 "\nYou need to fix this issue to gain access to your server."
      end
      PrcLib.info(s_msg)

      o_log = process_get(:server_log, 25)[:attrs][:output]
      if /cloud-init boot finished/ =~ o_log
        s_status = :active
        PrcLib.high_level_msg("\n%s\nThe forge is ready...\n", s_msg)
      else
        PrcLib.high_level_msg("\n%s\nThe forge is still building...\n", s_msg)
        s_status = :cloud_init
      end
    else
      sleep 5
      s_status = :starting
    end
    s_status
  end
end

# Functions for boot - build_forge
class ForjCoreProcess
  # TODO: Rewrite this function to break it for rubocop.
  # rubocop:disable CyclomaticComplexity

  # Function displaying the server status
  def maestro_create_status(sStatus, iCurAct = 4, pending_count = 0)
    s_activity = '/-\\|?'
    if iCurAct < 4
      s_cur_act = 'ACTIVE'
    else
      s_cur_act = format('%s - %d s', ANSI.bold('PENDING'),
                         (pending_count + 1) * 5)
    end

    case sStatus
    when :checking
      PrcLib.state('Checking server status')
    when :starting
      PrcLib.state('STARTING')
    when :assign_ip
      PrcLib.state('%s - %s - Assigning Public IP',
                   s_activity[iCurAct], s_cur_act)
    when :cloud_init
      PrcLib.state('%s - %s - Currently running cloud-init. Be patient.',
                   s_activity[iCurAct], s_cur_act)
    when :nonet
      PrcLib.state('%s - %s - Currently running cloud-init. Be patient.',
                   s_activity[iCurAct], s_cur_act)
    when :restart
      PrcLib.state('RESTARTING - Currently restarting maestro box. Be patient.')
    when :active
      PrcLib.info('Server is active')
    end
  end

  # TODO: Rewrite this function to break it for rubocop.
  # rubocop: disable PerceivedComplexity
  # rubocop: disable Metrics/MethodLength
  # rubocop: disable Metrics/AbcSize

  # Loop until server is active
  def till_server_active(s_status, hParams, o_address, boot_options)
    m_cloud_init_error = []
    i_cur_act = 0
    o_old_log = ''
    pending_count = 0
    server_error = 0
    o_server = hParams.refresh[:server, :ObjectData]
    server_name = o_server[:attrs, :name]

    while s_status != :active
      if i_cur_act == 4
        pending_count += 1
      else
        pending_count = 0
      end
      maestro_create_status(s_status, i_cur_act, pending_count)
      i_cur_act += 1
      i_cur_act = i_cur_act % 4

      if s_status == :restart
        process_delete(:server)
        PrcLib.message("Bad server '%s' removed. Creating a new one...",
                       server_name)
        sleep(5)
        process_create(:internet_server)
        s_status = :starting
        o_server = hParams.refresh[:server, :ObjectData]
        next
      end

      unless o_server.refresh
        sleep(5)
        next
      end

      if o_server[:status] == :error
        if server_error == 1
          PrcLib.fatal(1, 'Server tried to be rebuilt but failed again.')
        end
        server_error = 1
        PrcLib.warning("The creation of server '%s' has currently failed. "\
                       'Trying to rebuild it, once before give up.',
                       server_name)
        s_status = :restart
        next
      end

      if s_status == :starting
        s_status = :assign_ip if o_server[:status] == :active
      elsif s_status == :assign_ip
        s_status = assign_ip_boot(o_address, boot_options, s_status, o_server,
                                  hParams)
      else # analyze the log output
        output_options = { :status => s_status, :error => m_cloud_init_error,
                           :old_log => o_old_log, :cur_act => i_cur_act
        }
        output_options = analyze_log_output(output_options, s_status, hParams)
        s_status = output_options[:status]
        m_cloud_init_error = output_options[:error]
        o_old_log = output_options[:old_log]
        i_cur_act = output_options[:cur_act]

        tb_detect(hParams, o_old_log)
        ca_root_detect(hParams, o_old_log)
        lorj_detect(hParams, o_old_log, boot_options)

        if pending_count == 60
          image = server_get_image o_server
          highlight = ANSI.yellow('-' * 40)
          PrcLib.warning("No more server activity detected.\n"\
                         "#{highlight}\n"\
                         "%s\n"\
                         "#{highlight}\n"\
                         "The server '%s' is not providing any output log for"\
                         " more than 5 minutes.\nPlease review the current "\
                         'output shown below to determine if this is a normal '\
                         "situation.\nYou can connect to the server if you "\
                         "want to.\nTo connect, use:\n"\
                         'ssh %s@%s -o StrictHostKeyChecking=no -i %s',
                         o_old_log, server_name, image[:ssh_user],
                         o_address[:public_ip], boot_options[:keys])
        end
      end
      sleep(5) if s_status != :active
    end
  end

  # Function to get the image data from the server
  #

  def server_get_image(server)
    image = data_objects(:image, :ObjectData)
    return image unless image.nil?

    image = process_get(:image, server[:image_id])

    return Lorj::Data.new if image.nil?

    register(image)
  end

  # rubocop:enable CyclomaticComplexity
  # rubocop:enable PerceivedComplexity
end

# Functions for boot - build_forge
class ForjCoreProcess
  def assign_ip_boot(o_address, boot_options, s_status, o_server, hParams)
    if o_address.empty?
      # To be able to ask for server IP assigned
      query_cache_cleanup(:public_ip)
      o_addresses = process_query(:public_ip, :server_id => o_server[:id])
      if o_addresses.length == 0
        # Assigning Public IP.
        o_address = process_create(:public_ip)
      else
        o_address = o_addresses[0]
      end
    end
    image = hParams.refresh[:image]
    s_msg = <<-END
Public IP for server '%s' is assigned.
Now, as soon as the server respond to the ssh port,
you will be able to get a tail of the build with:
while [ 1 = 1 ]
do
 ssh %s@%s -o StrictHostKeyChecking=no -i %s tail -f /var/log/cloud-init.log
 sleep 5
done
    END
    server_name = o_server.nil? ? 'undefined' : o_server[:name]
    image_user = image.nil? ? 'undefined' : image[:ssh_user]
    public_ip = o_address.nil? ? 'undefined' : o_address[:public_ip]
    keys = boot_options.nil? ? 'undefined' : boot_options[:keys]

    s_msg = format(s_msg, server_name, image_user, public_ip, keys)
    unless boot_options[:coherent]
      s_msg += ANSI.bold("\nUnfortunatelly") + " your current keypair' \
            ' is not usable to connect to your server.\nYou need to fix'   \
            ' this issue to gain access to your server."
    end
    PrcLib.info(s_msg)
    PrcLib.high_level_msg("\n%s\nThe forge is still building...\n", s_msg)
    s_status = :cloud_init
    s_status
  end

  def analyze_log_output(output_options, s_status, hParams)
    o_log = process_get(:server_log, 25)
    return output_options if o_log.nil? || o_log.empty?

    log = o_log[:attrs][:output]
    output_options[:cur_act] = 4 if log == output_options[:old_log]
    output_options[:old_log] = log
    if /cloud-init boot finished/ =~ log
      output_options[:status] = :active
      output_options[:error] = display_boot_moving_error(
        output_options[:error]
      )
    elsif /\[CRITICAL\]/ =~ log
      m_critical = log.scan(/.*\[CRITICAL\].*\n/)
      output_options[:error] = display_boot_critical_error(
        output_options[:error],
        m_critical
      )
    else
      # validate server status
      output_options = analyze_server_status(s_status, log,
                                             output_options, hParams)
    end
    output_options
  end

  def display_boot_critical_error(m_cloud_init_error, m_critical)
    # unless (m_cloud_init_error == m_critical)
    return if m_cloud_init_error == m_critical
    s_reported = o_log.clone
    s_reported['CRITICAL'] = ANSI.bold('CRITICAL')
    PrcLib.error("cloud-init error detected:\n-----\n%s\n-----\n" \
                 'Please connect to the box to decide what you' \
                 ' need to do.', s_reported)
    m_cloud_init_error = m_critical
    m_cloud_init_error
    # end
  end

  def display_boot_moving_error(m_cloud_init_error)
    if m_cloud_init_error != []
      PrcLib.high_level_msg(
        'Critical error cleared. Cloud-init seems moving...'
      )
      PrcLib.info('Critical error cleared. Cloud-init seems moving...')
      m_cloud_init_error = []
    end
    m_cloud_init_error
  end
end

# Functions for boot - build_forge
class ForjCoreProcess
  def analyze_server_status(s_status, o_log, output_options, _hParams)
    if s_status == :cloud_init &&
       /cloud-init-nonet gave up waiting for a network device/ =~ o_log
      # Valid for ubuntu image 12.04
      PrcLib.warning(
        'Cloud-init has gave up to configure the network. waiting...'
      )
      output_options[:status] = :nonet
    elsif s_status == :nonet &&
          /Booting system without full network configuration/ =~ o_log
      # Valid for ubuntu image 12.04
      PrcLib.warning(
        'forj has detected an issue to bring up your maestro server.' \
                ' Removing it and re-creating a new one. please be patient...'
      )
      output_options[:status] = :restart
    elsif s_status == :restart
      process_delete(:server)
      process_create(:internet_server)
      output_options[:status] = :starting
    end
    output_options
  end

  def read_blueprint_implemented(o_forge, params)
    o_address = params[:public_ip, :ObjectData]
    blueprint = params[:blueprint]
    instance_name = params[:instance_name]
    s_msg = format(
      "Your Forge '%s' is ready and accessible from" \
      " IP #{o_address[:public_ip]}.",
      instance_name
    )
    # TODO: read the blueprint/layout to identify which services
    # are implemented and can be accessible.
    if blueprint
      s_msg += format(
        "\n" + 'Maestro has implemented the following server(s) for your' \
          " blueprint '%s':",
        blueprint
      )
      server_options = display_servers_with_ip(o_forge, s_msg)
      s_msg += server_options[:message]
      i_count = server_options[:count]
      if i_count > 0
        s_msg += format("\n%d server(s) identified.\n", i_count)
      else
        s_msg = 'No servers found except maestro'
        PrcLib.warning('Something went wrong, while creating nodes for '\
                       "blueprint '%s'. check maestro logs "\
                       "(Usually /var/log/cloud-init.log).\n"\
                       'Consider Lorj Gardener by setting :default/:lorj: '\
                       '[true/false] in /opt/config/lorj/config.yaml if puppet'\
                       ' returned some strange ruby error.', blueprint)
      end
    else
      s_msg += "\nMaestro has NOT implemented any servers, because you did" \
        ' not provided a blueprint. Connect to Maestro, and ask Maestro to' \
        ' implement any kind of blueprint you need. (Feature currently' \
        ' under development)'
    end
    PrcLib.info(s_msg)
    PrcLib.high_level_msg("\n%s\nEnjoy!\n", s_msg)
  end

  def display_servers_with_ip(o_forge, s_msg)
    i_count = 0
    o_forge[:servers].each do |_type, server|
      next if /^maestro\./ =~ server[:name]
      register(server)
      o_ip = process_query(:public_ip, :server_id => server[:id])
      if o_ip.length == 0
        s_msg += format("\n- %s (No public IP)", server[:name])
      else
        s_msg += format("\n- %s (%s)", server[:name], o_ip[0][:public_ip])
      end
      i_count += 1
    end
    server_options = { :message => s_msg, :count => i_count }
    server_options
  end
end

# Functions for boot - build_metadata
class ForjCoreProcess
  def load_encoded_key
    key_file = File.join(PrcLib.pdata_path, '.key')
    if !File.exist?(key_file)
      # Need to create a random key.
      entr = {
        :key => rand(36**10).to_s(36),
        :salt => Time.now.to_i.to_s,
        :iv => Base64.strict_encode64(
          OpenSSL::Cipher::Cipher.new('aes-256-cbc').random_iv
        )
      }

      PrcLib.debug("Writing '%s' key file", key_file)
      File.open(key_file, 'w') do |out|
        out.write(Base64.encode64(entr.to_yaml))
      end
    else
      PrcLib.debug("Loading '%s' key file", key_file)
      encoded_key = IO.read(key_file)
      entr = YAML.load(Base64.decode64(encoded_key))
    end
    entr
  end

  def decrypt_key(os_enckey, entr)
    begin
      os_key = Encryptor.decrypt(
        :value => Base64.strict_decode64(os_enckey),
        :key => entr[:key],
        :iv => Base64.strict_decode64(entr[:iv]),
        :salt => entr[:salt]
      )
    rescue
      raise 'Unable to decript your password. You need to re-execute setup.'
    end
    os_key
  end

  def load_hpcloud(hParams, os_key)
    hpcloud_priv = nil
    IO.popen('gzip -c', 'r+') do|pipe|
      data = <<-END
HPCLOUD_OS_USER='#{hParams['gardener#os_user']}'
HPCLOUD_OS_KEY='#{os_key}'
DNS_KEY='#{hParams[:'credentials#account_id']}'
DNS_SECRET='#{hParams['credentials#account_key']}'
      END
      pipe.puts(data)
      pipe.close_write
      hpcloud_priv = pipe.read
    end
    hpcloud_priv
  end

  def load_h_meta(hParams, hpcloud_priv)
    h_meta = {
      'flavor_name' => hParams['maestro#bp_flavor'],
      'cdksite' => hParams[:server_name],
      'cdkdomain' => hParams['dns#domain_name'],
      'eroip' => '127.0.0.1',
      'erosite' => hParams[:server_name],
      'erodomain' => hParams['dns#domain_name'],
      'gitbranch' => hParams['maestro#branch'],
      'security_groups' => hParams['maestro#security_group'],
      'tenant_name' => hParams['maestro#tenant_name'],
      'network_name' => hParams['maestro#network_name'],
      'hpcloud_os_region' => hParams['services#compute'],
      'PUPPET_DEBUG' => 'True',
      'image_name' => hParams['maestro#image_name'],
      'key_name' => hParams['credentials#keypair_name'],
      # The following is used by gardener
      # Remove pad
      'hpcloud_priv' => Base64.strict_encode64(hpcloud_priv).gsub('=', ''),
      'compute_os_auth_url' => hParams['gardener#os_auth_uri']
    }

    if hParams['dns#dns_service']
      h_meta['dns_zone'] = hParams[:'dns#dns_service']
      h_meta['dns_tenantid'] = hParams['dns#dns_tenant_id']
      h_meta['dns_auth_url'] = hParams['credentials#auth_uri']
    end
    # If requested by user, ask Maestro to instantiate a blueprint.
    h_meta['blueprint'] = hParams[:blueprint] if hParams[:blueprint]

    # Add init additionnal git clone steps.
    h_meta['repos'] = hParams[:repos] if hParams[:repos]
    # Add init bootstrap additionnal steps
    h_meta['bootstrap'] = hParams[:bootstrap] if hParams[:bootstrap]

    if hParams[:extra_metadata]
      hParams[:extra_metadata].split(/,/).each do |kv|
        k, v = kv.split(/=/)
        h_meta[k] = v
      end
    end

    tb_metadata(hParams, h_meta)
    ca_root_metadata(hParams, h_meta)
    proxy_metadata(hParams, h_meta)
    lorj_metadata(hParams, h_meta)

    h_meta
  end

  def build_metadata(sObjectType, hParams)
    entr = load_encoded_key

    os_enckey = hParams['gardener#os_enckey']

    os_key = decrypt_key(os_enckey, entr)

    hpcloud_priv = load_hpcloud(hParams, os_key)

    h_meta = load_h_meta(hParams, hpcloud_priv)

    config.set(:meta_data, h_meta) # Used by :server object

    h_meta_printable = h_meta.clone
    h_meta_printable['hpcloud_priv'] = 'XXX - data hidden - XXX'
    m_print = ''
    max_key = 0
    h_meta_printable.keys.each { |k| max_key = [max_key, k.length].max }
    h_meta_printable.keys.sort.each do |k|
      m_print += format("%-#{max_key}s : %s\n",
                        k, ANSI.bold(h_meta_printable[k]))
    end
    PrcLib.info("Metadata set:\n%s", m_print)

    o_meta_data = register(h_meta, sObjectType)
    o_meta_data[:meta_data] = h_meta

    o_meta_data
  end
end

# Functions for boot - clone_or_use_maestro_repo
class ForjCoreProcess
  def clone_maestro_repo(maestro_url, path_maestro, config)
    PrcLib.state("Cloning maestro repo from '%s' to '%s'",
                 maestro_url, File.join(path_maestro, 'maestro'))
    if File.directory?(path_maestro)
      if File.directory?(File.join(path_maestro, 'maestro'))
        FileUtils.rm_r File.join(path_maestro, 'maestro')
      end
    end
    git = Git.clone(maestro_url, 'maestro', :path => path_maestro)
    git.checkout(config[:branch]) if config[:branch] != 'master'
    PrcLib.info("Maestro repo '%s' cloned on branch '%s'",
                File.join(path_maestro, 'maestro'), config[:branch])
  end

  def clone_or_use_maestro_repo(sObjectType, hParams)
    maestro_url = hParams[:maestro_url]
    maestro_repo = File.expand_path(
      hParams[:maestro_repo]
    ) unless hParams[:maestro_repo].nil?
    path_maestro = File.expand_path('~/.forj/')
    h_result = {}

    begin
      if maestro_repo && File.directory?(maestro_repo)
        PrcLib.info("Using maestro repo '%s'", maestro_repo)
        h_result[:maestro_repo] = maestro_repo
      else
        h_result[:maestro_repo] = File.join(path_maestro, 'maestro')
        clone_maestro_repo(maestro_url, path_maestro, config)
      end
   rescue => e
     PrcLib.error("Error while cloning the repo from %s\n%s\n%s"\
                  "\nIf this error persist you could clone the repo manually"\
                  " in '%s'",
                  maestro_url, e.message, e.backtrace.join("\n"),
                  h_result[:maestro_repo])
    end
    o_maestro = register(h_result, sObjectType)
    o_maestro[:maestro_repo] = h_result[:maestro_repo]
    o_maestro[:maestro_repo_exist?] = File.directory?(h_result[:maestro_repo])
    o_maestro
  end
end

# Functions for boot - create_or_use_infra
class ForjCoreProcess
  def create_or_use_infra(sObjectType, hParams)
    infra = File.expand_path(hParams[:infra_repo])
    maestro_repo = hParams[:maestro_repository, :maestro_repo]
    # branch = hParams[:branch]
    dest_cloud_init = File.join(infra, 'cloud-init')
    template = File.join(maestro_repo, 'templates', 'infra')
    cloud_init = File.join(template, 'cloud-init')

    h_infra = { :infra_repo => dest_cloud_init }

    PrcLib.ensure_dir_exists(dest_cloud_init)

    b_rebuild_infra = infra_is_original?(infra, maestro_repo)

    if b_rebuild_infra
      PrcLib.state("Building your infra workspace in '%s'", infra)

      if File.directory?(cloud_init)
        PrcLib.debug("Copying recursively '%s' to '%s'", cloud_init, infra)
        FileUtils.copy_entry(cloud_init, dest_cloud_init)
      end

      file_ver = File.join(infra, 'forj-cli.ver')
      File.write(file_ver, INFRA_VERSION)
      infra_cleanup(infra, maestro_repo)
      PrcLib.info("The infra workspace '%s' has been built from maestro" \
                  ' predefined files.', infra)
    else
      PrcLib.info("Re-using your infra... in '%s'", infra)
    end

    o_infra = register(h_infra, sObjectType)
    o_infra[:infra_repo] = h_infra[:infra_repo]
    o_infra
  end

  # check from the list of files under maestro control
  # Do cleanup for files that disappeared.
  #
  # Then it update the hidden maestro controlled file.
  #
  def infra_cleanup(infra_dir, maestro_dir)
    md5_list_file = File.join(infra_dir, '.maestro_original.yaml')

    md5_list = {}
    md5_list = YAML.load_file(md5_list_file) if File.exist?(md5_list_file)

    cur_md5_list = {}

    template_dir = File.join(maestro_dir, 'templates', 'infra')
    cloud_init_dir = File.join(infra_dir, 'cloud-init')

    load_infra(template_dir, cloud_init_dir, cur_md5_list)

    md5_list.each do |path, _md5|
      if cur_md5_list.key?(path)
        md5_list[path] = cur_md5_list[path]
      else
        begin
          File.delete(File.join(template_dir, path))
        rescue
          PrcLib.debug("'%s' infra file has already been removed.", path)
        else
          PrcLib.debug("'%s' infra file has been removed.", path)
        end
        md5_list.delete(path)
      end
    end
    infra_save_md5(md5_list_file, md5_list)
  end

  def load_infra(template, dest_cloud_init, md5_list, is_original = false)
    # We are taking care on bootstrap files only.
    cloud_init_path = File.join(template, 'cloud-init')
    return is_original unless File.directory?(cloud_init_path)

    Find.find(cloud_init_path) do |path|
      next if File.directory?(path)
      file_original = true # By default we consider it to be original
      s_maestro_rel_path = path.clone
      s_maestro_rel_path[cloud_init_path + '/'] = ''
      s_infra_path = File.join(dest_cloud_init, s_maestro_rel_path)
      if File.exist?(s_infra_path)
        md5_file = Digest::MD5.file(s_infra_path).hexdigest
        if md5_list.key?(s_maestro_rel_path) &&
           md5_list.rh_get(s_maestro_rel_path, :md5) != md5_file
          file_original = false
          PrcLib.info("'%s' infra file has changed from original template" \
                      ' in maestro.', s_infra_path)
        else
          PrcLib.debug("'%s' infra file has not been updated.", s_infra_path)
        end
      end
      md5_file = Digest::MD5.file(path).hexdigest
      md5_list[s_maestro_rel_path] = { :md5 => md5_file,
                                       :original => file_original }
      is_original &= false
    end
    is_original
  end

  def infra_save_md5(md5_list_file, data)
    File.open(md5_list_file, 'w') { |out| YAML.dump(data, out) }
  rescue => e
    PrcLib.error("File '%s': %s\n%s", md5_list_file, e.message,
                 e.backtrace.join("\n"))
  end
end

# Functions for boot - create_or_use_infra
class ForjCoreProcess
  # Function which compare directories from maestro templates to infra.
  #
  # * *return*:
  #   - true if the infra repository file contains some files managed by maestro
  #     which has not been updated manually.
  #   - false otherwise.
  def infra_is_original?(infra_dir, maestro_dir)
    dest_cloud_init = File.join(infra_dir, 'cloud-init')
    template = File.join(maestro_dir, 'templates', 'infra')
    return false unless File.exist?(template)
    s_md5_list = File.join(infra_dir, '.maestro_original.yaml')
    b_result = true
    md5_list = {}
    if File.exist?(s_md5_list)
      begin
        md5_list = YAML.load_file(s_md5_list)
     rescue
       PrcLib.error("Unable to load valid Original files list '%s'. " \
                    "Your infra workspace won't be migrated, until fixed.",
                    s_md5_list)
       b_result = false
      end
      unless md5_list
        md5_list = {}
        b_result = false
      end
    end
    b_result = load_infra(template, dest_cloud_init, md5_list, b_result)
    if b_result
      PrcLib.debug(
        'No original files found has been updated. Infra workspace' \
          ' can be updated/created if needed.'
      )
    else
      PrcLib.warning(
        'At least, one file has been updated. Infra workspace' \
          " won't be updated by forj cli."
      )
    end
    b_result
  end

  def infra_rebuild(infra_dir)
    return false unless File.exist?(infra_dir)

    file_ver = File.join(infra_dir, 'forj-cli.ver')
    forj_infra_version = nil
    forj_infra_version = File.read(file_ver) if File.exist?(file_ver)

    if forj_infra_version.nil? || forj_infra_version == ''
      # Prior version 37
      return(old_infra_data_update(oConfig, '0.0.36', infra_dir))
    elsif Gem::Version.new(forj_infra_version) < Gem::Version.new(INFRA_VERSION)
      return(old_infra_data_update(oConfig, forj_infra_version, infra_dir))
    end
  end

  def update_build_env(b_update, tag, y_dns, m_obj)
    if !b_update.nil? && b_update
      PrcLib.debug("Saved: '%s' = '%s'", m_obj[1], m_obj[2])
      y_dns.rh_set(m_obj[2], tag)
    end
    b_update
  end

  def update_build_env?(b_update, tag, y_dns, m_obj)
    if tag && m_obj[2]
      if b_update.nil? &&
         y_dns.rh_get(tag) && y_dns.rh_get(tag) != m_obj[2]
        PrcLib.message('Your account setup is different than'\
                ' build env.')
        PrcLib.message('We suggest you to update your account'\
                ' setup with data from your build env.')
        b_update = agree('Do you want to update your setup with'\
                ' those build environment data?')
      end
      b_update = update_build_env(b_update, tag, y_dns, m_obj)
    end
    b_update
  end

  def open_build_env(build_env, tags, y_dns)
    b_update = nil

    File.open(build_env) do |f|
      line = f.readline
      next if line.match(/^(SET_[A-Z_]+)=["'](.*)["'].*$/).nil?
      # f.each_line do |line|
      m_obj = line.match(/^(SET_[A-Z_]+)=["'](.*)["'].*$/)
      # if m_obj
      PrcLib.debug("Reviewing detected '%s' tag", m_obj[1])
      tag = (tags[m_obj[1]] ? tags[m_obj[1]] : nil)
      b_update = update_build_env(b_update, tag, y_dns, m_obj)
      # end
      # end
    end
  rescue => e
    PrcLib.fatal(1, "Failed to open the build environment file '%s'",
                 build_env, e)
  end
end

# Functions for boot - create_or_use_infra
class ForjCoreProcess
  def old_infra_data_update(oConfig, version, infra_dir)
    PrcLib.info('Migrating your local infra repo (%s) to the latest version.',
                version)
    # Be default migration is successful. No need to rebuild it.
    b_rebuild = false
    case version
    when '0.0.36'
      # Moving from 0.0.36 or less to 0.0.37 or higher.
      # SET_COMPUTE="{SET_COMPUTE!}" => Setting for Compute.
      # ignored. Coming from HPC
      # SET_TENANT_NAME="{SET_TENANT_NAME!}" => Setting for Compute.
      # ignored. Need to query HPC from current Tenant ID

      # SET_DNS_TENANTID="{SET_DNS_TENANTID!}" => Setting for DNS.
      # meta = dns_tenantid
      #  ==> :forj_accounts, s_account_name, :dns, :tenant_id

      # SET_DNS_ZONE="{SET_DNS_ZONE!}" => Setting for DNS. meta = dns_zone
      # ==> :forj_accounts, s_account_name, :dns, :service

      # SET_DOMAIN="{SET_DOMAIN!}" => Setting for Maestro (required)
      # and DNS if enabled.
      # ==> :forj_accounts, s_account_name, :dns, :domain_name
      y_dns = {}
      y_dns = oConfig[:dns] if oConfig.exist?(:dns)

      Dir.foreach(infra_dir) do |file|
        next unless /^maestro\.box\..*\.env$/ =~ file
        build_env = File.join(infra_dir, file)
        PrcLib.debug("Reading data from '%s'", build_env)
        tags = { 'SET_DNS_TENANTID' => :tenant_id,
                 'SET_DNS_ZONE' => :service,
                 'SET_DOMAIN' => :domain_name
        }

        open_build_env(build_env, tags, y_dns)
      end
      file_ver = File.join(infra_dir, 'forj-cli.ver')
      File.write(file_ver, INFRA_VERSION)
      oConfig[:dns] = y_dns
      oConfig.ac_save
      return b_rebuild
    end
  end
end

# Functions for boot - build_userdata
class ForjCoreProcess
  def run_userdata_cmd(cmd, bootstrap, mime)
    # TODO: Replace shell script call to ruby functions
    if PrcLib.core_level >= 1
      cmd += " >> #{PrcLib.log_file}"
    else
      cmd += " | tee -a #{PrcLib.log_file}"
    end
    fail ForjError.new, "#{bootstrap} script file is" \
      ' not found.' unless File.exist?(bootstrap)
    PrcLib.debug("Running '%s'", cmd)
    Kernel.system(cmd)

    fail ForjError.new, format(
      "mime file '%s' not found.",
      mime
    ) unless File.exist?(mime)
  end

  def build_userdata(sObjectType, hParams)
    # get the paths for maestro and infra repositories
    # maestro_path = hParams[:maestro_repository].values
    # infra_path = hParams[:infra_repository].values

    # concatenate the paths for boothook and cloud_config files
    # ~ build_dir = File.expand_path(File.join($FORJ_DATA_PATH, '.build'))
    # ~ boothook = File.join(maestro_path, 'build', 'bin', 'build-tools')
    # ~ cloud_config = File.join(maestro_path, 'build', 'maestro')

    mime = File.join(
      Forj.build_path,
      format('userdata.mime.%s', rand(36**5).to_s(36))
    )

    unless hParams[:maestro_repository, :maestro_repo_exist?]
      PrcLib.fatal(1, "Maestro repository doesn't exist. This is required for "\
                      "cloud_init user_data build. Check why '%s' "\
                      "doesn't exist.",
                   hParams[:maestro_repository, :maestro_repo])
    end

    meta_data = JSON.generate(hParams[:metadata, :meta_data])

    build_tmpl_dir = File.expand_path(File.join(LIB_PATH, 'build_tmpl'))

    PrcLib.state("Preparing user_data - file '%s'", mime)
    # generate boot_*.sh
    mime_cmd = "#{build_tmpl_dir}/write-mime-multipart.py"
    bootstrap = "#{build_tmpl_dir}/bootstrap_build.sh"

    cmd = format(
      "%s '%s' '%s' '%s' '%s' '%s' '%s' '%s'",
      bootstrap, # script
      # $1 = Forj data base dir
      PrcLib.data_path,
      # $2 = Maestro repository dir
      hParams[:maestro_repository, :maestro_repo],
      # $3 = Bootstrap directories
      hParams[:infra_repository, :infra_repo] + ' ' +
      config.get(:bootstrap_dirs, ''),
      # $4 = Bootstrap extra directory
      config[:bootstrap_extra_dir],
      # $5 = meta_data (string)
      meta_data,
      # $6: mime script file to execute.
      mime_cmd,
      # $7: mime file generated.
      mime
    )

    run_userdata_cmd(cmd, bootstrap, mime)

    begin
      user_data = File.read(mime)
    rescue => e
      PrcLib.fatal(1, e.message)
    end
    if PrcLib.core_level < 5
      File.delete(mime)
    else
      Lorj.debug(5, "user_data temp file '%s' kept", mime)
    end

    config[:user_data] = user_data

    o_user_data = register(hParams, sObjectType)
    o_user_data[:user_data] = user_data
    o_user_data[:user_data_encoded] = Base64.strict_encode64(user_data)
    o_user_data[:mime] = mime
    PrcLib.info("user_data prepared. File: '%s'", mime)
    o_user_data
  end
end

# Functions for setup
class ForjCoreProcess
  def create_directory(base_dir)
    # unless File.directory?(base_dir)
    return true if FIle.directory?(base_dir)
    if agree(
      format("'%s' doesn't exist. Do you want to create it?", base_dir)
    )
      PrcLib.ensure_dir_exists(base_dir)
      # true
    else
      return false
    end
    # end
  end

  # Check files existence
  def forj_check_keypairs_files(input_pathbase)
    key_name = config.get(:keypair_name)

    keypair_path = File.expand_path(File.dirname(input_pathbase))
    keypair_base = File.expand_path(File.basename(input_pathbase))
    keys_entered = keypair_detect(key_name, keypair_path, keypair_base)

    if !keys_entered[:private_key_exist?] && !keys_entered[:public_key_exist?]
      if agree('The key you entered was not found. Do you want to create' \
        ' this one?')
        base_dir = keys_entered[:keypair_path]
        return create_directory(base_dir)
      else
        return false
      end
    end
    true
  end

  # Function to identify if the keypair name has already been imported.
  # If so, we can't change the original files used to import it.
  # The script will ask for another keypair_name.
  #
  # It will loop until keyname is new or until files originally used
  # is identical.
  def check_about_imported_key(setup_keys, key_name)
    loop do
      keys_imported = nil
      if config.local_exist?(key_name.to_sym, :imported_keys)
        keys_imported = keypair_detect(key_name,
                                       config.local_get(key_name.to_sym,
                                                        :imported_keys))
      end

      return setup_keys if keys_imported.nil?

      unless keys_imported[:private_key_exist?] ||
             keys_imported[:public_key_exist?]
        PrcLib.warning("The local keypair '%s' imported files do not exist "\
                       'anymore. Removed from imported_keys.', key_name)
        local_del(key_name.to_sym, :imported_keys)
        break
      end

      setup_keybase = File.join(setup_keys[:keypair_path],
                                setup_keys[:key_basename])
      imported_keybase = File.join(keys_imported[:keypair_path],
                                   keys_imported[:key_basename])

      break if setup_keybase == imported_keybase

      PrcLib.warning("You entered a keypair base file '%s' for keypair name "\
                     "'%s'. Originally, this keypair name was created from "\
                     "'%s' instead.\n"\
                     'To not overwrite it, we recommend you'\
                     ' to choose a different keypair name.',
                     setup_keybase, key_name, imported_keybase)
      key_name = _keypair_files_ask(key_name)
      config.set(:key_name, key_name)

      setup_keys = keypair_detect(key_name,
                                  setup_keys[:keypair_path],
                                  setup_keys[:key_basename])
    end
    setup_keys
  end

  # Function to change the keypair name, as already used.
  def _keypair_files_ask(key_name)
    new_key_name = key_name
    s_msg = 'Please, provide a different keypair base file:'
    while key_name == new_key_name
      new_key_name = ask(s_msg) do |q|
        q.validate = /.+/
      end
      new_key_name = new_key_name.to_s
      s_msg = 'Incorrect. You have to choose a keypair base file different'\
              " than '#{key_name}'. If you want to interrupt, press Ctrl-C."\
              "\nSo, please, provide a different keypair"\
              ' name:' if key_name == new_key_name
    end
    new_key_name
  end

  def create_keys_automatically(keys, private_key_file)
    return if keys[:private_key_exist?]
    unless File.exist?(private_key_file)
      # Need to create a key. ask if we need so.
      PrcLib.message("The private key file attached to keypair named '%s' is "\
                     'not found. Running ssh-keygen to create it.',
                     keys[:keypair_name])
      PrcLib.ensure_dir_exists(File.dirname(private_key_file))
      command = format('ssh-keygen -t rsa -f %s', private_key_file)
      PrcLib.debug(format("Executing '%s'", command))
      system(command)
    end
    return if File.exist?(private_key_file)
    PrcLib.fatal(1, 'ssh-keygen did not created your key pairs. Aborting.'\
                   ' Please review errors in ~/.forj/forj.log')
  end
end

# Functions for setup
class ForjCoreProcess
  # Import the keypair base files setup by user in forj keypair files.
  #
  # This function is can be executed only if we copy files to internal
  # forj keypair storage. Otherwise this update is ignored.
  def save_sequences(private_key_file, forj_private_key_file,
                     public_key_file, forj_public_key_file, key_name
                    )
    PrcLib.info('Importing key pair to FORJ keypairs list.')

    FileUtils.copy(private_key_file, forj_private_key_file)
    FileUtils.copy(public_key_file, forj_public_key_file)
    # Attaching this keypair to the account
    config.set(:keypair_name, key_name, :name => 'account')
    config.local_set(key_name.to_sym, private_key_file, :imported_keys)
  end

  # Update the forj keypair base files copy from the original base files.
  #
  # This function is can be executed only if we copy files to internal
  # forj keypair storage. Otherwise this update is ignored.
  def save_md5(private_key_file, forj_private_key_file,
               public_key_file, forj_public_key_file
              )
    # Checking source/dest files content
    if Digest::MD5.file(private_key_file).hexdigest !=
       Digest::MD5.file(forj_private_key_file).hexdigest
      PrcLib.info(
        'Updating private key keypair piece to FORJ keypairs list.'
      )
      FileUtils.copy(private_key_file, forj_private_key_file)
    else
      PrcLib.info('Private key keypair up to date.')
    end
    if Digest::MD5.file(public_key_file).hexdigest !=
       Digest::MD5.file(forj_public_key_file).hexdigest
      PrcLib.info(
        'Updating public key keypair piece to FORJ keypairs list.'
      )
      FileUtils.copy(public_key_file, forj_public_key_file)
    else
      PrcLib.info('Public key keypair up to date.')
    end
  end
end

# Functions for setup
class ForjCoreProcess
  def save_internal_key(keys)
    # Saving internal copy of private key file for forj use.
    config.set(:keypair_base, keys[:keypair_name], :name => 'account')
    PrcLib.info("Configured forj keypair '%s' with '%s'",
                keys[:keypair_name],
                File.join(keys[:keypair_path], keys[:key_basename])
               )
  end

  # keypair_files post setup
  #
  # This function will get the keypair_files setup by user and it will:
  #
  # * In case keypair already exist, check if imported files is identical.
  # * Create SSH keys if missing (ssh-keygen - create_keys_automatically)
  # * exit if :keypair_change is not set to the internal forj dir.
  # * For new keys, copy new files and keep the original files import place.
  # * For existing keys, update them from their original places (imported from)
  # * done
  def forj_setup_keypairs_files
    keys = check_setup_keypair

    private_key_file = File.join(keys[:keypair_path], keys[:private_key_name])
    public_key_file = File.join(keys[:keypair_path], keys[:public_key_name])

    # Creation sequences
    create_keys_automatically(keys, private_key_file)

    if Forj.keypairs_path != config[:keypair_path]
      # Do not save in a config keypair_path not managed by forj.
      save_internal_key(keys)
      return true
    end

    forj_private_key_file = File.join(Forj.keypairs_path, keys[:keypair_name])
    forj_public_key_file = File.join(Forj.keypairs_path,
                                     keys[:keypair_name] + '.pub')

    # Saving sequences
    if !File.exist?(forj_private_key_file) || !File.exist?(forj_public_key_file)
      save_sequences(private_key_file, forj_private_key_file,
                     public_key_file, forj_public_key_file, keys[:keypair_name])
    else
      save_md5(private_key_file, forj_private_key_file,
               public_key_file, forj_public_key_file)
    end

    save_internal_key(keys)
    true # forj_setup_keypairs_files successful
  end

  def check_setup_keypair
    key_name = config[:keypair_name]
    setup_keypair_path = File.expand_path(File.dirname(config[:keypair_files]))
    setup_keypair_base = File.basename(config[:keypair_files])

    setup_keys = keypair_detect(key_name, setup_keypair_path,
                                setup_keypair_base)

    # Request different keypair_name, if exist and already imported from another
    # :keypair_files
    if config[:keypair_path] == Forj.keypairs_path
      check_about_imported_key(setup_keys, key_name)
    else
      setup_keys
    end
  end

  # TODO: Change this by a migration function called at install time.

  # Function to convert unclear data structure keypair_path, splitted.
  # Update config with keypair_base and keypair_path - forj 1.0.8
  #
  # * split it in path and base.
  # * Fix existing config about path&base (update_keypair_config)
  # * save it in account file respectively as :keypair_path and :keypair_base
  #
  # Used in keypair_name pre-step at setup time.
  # return true to not skip the data.
  #
  def update_keypair_config(_ = nil)
    %w(local account).each do |config_name|
      next if config.latest_version?(config_name)
      keypair_path = config.get(:keypair_path, nil, :name => config_name)

      unless keypair_path.nil?
        options = { :name => config_name }
        options.merge!(:section => :default) if config_name == 'local'
        config.set(:keypair_base, File.basename(keypair_path), options)
        config.set(:keypair_path, File.dirname(keypair_path), options)
      end
      config.version_set(config_name, Forj.file_version)
    end
    true
  end

  def forj_dns_settings
    config[:dns_settings] = false

    return true unless forj_dns_supported?

    s_ask = 'Optionally, you can ask Maestro to use/manage a domain name on' \
      " your cloud. It requires your DNS cloud service to be enabled.\nDo" \
      ' you want to configure it?'
    config[:dns_settings] = agree(s_ask)
    true
  end

  def forj_dns_settings?(key)
    # Return true to ask the question. false otherwise
    unless config[:dns_settings]
      section, key = Lorj.data.first_section(key)
      config.del(key, :name => 'account', :section => section)
      return false # Do not ask
    end
    true
  end

  def forj_dns_supported?
    unless config[:provider] == 'hpcloud'
      PrcLib.message("maestro running under '%s' provider currently do "\
                     "support DNS setting.\n", config.get(:provider))
      config[:dns_settings] = false
      return false # Do not ask
    end
    true
  end
end

# Functions for setup
class ForjCoreProcess
  def setup_tenant_name
    # TODO: To re-introduce with a Controller call instead.
    o_ssl_error = SSLErrorMgt.new # Retry object
    PrcLib.debug('Getting tenants from hpcloud cli libraries')
    begin
      tenants = Connection.instance.tenants(@sAccountName)
   rescue => e
     retry unless o_ssl_error.ErrorDetected(e.message, e.backtrace, e)
     PrcLib.fatal(1, 'Network: Unable to connect.')
    end
    tenant_id = @oConfig.ExtraGet(:hpc_accounts, @sAccountName,
                                  :credentials).rh_get(:tenant_id)
    tenant_name = nil
    tenants.each do |elem|
      tenant_name = elem['name'] if elem['id'] == tenant_id
    end
    if tenant_name
      PrcLib.debug("Tenant ID '%s': '%s' found.", tenant_id, tenant_name)
      @hAccountData.rh_set(tenant_name, :maestro, :tenant_name)
    else
      PrcLib.error("Unable to find the tenant Name for '%s' ID.", tenant_id)
    end
    @oConfig.set('tenants', tenants)
  end

  # post process after asking keypair name
  # return true    go to next step
  # return false   go back to ask keypair name again
  def forj_check_cloud_keypair
    key_name = config[:keypair_name]
    return true if key_name.nil?
    config[:key_cloud_coherence] = false
    cloud_key = process_get(:keypairs, key_name)
    register(cloud_key)
    if !cloud_key.empty?
      if cloud_key[:coherent]
        config[:key_cloud_coherence] = true
        return true
      end
    else
      return true
    end
    keypair_display(cloud_key)

    return true unless cloud_key[:public_key_exist?]

    PrcLib.message("You need to create a new keypair instead of '%s'"\
                   'or quit the setup to get the original key and retry.',
                   key_name)
    s_ask = 'Do you want to create new keypair?'

    PrcLib.fatal(1, 'Quitting setup per your request.') unless agree(s_ask)
    false
  end

  # pre process before asking keypair files
  # return true  continue to ask keypair files
  # return false skip asking keypair files
  def forj_cloud_keypair_coherent?(_keypair_files)
    return true unless config.exist?(:key_cloud_coherence)

    keypair = data_objects(:keypairs)

    return true unless keypair.nil? || keypair[:private_key_exist?]

    if config[:key_cloud_coherence]
      PrcLib.message('Your local ssh keypair is detected ' \
                     'and valid to access the box.')
      return false
    end
    match = ANSI.bold(format('matching %s keypair name previously set',
                             ANSI.red(config[:keypair_name])))
    desc = 'the base keypair file name (with absolute path) ' + match

    Lorj.data.set(:sections, :credentials, :keypair_files,
                  { :desc => desc }, 'setup')
    true
  end
end

# Funtions for get
class ForjCoreProcess
  def get_forge(sCloudObj, sForgeId, _hParams)
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
    o_forge
  end
end

# Funtions for destroy
class ForjCoreProcess
  def delete_forge(_sCloudObj, hParams)
    PrcLib.state('Destroying server(s) of your forge')

    forge_serverid = hParams[:forge_server]

    o_forge = hParams[:forge]

    o_forge[:servers].each do|_type, server|
      next if forge_serverid && forge_serverid != server[:id]
      register(server)
      PrcLib.state("Destroying server '%s - %s'", server[:name], server[:id])
      process_delete(:server)
    end
    if forge_serverid.nil?
      PrcLib.high_level_msg("The forge '%s' has been destroyed. (all servers" \
                            " linked to the forge)\n", o_forge[:name])
    else
      PrcLib.high_level_msg("Server(s) selected in the forge '%s' has been"\
                            " removed.\n", o_forge[:name])
    end
  end
end

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
