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

# forj setup - keypairs management
class ForjCoreProcess
  # ******************
  # KEYPAIR_FILES
  # ******************

  # SETUP: :keypair_files validate_function
  #
  # Check files existence
  def forj_check_keypairs_files(input_pathbase)
    key_name = config.get(:keypair_name)

    keypair_path = File.expand_path(File.dirname(input_pathbase))
    keypair_base = File.expand_path(File.basename(input_pathbase))
    keys_entered = keypair_detect(key_name, keypair_path, keypair_base)

    spriv_key_exist = :private_key_exist?
    spub_key_exist = :public_key_exist?

    if !keys_entered[spriv_key_exist] && !keys_entered[spub_key_exist]
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

  # SETUP: :keypair_files post_step_function
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

  # SETUP: :keypair_files pre_step_function
  #
  # pre process before asking keypair files
  # return true  continue to ask keypair files
  # return false skip asking keypair files
  def forj_cloud_keypair_coherent?(_keypair_files)
    return true unless config.exist?(:key_cloud_coherence)

    keypair = data_objects(:keypairs)

    spriv_key_exist = :private_key_exist?
    return true unless keypair.nil? || keypair[spriv_key_exist]

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

  # ******************
  # KEYPAIR_NAME
  # ******************

  # TODO: Change this by a migration function called at install time.

  # SETUP: :keypair_name pre_step_function
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
  # This function is used by forge boot and forj setup.
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

  # SETUP: :keypair_name post_step_function
  #
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

    spub_key_exist = :public_key_exist?
    return true unless cloud_key[spub_key_exist]

    PrcLib.message("You need to create a new keypair instead of '%s'"\
                   'or quit the setup to get the original key and retry.',
                   key_name)
    s_ask = 'Do you want to create new keypair?'

    PrcLib.fatal(1, 'Quitting setup per your request.') unless agree(s_ask)
    false
  end
end

# ---------------------------------
# Internal functions for forj setup
class ForjCoreProcess
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
      spriv_key_exist = :private_key_exist?
      spub_key_exist = :public_key_exist?
      unless keys_imported[spriv_key_exist] || keys_imported[spub_key_exist]
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
    spriv_key_exist = :private_key_exist?
    return if keys[spriv_key_exist]
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

  def save_internal_key(keys)
    # Saving internal copy of private key file for forj use.
    config.set(:keypair_base, keys[:keypair_name], :name => 'account')
    PrcLib.info("Configured forj keypair '%s' with '%s'",
                keys[:keypair_name],
                File.join(keys[:keypair_path], keys[:key_basename])
               )
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
