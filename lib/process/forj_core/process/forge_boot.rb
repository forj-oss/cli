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

require 'fileutils'
require 'find'
require 'digest'
require 'json'
require 'encryptor' # gem install encryptor
require 'base64'
require 'net/ssh'

# Functions for :forge boot
class ForjCoreProcess
  def build_forge(sObjectType, hParams)
    # TODO: To be replaced by a migration task at install phase.
    update_keypair_config

    forge = forge_get_or_create(sObjectType, hParams)

    maestro = forge[:servers, 'maestro']
    unless maestro.nil?
      register(maestro)
      register(boot_keypairs(maestro))
      hParams.refresh
    end

    # Define the log lines to get and test.
    config.set(:log_lines, 5)

    PrcLib.info("Maestro server '%s' id is '%s'.", maestro[:name], maestro[:id])

    till_server_active(forge, hParams)

    forge.refresh
    _server_show_info(forge, hParams)

    forge
  end

  def forge_get_or_create(sObjectType, hParams)
    forge = process_get(sObjectType, hParams[:instance_name], :info => false)
    if forge.empty? || forge[:servers].length == 0 ||
       forge[:servers, 'maestro'].nil?
      PrcLib.high_level_msg("\nBuilding your forge...\n")
      process_create(:internet_server)

      forge[:servers, 'maestro'] = hParams.refresh[:server, :ObjectData]
    end
    forge
  end
end

# Internal functions
class ForjCoreProcess
  def assign_ip_boot(maestro, status)
    # To be able to ask for server IP assigned
    query_cache_cleanup(:public_ip)
    o_addresses = process_query(:public_ip, :server_id => maestro[:id])
    if o_addresses.length == 0
      # Assigning Public IP.
      o_address = process_create(:public_ip)
      s_msg = "Public IP for server '#{o_address[:public_ip]}' is assigned."
      PrcLib.info(s_msg)
    end
    status.is :cloud_init
  end

  # Log analyzes at boot time.
  def analyze_log_output(server, status, hParams)
    o_log = process_get(:server_log, 25)
    return false if o_log.nil? || o_log.empty?

    log = o_log[:output]

    if log == status.prev_log
      status.pending(true, server, hParams)
    else
      status.pending(false, server, hParams)
      status.prev_log = log
    end

    detects = %w(done critical cloud_init nonet)
    detects.each do |event|
      break if method("detect_log_#{event}").call(status, log)
    end
    true
  end

  def detect_log_done(status, log)
    return false unless /cloud-init boot finished/ =~ log

    status.is :active
    status.error = display_boot_moving_error(status.error)
    true
  end

  def detect_log_critical(status, log)
    return false unless /\[CRITICAL\]/ =~ log

    m_critical = log.scan(/.*\[CRITICAL\].*\n/)
    display_boot_critical_error(log, status, m_critical)
    true
  end

  def detect_log_cloud_init(status, log)
    re = /cloud-init-nonet gave up waiting for a network device/
    return false unless status.status == :cloud_init && re =~ log
    # Valid for ubuntu image 12.04

    PrcLib.warning('Cloud-init has gave up to configure the network. '\
                   'waiting...')
    status.is :nonet
    true
  end

  def detect_log_nonet(status, log)
    re = /Booting system without full network configuration/
    return false unless status.status == :nonet && re =~ log
    # Valid for ubuntu image 12.04

    PrcLib.warning('forj has detected an issue to bring up your '\
                   'maestro server. Removing it and re-creating a new one.'\
                   ' please be patient...')
    status.is :restart
    true
  end

  def display_boot_critical_error(log, status, m_critical)
    return if status.error == m_critical
    s_reported = log.clone
    s_reported['CRITICAL'] = ANSI.bold('CRITICAL')
    PrcLib.error("cloud-init error detected:\n-----\n%s\n-----\n" \
                 'Please connect to the box to decide what you' \
                 ' need to do.', s_reported)
    status.error = m_critical
  end

  def display_boot_moving_error(m_cloud_init_error)
    if m_cloud_init_error != []
      msg = 'Critical error cleared. Cloud-init seems moving...'
      PrcLib.high_level_msg(msg)
      PrcLib.info(msg)
      m_cloud_init_error = []
    end
    m_cloud_init_error
  end
end

# Functions for boot - build_forge
class ForjCoreProcess
  def forge_status(maestro)
    return ForgeStatus.new if maestro.nil?

    maestro.refresh
    return ForgeStatus.new unless maestro[:status] == :active

    register(maestro)
    log = process_get(:server_log, 25)
    return ForgeStatus.new if log.nil? || log.empty?
    return ForgeStatus.new :active if /cloud-init boot finished/ =~ log[:output]

    network_used = maestro[:meta_data, 'network_name']
    if network_used && maestro[:pub_ip_addresses, network_used].nil?
      return ForgeStatus.new :assign_ip
    end

    ForgeStatus.new :cloud_init
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
  # Loop until server is active
  def till_server_active(forge, hParams)
    ForgeStatus.new.display
    maestro = forge[:servers, 'maestro']
    status = forge_status(maestro)

    forge_info(maestro, hParams, status.status) unless status.status == :active

    hParams.refresh

    hParams[:server_id] = maestro[:id]
    hParams[:server_name] = maestro[:name]

    while status.running?
      status.display

      sleep(5) unless status.changed?

      status.progress

      maestro = hParams[:server, :ObjectData]
      hParams[:server_id] = maestro[:id] unless maestro.nil?
      status.is :disappeared unless maestro.refresh

      task = %w(disappeared error restart restarted checking starting assign
                analyze_log)
      task.each do |t|
        break if method("_run_#{t}").call(maestro, status, hParams)
      end
    end
    msg = 'The Forge build is over!'
    PrcLib.info(msg)
    PrcLib.high_level_msg("\n#{msg}\n")
  end

  # Task run list ****************

  # if the server has disappeared. try to get is back
  def _run_disappeared(maestro, status, hParams)
    return false unless status.status == :disappeared

    maestro = process_get(:server, hParams[:server_id], hParams)
    unless maestro.nil?
      register(maestro)
      return true
    end
    PrcLib.warning("Server '#{hParams[:server_name]}' is not found "\
                   "with ID '#{hParams[:server_id]}'. Trying to get the server"\
                   ' from his name.')
    list = process_query(:server, { :name => hParams[:server_name] }, hParams)
    return true if list.nil?
    if list.empty?
      PrcLib.fatal("No more maestro server '#{hParams[:server_name]}' has been"\
                   " found. Did you remove it?.\nBoot aborted.")
    end
    if list.length > 1
      found = []
      list.each { |s| found << s[:id] }
      PrcLib.fatal("Too many servers with name '#{hParams[:server_name]}'."\
      ' You have to connect manually to your cloud and fix those duplicated'\
      " servers.\nList of servers:\n%s", found.join(', '))
    end
    status.is :starting
    maestro = list[0]
    hParams[:server_id] = maestro[:id]
    register(maestro)
    true
  end

  # if the server is in error, state forge in error.
  def _run_error(maestro, status, _hParams)
    return false unless maestro[:status] == :error
    PrcLib.warning("The creation of server '%s' has currently failed. "\
                   'Trying to rebuild it, once before giving up.',
                   server_name)
    status.is :in_error
    true
  end

  # if forge is in error, try to recreate Maestro. forge state move to restarted
  #
  # The server ID will change.
  def _run_restart(maestro, status, hParams)
    return false unless status.status == :in_error
    process_delete(:server)
    PrcLib.message("Bad server '%s' removed. Creating a new one...",
                   server_name)
    sleep(5)
    process_create(:internet_server)
    status.is :restarted
    maestro = hParams.refresh[:server]
    hParams[:server_id] = maestro[:id] unless maestro.nil?
    PrcLib.info("NEW Maestro server '%s' id is '%s'.",
                maestro[:name], maestro[:id])
    true
  end

  # if the forge creation has been restarted (maestro creation error)
  # and if the server is back in error, then forgive forge creation.
  # if the server state moved to :active, move forge state to :cloud_init
  def _run_restarted(maestro, status, _hParams)
    return false unless status.status == :restarted

    if maestro[:status] == :error
      PrcLib.fatal(1, 'Server tried to be rebuilt but failed again.')
    end
    status.is :cloud_init
    true
  end

  # if we check the forge and maestro is still not active
  # Move status to :starting
  def _run_checking(maestro, status, _hParams)
    return false unless status.status == :checking &&
                        maestro[:status] != :active
    status.is :starting
    true
  end

  # If forge creation is starting or checking and server is active
  # move forge state to :assign_ip
  def _run_starting(maestro, status, _hParams)
    return false unless [:starting, :checking].include?(status.status) &&
                        maestro[:status] == :active
    status.is :assign_ip
    true
  end

  # if forge is assign_ip, create the pub IP if missing.
  # state move to :cloud_init when public IP is found.
  def _run_assign(maestro, status, _hParams)
    return false unless status.status == :assign_ip
    assign_ip_boot(maestro, status)
    true
  end

  # Default task
  # Analyze the log and some additional log detection sent by maestro
  # cloud_init.
  #
  # - tb_detect - Maestro Test-box request detection - See test_box.rb
  # - ca_root_detect - Maestro CA Root request detection - See ca_root_cert.rb
  # - lorj_detect - Maestro Lorj account request detection - See lorj_account.rb
  #
  def _run_analyze_log(maestro, status, hParams)
    return false unless analyze_log_output(maestro, status, hParams)

    tb_detect(hParams, status.prev_log)
    ca_root_detect(hParams, status.prev_log)
    lorj_detect(hParams, status.prev_log)

    true
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
