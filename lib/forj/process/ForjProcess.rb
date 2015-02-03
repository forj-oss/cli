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
    forge_exist?(sObjectType)

    o_server = data_objects(:server, :ObjectData)

    boot_options = boot_keypairs(o_server)

    # Define the log lines to get and test.
    config.set(:log_lines, 5)

    PrcLib.info("Maestro server '%s' id is '%s'.",
                o_server[:name], o_server[:id])
    # Waiting for server to come online before assigning a public IP.

    s_status = :checking
    maestro_create_status(s_status)

    o_address = data_objects(:public_ip, :ObjectData)

    s_status = active_server?(o_server, o_address, boot_options[:keys],
                              boot_options[:coherent], s_status
    )

    till_server_active(s_status, o_server, o_address, boot_options)

    o_forge = get_forge(sObjectType, config[:instance_name], hParams)

    read_blueprint_implemented(o_forge, o_address)
    o_forge
  end

  def forge_exist?(sObjectType)
    o_forge = process_get(sObjectType, config[:instance_name])
    if o_forge.empty? || o_forge[:servers].length == 0
      PrcLib.high_level_msg("\nBuilding your forge...\n")
      process_create(:internet_server)
    else
      load_existing_forge(o_forge)
    end
  end

  def load_existing_forge(o_forge)
    o_forge[:servers].each do |oServerToFind|
      if /^maestro\./ =~ oServerToFind[:name]
        process_get(:server, oServerToFind[:id])
      end
    end
    PrcLib.high_level_msg("\nChecking your forge...\n")

    o_server = data_objects(:server, :ObjectData)
    if o_server
      o_ip = process_query(:public_ip, :server_id => o_server[:id])
      register o_ip[0] if o_ip.length > 0
      process_create(:keypairs)
    else
      PrcLib.high_level_msg("\nYour forge exist, without maestro." \
        " Building Maestro...\n")
      process_create(:internet_server)

      PrcLib.high_level_msg("\nBuilding your forge...\n")
    end
  end

  def boot_keypairs(o_server)
    # Get keypairs
    h_keys = keypair_detect(
      o_server[:key_name],
      File.join(Forj.keypairs_path, o_server[:key_name])
    )

    private_key_file = File.join(
      h_keys[:keypair_path],
      h_keys[:private_key_name]
    )
    # public_key_file  = File.join(
    #     h_keys[:keypair_path],
    #     h_keys[:public_key_name]
    # )

    o_server_key = process_get(:keypairs, o_server[:key_name])

    keypair_coherent = coherent_keypair?(h_keys, o_server_key)
    boot_options = { :keys => private_key_file, :coherent => keypair_coherent }
    boot_options
  end

  def active_server?(o_server, o_address, private_key_file,
                     keypair_coherent, s_status
  )
    if o_server[:attrs][:status] == :active
      s_msg = <<-END
Your forj Maestro server is up and running and is publically accessible
through IP '%s'.

You can connect to '%s' with:
ssh ubuntu@%s -o StrictHostKeyChecking=no -i %s
      END
      s_msg = format(s_msg, o_address[:public_ip], o_server[:name],
                     o_address[:public_ip], private_key_file
      )

      unless keypair_coherent
        s_msg += "\n" + ANSI.bold(
          'Unfortunatelly'
        ) + ' your current keypair is not usable to connect to your server.' \
          "\n" + 'You need to fix this issue to gain access to your server.'
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
  # rubocop:disable CyclomaticComplexity
  def maestro_create_status(sStatus, iCurAct = 4)
    s_activity = '/-\\|?'
    if iCurAct < 4
      s_cur_act = 'ACTIVE'
    else
      s_cur_act = ANSI.bold('PENDING')
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
  # rubocop:enable CyclomaticComplexity

  def till_server_active(s_status, o_server, o_address, boot_options)
    m_cloud_init_error = []
    i_cur_act = 0
    o_old_log = ''

    while s_status != :active
      maestro_create_status(s_status, i_cur_act)
      i_cur_act += 1
      i_cur_act = i_cur_act % 4
      o_server = load_server(o_server)
      # s_status = o_server[:attrs][:status]
      if s_status == :starting
        s_status = :assign_ip if o_server[:attrs][:status] == :active
      elsif s_status == :assign_ip
        s_status = assign_ip_boot(o_address, boot_options, s_status, o_server)
      else # analyze the log output
        output_options = { :status => s_status, :error => m_cloud_init_error,
                           :old_log => o_old_log, :cur_act => i_cur_act
        }
        output_options = analyze_log_output(output_options, s_status)
        s_status = output_options[:status]
        m_cloud_init_error = output_options[:error]
        o_old_log = output_options[:old_log]
        i_cur_act = output_options[:cur_act]
      end
      sleep(5) if s_status != :active
    end
  end

  # Function to get the server, tracking errors
  #
  # *return*
  # - Server found.
  #
  def load_server(server)
    begin
      found_server = process_get(:server, server[:attrs][:id])
    rescue => e
      PrcLib.error(e.message)
    end
    (found_server.nil? ? server : found_server)
  end
end

# Functions for boot - build_forge
class ForjCoreProcess
  def assign_ip_boot(o_address, boot_options, s_status, o_server)
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
    s_msg = <<-END
Public IP for server '%s' is assigned.
Now, as soon as the server respond to the ssh port,
you will be able to get a tail of the build with:
while [ 1 = 1 ]
do
 ssh ubuntu@%s -o StrictHostKeyChecking=no -i %s tail -f /var/log/cloud-init.log
 sleep 5
done
    END
    s_msg = format(s_msg, o_server[:name],
                   o_address[:public_ip], boot_options[:keys]
    )
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

  def analyze_log_output(output_options, s_status)
    # m_cloud_init_error = []
    # o_old_log = ''
    o_log = process_get(:server_log, 25)[:attrs][:output]
    # i_cur_act = 4 if o_log == o_old_log
    output_options[:cur_act] = 4 if o_log == output_options[:old_log]
    # o_old_log = o_log
    output_options[:old_log] = o_log
    if /cloud-init boot finished/ =~ o_log
      # s_status = :active
      output_options[:status] = :active
      output_options[:error] = display_boot_moving_error(
        output_options[:error]
      )
    elsif /\[CRITICAL\]/ =~ o_log
      m_critical = o_log.scan(/.*\[CRITICAL\].*\n/)
      output_options[:error] = display_boot_critical_error(
        output_options[:error],
        m_critical
      )
    else
      # validate server status
      output_options = analyze_server_status(s_status, o_log, output_options)
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
  def analyze_server_status(s_status, o_log, output_options)
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

  def read_blueprint_implemented(o_forge, o_address)
    s_msg = format(
      "Your Forge '%s' is ready and accessible from" \
      " IP #{o_address[:public_ip]}.",
      config[:instance_name]
    )
    # TODO: read the blueprint/layout to identify which services
    # are implemented and can be accessible.
    if config[:blueprint]
      s_msg += format(
        "\n" + 'Maestro has implemented the following server(s) for your' \
          " blueprint '%s':",
        config[:blueprint]
      )
      server_options = display_servers_with_ip(o_forge, s_msg)
      s_msg += server_options[:message]
      i_count = server_options[:count]
      if i_count > 0
        s_msg += format("\n%d server(s) identified.\n", i_count)
      else
        s_msg = 'No servers found except maestro'
        PrcLib.warning(
          format(
            'Something went wrong, while creating nodes for blueprint' \
              " '%s'. check maestro logs.",
            config[:blueprint]
          )
        )
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
    o_forge[:servers].each do |server|
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
      pipe.puts(format('HPCLOUD_OS_USER=%s', hParams[:os_user]))
      pipe.puts(format('HPCLOUD_OS_KEY=%s', os_key))
      pipe.puts(format('DNS_KEY=%s', hParams[:account_id]))
      pipe.puts(format('DNS_SECRET=%s', hParams[:account_key]))
      pipe.close_write
      hpcloud_priv = pipe.read
    end
    hpcloud_priv
  end

  def load_h_meta(hParams, hpcloud_priv)
    h_meta = {
      'cdksite' => config.get(:server_name),
      'cdkdomain' => hParams[:domain_name],
      'eroip' => '127.0.0.1',
      'erosite' => config.get(:server_name),
      'erodomain' => hParams[:domain_name],
      'gitbranch' => hParams[:branch],
      'security_groups' => hParams[:security_group],
      'tenant_name' => hParams[:tenant_name],
      'network_name' => hParams[:network_name],
      'hpcloud_os_region' => hParams[:compute],
      'PUPPET_DEBUG' => 'True',
      'image_name' => hParams[:image_name],
      'key_name' => hParams[:keypair_name],
      'hpcloud_priv' => Base64.strict_encode64(
        hpcloud_priv
        ).gsub('=', '') # Remove pad
    }

    if hParams[:dns_service]
      h_meta['dns_zone'] = hParams[:dns_service]
      h_meta['dns_tenantid'] = hParams[:dns_tenant_id]
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

    h_meta
  end

  def build_metadata(sObjectType, hParams)
    entr = load_encoded_key

    os_enckey = hParams[:os_enckey]

    os_key = decrypt_key(os_enckey, entr)

    hpcloud_priv = load_hpcloud(hParams, os_key)

    config.set(
      :server_name,
      format('maestro.%s', hParams[:instance_name])
    ) # Used by :server object

    h_meta = load_h_meta(hParams, hpcloud_priv)

    config.set(:meta_data, h_meta) # Used by :server object

    h_meta_printable = h_meta.clone
    h_meta_printable['hpcloud_priv'] = 'XXX - data hidden - XXX'
    PrcLib.info("Metadata set:\n%s", h_meta_printable)

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
     PrcLib.error('Error while cloning the repo from %s\n%s\n%s',
                  maestro_url, e.message, e.backtrace.join("\n"))
     PrcLib.info(
       'If this error persist you could clone the repo manually in ~/.forj/'
     )
    end
    o_maestro = register(h_result, sObjectType)
    o_maestro[:maestro_repo] = h_result[:maestro_repo]
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

      PrcLib.debug("Copying recursively '%s' to '%s'", cloud_init, infra)
      FileUtils.copy_entry(cloud_init, dest_cloud_init)

      file_ver = File.join(infra, 'forj-cli.ver')
      File.write(file_ver, INFRA_VERSION)
      PrcLib.info("The infra workspace '%s' has been built from maestro" \
                  ' predefined files.', infra)
    else
      PrcLib.info("Re-using your infra... in '%s'", infra)
    end

    o_infra = register(h_infra, sObjectType)
    o_infra[:infra_repo] = h_infra[:infra_repo]
    o_infra
  end

  def load_infra(template, dest_cloud_init, h_result, b_result)
    # We are taking care on bootstrap files only.
    Find.find(File.join(template, 'cloud-init')) do |path|
      # unless File.directory?(path)
      next if File.directory?(path)
      s_maestro_rel_path = path.clone
      s_maestro_rel_path[File.join(template, 'cloud-init/')] = ''
      s_infra_path = File.join(dest_cloud_init, s_maestro_rel_path)
      if File.exist?(s_infra_path)
        md5_file = Digest::MD5.file(s_infra_path).hexdigest
        if h_result.key?(s_maestro_rel_path) &&
           h_result[s_maestro_rel_path] != md5_file
          b_result = false
          PrcLib.info("'%s' infra file has changed from original template" \
                      ' in maestro.', s_infra_path)
        else
          PrcLib.debug("'%s' infra file has not been updated.", s_infra_path)
        end
      end
      md5_file = Digest::MD5.file(path).hexdigest
      h_result[s_maestro_rel_path] = md5_file
      # end
    end
    b_result
  end

  def open_md5(s_md5_list, h_result)
    # begin
    File.open(s_md5_list, 'w') do |out|
      YAML.dump(h_result, out)
    end
    rescue => e
      PrcLib.error("%s\n%s", e.message, e.backtrace.join("\n"))
    # end
  end
end

# Functions for boot - create_or_use_infra
class ForjCoreProcess
  # Function which compare directories from maestro templates to infra.
  def infra_is_original?(infra_dir, maestro_dir)
    dest_cloud_init = File.join(infra_dir, 'cloud-init')
    template = File.join(maestro_dir, 'templates', 'infra')
    return false unless File.exist?(template)
    s_md5_list = File.join(infra_dir, '.maestro_original.yaml')
    b_result = true
    h_result = {}
    if File.exist?(s_md5_list)
      begin
        h_result = YAML.load_file(s_md5_list)
     rescue
       PrcLib.error("Unable to load valid Original files list '%s'. " \
                    "Your infra workspace won't be migrated, until fixed.",
                    s_md5_list)
       b_result = false
      end
      unless h_result
        h_result = {}
        b_result = false
      end
    end
    b_result = load_infra(template, dest_cloud_init, h_result, b_result)
    open_md5(s_md5_list, h_result)
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

    meta_data = JSON.generate(hParams[:metadata, :meta_data])

    build_tmpl_dir = File.expand_path(File.join(LIB_PATH, 'build_tmpl'))

    PrcLib.state("Preparing user_data - file '%s'", mime)
    # generate boot_*.sh
    mime_cmd = "#{build_tmpl_dir}/write-mime-multipart.py"
    bootstrap = "#{build_tmpl_dir}/bootstrap_build.sh"

    cmd = format(
      "%s '%s' '%s' '%s' '%s' '%s' '%s' '%s'",
      bootstrap, # script
      PrcLib.data_path, # $1 = Forj data base dir
      # $2 = Maestro repository dir
      hParams[:maestro_repository, :maestro_repo],
      config[:bootstrap_dirs], # $3 = Bootstrap directories
      config[:bootstrap_extra_dir], # $4 = Bootstrap extra directory
      meta_data,  # $5 = meta_data (string)
      mime_cmd, # $6: mime script file to execute.
      mime # $7: mime file generated.
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
      ForjLib.debug(5, "user_data temp file '%s' kept", mime)
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
  def forj_check_keypairs_files(keypath)
    key_name = config.get(:keypair_name)

    keys_entered = keypair_detect(key_name, keypath)
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

  def duplicate_keyname?(keys_imported, keys, key_name)
    if keys_imported && keys_imported[:key_basename] != keys[:key_basename] &&
       Forj.keypairs_path != keys[:keypair_path]
      PrcLib.warning("The private key '%s' was assigned to a different private"\
                     " key file '%s'.\nTo not overwrite it, we recommend you"\
                     ' to choose a different keypair name.',
                     keys, keys_imported[:key_basename])
      new_key_name = key_name
      s_msg = 'Please, provide a different keypair name:'
      while key_name == new_key_name
        new_key_name = ask(s_msg) do |q|
          q.validate = /.+/
        end
        new_key_name = new_key_name.to_s
        s_msg = 'Incorrect. You have to choose a keypair name different' \
          " than '#{key_name}'. If you want to interrupt, press Ctrl-C and" \
          ' retry later.\nSo, please, provide a different keypair' \
          ' name:' if key_name == new_key_name
      end
      key_name = new_key_name
      config.set(:key_name, key_name)
      keys = keypair_detect(key_name, key_path)
    end
    keys
  end

  def create_keys_automatically(keys, private_key_file)
    return if keys[:private_key_exist?]
    # Need to create a key. ask if we need so.
    PrcLib.message("The private key file attached to keypair named '%s' is not"\
                   ' found. Running ssh-keygen to create it.',
                   keys[:keypair_name])
    unless File.exist?(private_key_file)
      PrcLib.ensure_dir_exists(File.dirname(private_key_file))
      command = format('ssh-keygen -t rsa -f %s', private_key_file)
      PrcLib.debug(format("Executing '%s'", command))
      system(command)
    end
    if !File.exist?(private_key_file)
      PrcLib.fatal(1, "'%s' not found. Unable to add your keypair to hpcloud."\
                   ' Create it yourself and provide it with -p option. '\
                   'Then retry.', private_key_file)
    else
      PrcLib.fatal(1, 'ssh-keygen did not created your key pairs. Aborting.'\
                   ' Please review errors in ~/.forj/forj.log')
    end
  end
end

# Functions for setup
class ForjCoreProcess
  def load_key_with_passphrase(keys, public_key_file, private_key_file)
    # unless keys[:public_key_exist?]
    return if keys[:private_key_exist?]
    PrcLib.message("Your public key '%s' was not found. Getting it from the" \
                   ' private one. It may require your passphrase.',
                   public_key_file)
    command = format(
      'ssh-keygen -y -f %s > %s',
      private_key_file,
      public_key_file
    )
    PrcLib.debug("Executing '%s'", command)
    system(command)
    # end
  end

  def save_sequences(private_key_file, forj_private_key_file,
                     public_key_file, forj_public_key_file, key_name
  )
    PrcLib.info('Importing key pair to FORJ keypairs list.')
    FileUtils.copy(private_key_file, forj_private_key_file)
    FileUtils.copy(public_key_file, forj_public_key_file)
    # Attaching this keypair to the account
    @hAccountData.rh_set(key_name, :credentials, 'keypair_name')
    @hAccountData.rh_set(forj_private_key_file, :credentials, 'keypair_path')
    config.local_set(key_name.to_s, private_key_file, :imported_keys)
  end

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
  def save_internal_key(forj_private_key_file, keys)
    # Saving internal copy of private key file for forj use.
    config.set(:keypair_path, forj_private_key_file)
    PrcLib.info("Configured forj keypair '%s' with '%s'",
                keys[:keypair_name],
                File.join(keys[:keypair_path], keys[:key_basename])
                )
  end

  # keypair_files post setup
  def forj_setup_keypairs_files
    # Getting Account keypair information
    key_name = config[:keypair_name]
    key_path = File.expand_path(config[:keypair_files])

    keys_imported = nil
    keys_imported = keypair_detect(
      key_name,
      config.local_get(key_name, :imported_keys)
    ) if config.local_exist?(key_name, :imported_keys)
    keys = keypair_detect(key_name, key_path)

    keys = duplicate_keyname?(keys_imported, keys, key_name)

    private_key_file = File.join(keys[:keypair_path], keys[:private_key_name])
    public_key_file = File.join(keys[:keypair_path], keys[:public_key_name])

    # Creation sequences
    create_keys_automatically(keys, private_key_file)

    load_key_with_passphrase(keys, public_key_file, private_key_file)

    forj_private_key_file = File.join(Forj.keypairs_path, key_name)
    # forj_public_key_file = File.join($FORJ_KEYPAIRS_PATH, key_name + '.pub')

    # Saving sequences
    if keys[:keypair_path] != Forj.keypairs_path
      if !File.exist?(forj_private_key_file) ||
         !File.exist?(forj_public_key_file)
        save_sequences(private_key_file, forj_private_key_file,
                       public_key_file, forj_public_key_file, key_name
        )
      else
        save_md5(private_key_file, forj_private_key_file,
                 public_key_file, forj_public_key_file
        )
      end
    end

    save_internal_key(forj_private_key_file, keys)
    true # forj_setup_keypairs_files successfull
  end

  def forj_dns_settings
    s_ask = 'Optionally, you can ask Maestro to use/manage a domain name on' \
      " your cloud. It requires your DNS cloud service to be enabled.\nDo " \
      ' you want to configure it?'
    config.set(:dns_settings, agree(s_ask))
    true
  end

  def forj_dns_settings?(sKey)
    # Return true to ask the question. false otherwise
    unless config.get(:dns_settings)
      config.set(sKey, nil)
      return false # Do not ask
    end
    true
  end

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
end

# Funtions for get
class ForjCoreProcess
  def get_forge(sCloudObj, sForgeId, _hParams)
    s_query = {}
    h_servers = []
    s_query[:name] = sForgeId

    o_servers = process_query(:server, s_query)

    regex =  Regexp.new(format('\.%s$', sForgeId))

    o_servers.each do |o_server|
      o_name = o_server[:name]
      h_servers << o_server if regex =~ o_name
    end
    PrcLib.info('%s server(s) were found under instance name %s ',
                h_servers.count, s_query[:name])

    o_forge = register(h_servers, sCloudObj)
    o_forge[:servers] = h_servers
    o_forge[:name] = sForgeId
    o_forge
  end
end

# Funtions for destroy
class ForjCoreProcess
  def delete_forge(_sCloudObj, hParams)
    PrcLib.state('Destroying server(s) of your forge')

    forge_serverid = config.get(:forge_server)

    o_forge = hParams[:forge]

    o_forge[:servers].each do|server|
      next if forge_serverid && forge_serverid != server[:id]
      register(server)
      PrcLib.state("Destroying server '%s'", server[:name])
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
    o_forge = hParams[:forge]
    o_server = nil

    o_forge[:servers].each do|server|
      next if hParams[:forge_server] != server[:id]
      o_server = server
      break
    end

    # Get server information
    PrcLib.state('Getting server information')
    o_server = process_get(:server, o_server[:id])
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
      session = Net::SSH.start(public_ip, user, ssh_options) do |_ssh|
        ssh_login(ssh_options, user, public_ip)
      end
      PrcLib.debug('Error closing ssh connection, box %s ',
                   o_server[:name]) unless session
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
    case images.length
    when 0
      s_default = hParams[:default_value]
    else
      if images[0, :ssh_user].nil?
        s_default = hParams[:default_value]
      else
        s_default = images[0, :ssh_user]
      end
    end
    { :default_value => s_default, :list => config[:users] }
  end

  def ssh_login(options, user, public_ip)
    s_opts = '-o StrictHostKeyChecking=no -o ServerAliveInterval=180'
    s_opts += format(' -i %s', options[:keys]) if options[:keys]

    command = format('ssh %s %s@%s', s_opts, user, public_ip)
    PrcLib.debug("Running '%s'", command)
    system(command)
  end

  def ssh_user(image_name)
    return 'fedora' if image_name =~ /fedora/i
    return 'centos' if image_name =~ /centos/i
    'ubuntu'
  end
end
