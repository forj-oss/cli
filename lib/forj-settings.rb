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

module Forj
  # This module helps you to setup your forge's account
  module Settings
    def self.common_options(options)
      PrcLib.set_level(Logger::INFO) if options[:verbose]
      PrcLib.set_level(Logger::DEBUG) if options[:debug]
      unless options[:lorj_debug].nil?
        PrcLib.core_level = options[:lorj_debug].to_i
        PrcLib.set_level(Logger::DEBUG)
      end
    end

    def self.account_show_all(oConfig, account_name)
      oConfig.set(:account_name, account_name)

      o_forj_account = Lorj::Account.new(oConfig)
      o_forj_account.ac_load
      puts format(
               "List of account settings for provider '%s': ",
               o_forj_account.get(:provider)
           )
      puts format(
               "%-15s %-12s :\n------------------------------",
               'key',
               'section name'
           )

      o_forj_account.metadata_each do |section, found_key, hValue|
        next if Lorj.rhGet(hValue, :readonly)
        s_desc = Lorj.rhGet(hValue, :desc)
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

    def self.config_show_all(oConfig)
      puts 'List of available FORJ default settings:'
      puts format(
               "%-15s %-12s :\n------------------------------",
               'key',
               'section name'
           )
      oConfig.meta_each do |section, found_key, hValue|
        next if Lorj.rhGet(hValue, :readonly)
        s_desc = Lorj.rhGet(hValue, :desc)
        puts format('%-15s %-12s : %s', found_key, section, s_desc)
      end
      puts "\nUse `forj set KeyName=Value` to set one. "
      puts 'Use `forj get`               to get current values. '
    end

    def self.validate_account_set(o_forj_account, account_name, account_key)
      PrcLib.fatal(
          1,
          format(
              "Unable to update protected '%s'. use `forj setup`," \
                  ' to update it.',
              account_key
          )
      ) if o_forj_account.readonly?(account_key)

      if o_forj_account.meta_type?(account_key) == :default
        PrcLib.fatal(
            1,
            format(
                "Unable set '%s' value. To update this one, use forj set" \
                    ' %s, WITHOUT -a %s',
                account_key,
                account_key,
                account_name
            )
        )
      end
    end

    def self.format_old_key(o_forj_account, old_value, key_to_set)
      s_bef = 'unset'

      s_bef = format(
          "'%s' (%s)",
          old_value,
          o_forj_account.exist?(key_to_set)
      ) if o_forj_account.exist?(key_to_set)

      s_bef
    end

    def self.format_new_key(o_forj_account, key_to_set)
      s_aft = 'unset'

      s_aft = format(
          "'%s' (%s)",
          o_forj_account.get(key_to_set),
          o_forj_account.exist?(key_to_set)
      ) if o_forj_account.exist?(key_to_set)

      s_aft
    end

    def self.account_set(oConfig, account_name, *p)
      b_dirty = false

      oConfig[:account_name] = account_name

      o_forj_account = Lorj::Account.new(oConfig)
      o_forj_account.ac_load

      p.flatten!
      p.each do | key_val |
        mkey_val = valid_key_value?(key_val)

        key_to_set = mkey_val[1]
        key_value = mkey_val[2]

        validate_account_set(o_forj_account, account_name, key_to_set)

        full_key = format(
            '%s/%s',
            Lorj::Default.get_meta_section(key_to_set),
            key_to_set
        )

        old_value = o_forj_account.get(key_to_set)
        s_bef = format_old_key(o_forj_account, old_value, key_to_set)

        if old_value == key_value
          puts format('%-25s: No update', full_key)
          next
        end
        b_dirty = true

        if key_value == ''
          o_forj_account.del(key_to_set)
        else
          o_forj_account.set(key_to_set, key_value)
        end

        s_aft = format_new_key(o_forj_account, key_to_set)

        puts format(
                 '%-25s: %s => %s',
                 full_key,
                 s_bef,
                 ANSI.bold + s_aft + ANSI.clear
             )
      end
      o_forj_account.ac_save if b_dirty
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
      if Lorj::Default.get_meta_section(key).nil?
        PrcLib.warning(
            format(
                "key '%s' is not a recognized default key by forj process. ",
                key
            )
        )
      end
    end

    def self.config_set(oConfig, *p)
      b_dirty = false

      p.flatten!
      p.each do | key_val |
        mkey_val = valid_key_value?(key_val)

        key_to_set = mkey_val[1]
        key_value = mkey_val[2]

        s_bef = 'unset'
        s_aft = 'unset'

        valid_key?(key_to_set)

        old_value = oConfig.get(key_to_set)
        s_bef = format(
            "%s: '%s'",
            oConfig.exist?(key_to_set),
            oConfig.get(key_to_set)
        ) if oConfig.exist?(key_to_set)

        if old_value == key_value
          puts format('%-15s: No update', key_to_set)
          next
        end

        b_dirty = true

        if key_value != ''
          oConfig.localSet(key_to_set, key_value)
        else
          oConfig.localDel(key_to_set)
        end

        s_aft = format(
            "%s: '%s'",
            oConfig.exist?(key_to_set),
            oConfig.get(key_to_set)
        ) if oConfig.exist?(key_to_set)
        puts format(
                 '%-15s: %s => %s',
                 key_to_set,
                 s_bef,
                 ANSI.bold + s_aft + ANSI.clear
             )
      end
      oConfig.saveConfig if b_dirty
    end

    def self.get_highlight(account_name, key_exist)
      highlight = ''
      highlight = ANSI.bold if key_exist == account_name
      highlight = ANSI.bold + ANSI.yellow if key_exist == 'local'
      highlight
    end

    def self.get_account_values(o_forj_account, account_name)
      o_forj_account.metadata_each do | section, mykey, hValue |
        key_exist = o_forj_account.exist?(mykey)

        s_upd_msg = '+'
        s_upd_msg = ' ' if Lorj.rhGet(hValue, :readonly)

        if key_exist
          highlight = get_highlight(account_name, key_exist)
          default_key = nil
          default_key = format(
              " (from default key '%s')",
              Lorj.rhGet(hValue, :default)
          ) if Lorj.rhExist?(hValue, :default) == 1 &&
               key_exist != account_name

          puts format(
                  "%s %-15s(%s%-7s%s) %-12s: '%s'%s",
                  s_upd_msg,
                  mykey,
                  highlight,
                  key_exist,
                  ANSI.clear,
                  section,
                  o_forj_account.get(mykey),
                  default_key
               )
        else
          puts format(
                   '%s %-15s(       ) %-12s: unset',
                   s_upd_msg,
                   mykey,
                   section
               )
        end
      end
    end

    def self.account_get_all(oConfig, account_name)
      oConfig.set(:account_name, account_name)
      o_forj_account = Lorj::Account.new(oConfig)

      PrcLib.fatal(
          1,
          format("Unable to load account '%s'. Not found.", account_name)
      ) unless o_forj_account.ac_load

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

      get_account_values(o_forj_account, account_name)

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

    def self.config_get_all(oConfig)
      puts 'legend: default = Application defaults, local = Local default' \
        ' config\n\n'
      puts format(
               '%s %-15s(%-7s) %-12s:\n-----------------------------------' \
                 '-----', 'U',
               '''key', 'origin',
               'section name'
           )

      oConfig.meta_each do |section, found_key, hValue|
        s_upd_msg = '+'
        s_upd_msg = ' ' if Lorj.rhGet(hValue, :readonly)
        found_key = Lorj.rhGet(
            hValue,
            :default
        ) if Lorj.rhExist?(hValue, :default) == 1

        where = oConfig.exist?(found_key)
        if where
          highlight = ''
          highlight = ANSI.bold + ANSI.yellow if where == 'local'
          puts format(
                   "%s %-15s(%s%-7s%s) %-12s: '%s'",
                   s_upd_msg,
                   found_key,
                   highlight,
                   where,
                   ANSI.clear,
                   section,
                   oConfig.get(found_key)
               )
        else
          puts format(
                   '%s %-15s(       ) %-12s: unset',
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
      oConfig.set(:account_name, account_name)
      o_forj_account = Lorj::Account.new(oConfig)

      PrcLib.fatal(
          1,
          format("Unable to load account '%s'. Not found.", account_name)
      ) unless o_forj_account.ac_load

      if o_forj_account.exist?(key)
        puts format(
                 "%s: '%s'",
                 o_forj_account.exist?(key),
                 o_forj_account.get(key)
             )
      elsif o_forj_account.exist?(key.parameterize.underscore.to_sym)
        key_symb = key.parameterize.underscore.to_sym
        puts format(
                 "%s: '%s'",
                 o_forj_account.exist?(key_symb),
                 o_forj_account.get(key_symb)
             )
      else
        PrcLib.message(format("key '%s' not found", key))
      end
    end

    def self.config_get(oConfig, key)
      if oConfig.exist?(key)
        puts format("%s:'%s'", oConfig.exist?(key), oConfig.get(key))
      else
        PrcLib.message(format("key '%s' not found", key))
      end
    end

    def self.show_settings(o_config, options)
      if !options[:account_name]
        config_show_all(o_config)
      else
        account_show_all(o_config, options[:account_name])
      end
    end

    def self.set_settings(o_config, options, p)
      if options[:account_name]
        account_set(o_config, options[:account_name], p)
      else
        config_set(o_config, p)
      end
    end
  end
end
