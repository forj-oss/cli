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

require 'highline/import'
require 'cloud_connection.rb'
#
# Boot module
#
module Forj
  # This module provides the behavior to boot your forge
  module Boot
    @account = nil
    attr_accessor :account

    def self.deprecated_name?(blueprint, on_or_name,
        old_accountname, as,
        old_name
                             )
      # depreciated: <BluePrint> on <AccountName> as <InstanceName>
      if old_accountname && as && old_name
        msg = format(
          "The syntax `forj boot '%s' on '%s' as '%s'`" \
        " is depreciated. \nUse `forj boot '%s' '%s' ",
          blueprint, old_accountname, old_name, blueprint, old_name
        )

        if account.get('account_name') == old_accountname
          PrcLib.warning('%s` instead.', msg)
        else
          PrcLib.warning("%s -a '%s'` instead.", msg, old_accountname)
        end
        name = old_name
        @account.set(:account_name, old_accountname)
      else
        name = on_or_name
      end
      name
    end

    def self.load_options(options, options_map)
      options_map.each do |opt_key, ac_key|
        unless options[opt_key].nil?
          value = yield(opt_key, options[opt_key])
          @account.set(ac_key, options[opt_key]) unless value.nil?
        end
      end
    end

    def self.validate_keypath(options)
      if options[:key_path]
        m_found = options[:key_path].match(/^(.*)(\.pub)?$/)
        if m_found
          key_path = File.expand_path(m_found[1])
          if m_found[2] && !(File.exist?(
            File.expand_path(m_found[1] + m_found[2])
          ))
            PrcLib.fatal(
              1,
              "'%s' is not a valid keypair files." \
              ' At least the public key (.pub) is have to exist.',
              key_path
            )
          end
          @account.set(:keypair_path, key_path)
        else
          PrcLib.fatal(
            1,
            "'%s' is not a valid keypair files." \
            'At least the public key (.pub) is have to exist.',
            key_path
          )
        end
      end
    end

    def self.install_blueprint?(blueprint, name)
      @account[:instance_name] = name

      if blueprint == 'maestro'
        PrcLib.info("Starting boot process of '%s'. No blueprint requested.",
                    @account[:instance_name])
      else
        @account[:blueprint] = blueprint
        PrcLib.info("Starting boot process of '%s' with blueprint '%s'.",
                    @account[:instance_name], @account[:blueprint])
      end
    end

    # rubocop: disable Metrics/CyclomaticComplexity
    # rubocop: disable Metrics/MethodLength

    # Boot process
    def self.boot(blueprint, on_or_name, deprecated_name, options)
      @account = Lorj::Account.new(options[:config])

      name = deprecated_name?(blueprint, on_or_name, deprecated_name[0],
                              deprecated_name[1], deprecated_name[2])

      PrcLib.fatal(1, "instance name '%s' not supported. Support only lower" \
                   ' case, numeric and dash caracters.',
                   name) unless /^[\d[[:lower:]]-]+$/ =~ name

      # Options are added if they are set.
      # Otherwise, get will retrieve the default value.

      @account[:account_name] = options[:account_name] if options[:account_name]

      unless @account.ac_load @account[:account_name]
        PrcLib.fatal(1, "Account '%s' not loaded. You need to call "\
                     '`forj setup %s [provider]` to use this account.',
                     @account[:account_name], @account[:account_name])
      end

      options_map = { :infra          => :infra_repo,
                      :key_name       => :keypair_name,
                      :key_path       => :keypair_path,
                      :security_group => :security_group,
                      :image_name     => :image_name,
                      :maestro_flavor => :flavor,
                      :bp_flavor      => :bp_flavor,
                      :maestro_repo   => :maestro_repo,
                      :branch         => :branch,
                      :test_box       => :test_box,
                      :extra_metadata => :extra_metadata }

      load_options(options, options_map) do |key, value|
        case key
        when :test_box
          path = File.expand_path(value)
          return path if File.directory?(path)
          return nil
        end
        value
      end

      PrcLib.warning(
        'test_box is currently disabled in this version.' \
        'It will be re-activated in newer version.'
      ) if options[:test_box]

      validate_keypath(options)

      # o_cloud = get_o_cloud(o_forj_account)
      o_cloud = Forj::CloudConnection.connect(@account)

      install_blueprint?(blueprint, name)
      PrcLib.high_level_msg("Preparing your forge '%s'.Please be patient. "\
                            "more output in '%s'\n",
                            @account[:instance_name],
                            PrcLib.log_file)

      o_cloud.create(:forge)
    end
  end
end
