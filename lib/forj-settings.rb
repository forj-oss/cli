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

require 'cloud_connection.rb'

module Forj
  # This module helps you to setup your forge's account
  module Settings
    def self.common_options(options)
      PrcLib.level = Logger::INFO if options[:verbose]
      PrcLib.level = Logger::DEBUG if options[:debug]
      unless options[:lorj_debug].nil?
        PrcLib.core_level = options[:lorj_debug].to_i
        PrcLib.level = Logger::DEBUG
      end
      latest_version?(options[:account_name]) if options[:account_name]
    end

    def self.latest_version?(account_name)
      config = Lorj::Account.new(nil, Forj.file_version)

      config.ac_load account_name

      PrcLib.fatal(1,
                   "Your account '%s' is obsolete, use `forj setup`," \
                   ' to update it.',
                   account_name) \
                   unless config.latest_version?('account')
    end

    def self.account_show_all(account_name)
      config = Lorj::Account.new

      config.ac_load account_name
      Forj::CloudConnection.connect(config)

      puts format(
        "List of account settings for provider '%s': ",
        config.get(:provider)
      )
      puts format(
        "%-15s %-12s :\n------------------------------",
        'key',
        'section name'
      )

      config.meta_each do |section, found_key, hValue|
        next if hValue.rh_get(:readonly) || hValue.rh_get(:get) == false
        s_desc = hValue.rh_get(:desc)
        puts format('%-15s %-12s : %s', found_key, section, s_desc)
      end
      puts format(
        "\nUse `forj set KeyName=Value -a %s` to set one.",
        [account_name]
      )
      puts format(
        'Use `forj get -a %s`               to check current values.',
        account_name
      )
    end

    def self.config_show_all
      config = Lorj::Account.new
      puts 'List of available FORJ default settings:'
      puts format(
        "%-15s %-12s :\n------------------------------",
        'key',
        'section name'
      )
      config.meta_each do |section, found_key, hValue|
        next if hValue.rh_get(:readonly) || hValue.rh_get(:get) == fals
        s_desc = hValue.rh_get(:desc)
        puts format('%-15s %-12s : %s', found_key, section, s_desc)
      end
      puts "\nUse `forj set KeyName=Value` to set one. "
      puts 'Use `forj get`               to get current values. '
    end

    def self.validate_account_set(account, account_name, account_key)
      PrcLib.fatal(1,
                   "Unable to update protected '%s'. use `forj setup`," \
                   ' to update it.',
                   account_key) if account.readonly?(account_key)

      if account.meta_type?(account_key) == :default
        PrcLib.fatal(1, "Unable set '%s' value. To update this one, use forj" \
                     ' set %s, WITHOUT -a %s',
                     account_key, account_key, account_name)
      end
    end
  end

  # This module helps you to setup your forge's account
  module Settings
    def self.format_old_key(account, old_value, key_to_set)
      s_bef = 'unset'

      s_bef = format(
        "'%s' (%s)",
        old_value,
        account.where?(key_to_set)[0]
      ) if account.exist?(key_to_set)

      s_bef
    end

    def self.format_new_key(account, key_to_set)
      s_aft = 'unset'

      s_aft = format(
        "'%s' (%s)",
        account.get(key_to_set),
        account.where?(key_to_set)[0]
      ) if account.exist?(key_to_set)

      s_aft
    end

    def self.account_set(account_name, *p)
      config = Lorj::Account.new

      b_dirty = false

      config.ac_load account_name
      Forj::CloudConnection.connect(config)

      p.flatten!
      p.each do |key_val|
        mkey_val = valid_key_value?(key_val)

        key_to_set = mkey_val[1]
        key_value = mkey_val[2]

        validate_account_set(config, account_name, key_to_set)

        section, key_to_set = Lorj.data.first_section(key_to_set)
        full_key = format('%s/%s', section, key_to_set)

        old_value = config.get(key_to_set)
        s_bef = format_old_key(config, old_value, key_to_set)

        if old_value == key_value
          puts format('%-25s: No update', full_key)
          next
        end
        b_dirty = true

        if key_value == ''
          config.del(key_to_set, :name => 'account')
        else
          config.set(key_to_set, key_value, :name => 'account')
        end

        s_aft = format_new_key(config, key_to_set)

        puts format(
          '%-25s: %s => %s',
          full_key,
          s_bef,
          ANSI.bold + s_aft + ANSI.clear
        )
      end
      config.ac_save if b_dirty
    end

    def self.valid_key_value?(key_val)
      mkey_val = key_val.match(/^(.*) *= *(.*)$/)

      PrcLib.fatal(
        1,
        "Syntax error. Please set your value like: 'key=value' and retry."
      ) unless mkey_val

      mkey_val
    end

    def self.valid_key?(key)
      key = key.to_sym if key.is_a?(String)

      return nil unless key.is_a?(Symbol)

      if Lorj.defaults.get_meta_auto(key).nil?
        PrcLib.warning("key '%s' is not a recognized default key by forj"\
                       ' model. ', key)
      end

      key
    end
  end

  # This module helps you to setup your forge's account
  module Settings
    def self.config_set(*p)
      config = Lorj::Account.new
      b_dirty = false

      p.flatten!

      p.each do |key_val|
        mkey_val = valid_key_value?(key_val)

        key_to_set = mkey_val[1]
        key_value = mkey_val[2]

        s_bef = 'unset'
        s_aft = 'unset'

        key_to_set = valid_key?(key_to_set)

        old_value = config.get(key_to_set)
        s_bef = format("%s: '%s'", config.where?(key_to_set)[0],
                       config.get(key_to_set)) if config.exist?(key_to_set)

        next if _no_update?(key_to_set, old_value, key_value, config)

        b_dirty = true

        if key_value != ''
          config.local_set(key_to_set, key_value)
        else
          config.local_del(key_to_set)
        end

        s_aft = format("%s: '%s'", config.where?(key_to_set)[0],
                       config.get(key_to_set)) if config.exist?(key_to_set)

        puts format('%-15s: %s => %s', key_to_set, s_bef, ANSI.bold(s_aft))
      end
      config.save_local_config if b_dirty
    end

    def self._no_update?(key_to_set, old_value, key_value, config)
      if key_value == '' && config.where?(key_to_set)[0] != 'local'
        puts format('%-15s: No update', key_to_set)
        return true
      end

      if old_value == key_value
        puts format('%-15s: No update', key_to_set)
        return true
      end
      false
    end

    def self.format_highlight(account_name, config_where, where_format)
      return format(where_format, config_where) if config_where == 'default'

      return ANSI.bold(format(where_format,
                              account_name)) if config_where == 'account'
      ANSI.bold(ANSI.yellow(format(where_format, config_where)))
    end

    def self.get_account_values(account, account_name)
      Lorj.data.meta_each do |section, mykey, hValue|
        next if hValue.rh_get(:get) == false
        config_where = account.where?(mykey, :section => section,
                                             :names => account.layers -
                                                       %w(runtime))

        s_upd_msg = '+'
        s_upd_msg = ' ' if hValue.rh_get(:readonly)

        if config_where
          where_highlight = format_highlight(account_name,
                                             config_where[0], '%-9s')
          default_key = nil
          if hValue.rh_exist?(:default) && config_where[0] != 'account'
            default_key = format(" (from default key '%s')",
                                 hValue.rh_get(:default))
          end
          puts format("%s %-15s(%s) %-12s: '%s'%s",
                      s_upd_msg, mykey, where_highlight, section,
                      account.get(mykey, nil, :section => section), default_key)
        else
          puts format(
            '%s %-15s(         ) %-12s: unset',
            s_upd_msg,
            mykey,
            section
          )
        end
      end
    end

    def self.account_get_all(oConfig, account_name)
      #  byebug
      PrcLib.fatal(1, "Unable to load account '%s'. Not found.",
                   account_name) unless oConfig.ac_load account_name
      Forj::CloudConnection.connect(oConfig)

      puts format(
        'legend: default = Application defaults, local = Local' \
          " default config, %s = '%s' account config\n\n",
        account_name,
        account_name)

      puts format(
        '%s %-15s(%-7s) %-12s:' + "\n" + '--------------------------' \
          '--------------', 'U',
        'key', 'origin',
        'section name'
      )

      get_account_values(oConfig, account_name)

      puts "\nOn values identified by '+' you can:"

      puts format(
        'Use `forj set <key>=<value> -a %s` to update account data.',
        account_name
      )
      puts format(
        'Or  `forj set <key>= -a %s`        '\
          'to restore key default value.',
        account_name
      )
    end
  end

  # This module helps you to setup your forge's account
  module Settings
    def self.config_get_all(oConfig)
      puts 'legend: default = Application defaults, local = Local default' \
           " config\n\n"
      puts format("%s %-19s(%-7s) %-12s:\n"\
                  '----------------------------------------',
                  'U',  'key', 'origin', 'section name')

      a_processes = [{ :process_module => :cloud },
                     { :process_module => :forj_core }]

      # Loading CloudCore embedding provider controller + its process.
      Lorj::Core.new(oConfig, a_processes)

      oConfig.meta_each do |section, found_key, hValue|
        next if hValue.rh_get(:get) == false
        s_upd_msg = '+'
        s_upd_msg = ' ' if hValue.rh_get(:readonly)
        found_key = hValue.rh_get(:default) if hValue.rh_exist?(:default)

        where = oConfig.where?(found_key, :section => section)
        if where
          where = where[0]
          highlight = ''
          highlight = ANSI.bold + ANSI.yellow if where == 'local'
          puts format(
            "%s %-19s(%s%-7s%s) %-12s: '%s'",
            s_upd_msg,
            found_key,
            highlight,
            where,
            ANSI.clear,
            section,
            oConfig.get(section.to_s + '#' + found_key.to_s)
          )
        else
          puts format(
            '%s %-19s(       ) %-12s: unset',
            s_upd_msg,
            found_key,
            section
          )
        end
      end
      puts "\nUse 'forj set <key>=<value>' to update defaults on values" \
        " identified with '+'"
    end

    def self.account_get(oConfig, account_name, key)
      PrcLib.fatal(1, "Unable to load account '%s'. Not found.",
                   account_name) unless oConfig.ac_load account_name
      Forj::CloudConnection.connect(oConfig)

      if oConfig.where?(key)
        puts format(
          "%s: '%s'",
          oConfig.where?(key)[0],
          oConfig.get(key)
        )
      elsif oConfig.where?(key.parameterize.underscore.to_sym)
        key_symb = key.parameterize.underscore.to_sym
        puts format(
          "%s: '%s'",
          oConfig.where?(key_symb)[0],
          oConfig.get(key_symb)
        )
      else
        PrcLib.message("key '%s' not found", key)
      end
    end

    def self.config_get(oConfig, key)
      where = oConfig.where?(key)
      if where
        puts format("%s:'%s'", where[0], oConfig[key])
      else
        PrcLib.message("key '%s' not found", key)
      end
    end

    def self.show_settings(options)
      if !options[:account_name]
        config_show_all
      else
        account_show_all(options[:account_name])
      end
    end

    def self.set_settings(options, p)
      if options[:account_name]
        account_set(options[:account_name], p)
      else
        config_set(p)
      end
    end
  end
end
