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

    s_status = active_server?(server, o_address, boot_options, s_status)

    till_server_active(s_status, hParams, o_address, boot_options)

    hParams[:info] = true
    o_forge = get_forge(sObjectType, config[:instance_name], hParams)

    o_forge
  end

  def forge_get_or_create(sObjectType, hParams)
    o_forge = process_get(sObjectType, config[:instance_name], :info => false)
    if o_forge.empty? || o_forge[:servers].length == 0
      PrcLib.high_level_msg("\nBuilding your forge...\n")
      process_create(:internet_server)
      o_forge[:servers, 'maestro'] = hParams.refresh[:server]
    else
      o_forge = load_existing_forge(o_forge, hParams)
    end
    o_forge
  end

  # Funtions for destroy
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

# Internal functions
class ForjCoreProcess
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
    s_msg = "Public IP for server '#{o_address[:public_ip]}' is assigned."
    s_msg += server_connect_info(o_server, image, o_address,
                                 boot_options, s_status)

    PrcLib.info(s_msg)
    PrcLib.high_level_msg("\n%s\nThe forge is still building...\n", s_msg)
    s_status = :cloud_init
    s_status
  end
end

# Log analyzes at boot time.
class ForjProcess
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
  def active_server?(o_server, o_address, _ssh_key, status)
    if o_server[:attrs][:status] == :active
      return :assign_ip if o_address[:public_ip].nil?

      image = server_get_image o_server

      s_msg = 'Your forj Maestro server is up and running and is publically'\
              " accessible through IP '#{o_address[:public_ip]}'."

      PrcLib.info(s_msg)
      PrcLib.high_level_msg("\n%s\n", s_msg)

      o_log = process_get(:server_log, 25)[:attrs][:output]
      if /cloud-init boot finished/ =~ o_log
        status = :active
      else
        PrcLib.info(server_connect_info(o_server, image, o_address,
                                        nil, status))
        PrcLib.high_level_msg("The forge is still building...\n")
        status = :cloud_init
      end
    else
      sleep 5
      status = :starting
    end
    status
  end

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
end

# Manage Keypairs at boot time.
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
end

# Functions for boot - build_forge
class ForjCoreProcess
  # Function displaying the server status
  def maestro_create_status(sStatus, iCurAct = 4, pending_count = 0)
    s_activity = '/-\\|?'
    if iCurAct < 4
      s_cur_act = 'ACTIVE'
    else
      s_cur_act = format('%s - %d s', ANSI.bold('PENDING'),
                         (pending_count + 1) * 5)
    end

    state = {
      :checking   => 'Checking server status',
      :starting   => 'STARTING',
      :assign_ip  => '%s - %s - Assigning Public IP',
      :cloud_init => '%s - %s - Currently running cloud-init. Be patient.',
      :nonet      => '%s - %s - Currently running cloud-init. Be patient.',
      :restart    => 'RESTARTING - Currently restarting maestro box. '\
                     'Be patient.',
      :active     => 'Server is active'
    }
    case sStatus
    when :checking, :starting, :restart
      PrcLib.state(state[sStatus])
    when :assign_ip, :cloud_init, :nonet
      PrcLib.state(state[sStatus], s_activity[iCurAct], s_cur_act)
    when :active
      PrcLib.info(state[sStatus])
    end
  end

  # TODO: Rewrite this function to break it for rubocop.
  # rubocop: disable CyclomaticComplexity
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
    image = server_get_image o_server

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
    msg = 'The Forge build is over!'
    PrcLib.info(msg)
    PrcLib.high_level_msg("\n#{msg}\n")
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
