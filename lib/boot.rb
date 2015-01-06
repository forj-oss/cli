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
    @o_config = nil
    attr_accessor :o_config

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

        if o_config.get('account_name') == old_accountname
          PrcLib.warning(format('%s` instead.', msg))
        else
          PrcLib.warning(format("%s -a '%s'` instead.", msg, old_accountname))
        end
        name = old_name
        @o_config.set(:account_name, old_accountname)
      else
        name = on_or_name
      end
      name
    end

    def self.load_options(options)
      @o_config.set(:infra_repo,     options[:infra])
      @o_config.set(:keypair_name,   options[:key_name])
      @o_config.set(:keypair_path,   options[:key_path])
      @o_config.set(:security_group, options[:security_group])
      @o_config.set(:image_name,     options[:image_name])
      @o_config.set(:flavor,         options[:maestro_flavor])
      @o_config.set(:bp_flavor,      options[:bp_flavor])
      @o_config.set(:maestro_repo,   options[:maestro_repo])
      @o_config.set(:branch,         options[:branch])
      @o_config.set(
          :test_box,
          File.expand_path(options[:test_box])
      ) if options[:test_box] && File.directory?(
          File.expand_path(options[:test_box])
      )
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
                ' At least the public key (.pub) is have to exist.'
            )
          end
          @o_config.set(:keypair_path, key_path)
        else
          PrcLib.fatal(
              1,
              "'%s' is not a valid keypair files." \
              'At least the public key (.pub) is have to exist.'
          )
        end
      end
    end

    def self.install_blueprint?(blueprint, name)
      @o_config[:instance_name] = name

      if blueprint == 'maestro'
        PrcLib.info(
            format(
                "Starting boot process of '%s'. No blueprint requested.",
                @o_config[:instance_name])
        )
      else
        @o_config[:blueprint] = blueprint
        PrcLib.info(
            format(
                "Starting boot process of '%s' with blueprint '%s'.",
                @o_config[:instance_name], @o_config[:blueprint]
            )
        )
      end
    end

    def self.boot(blueprint, on_or_name, deprecated_name, options)
      @o_config = Lorj::Config.new(options[:config])

      name = deprecated_name?(blueprint, on_or_name, deprecated_name[0],
                              deprecated_name[1], deprecated_name[2])

      PrcLib.fatal(
          1,
          format(
              "instance name '%s' not supported. Support only lower case," \
              ' numeric and dash caracters.',
              name
          )
      ) unless /^[\d[[:lower:]]-]+$/ =~ name

      # Options are added if they are set.
      # Otherwise, get will retrieve the default value.
      @o_config.set(
          :account_name,
          options[:account_name]
      ) if options[:account_name]
      o_forj_account = Lorj::Account.new(@o_config)
      o_forj_account.ac_load

      load_options(options)

      PrcLib.warning(
          'test_box is currently disabled in this version.' \
          'It will be re-activated in newer version.'
      ) if options[:test_box]

      validate_keypath(options)

      # o_cloud = get_o_cloud(o_forj_account)
      o_cloud = Forj::CloudConnection.connect(@o_config)

      install_blueprint?(blueprint, name)
      PrcLib.high_level_msg(
          format(
              "Preparing your forge '%s'." \
              "Please be patient. more output in '%s'\n",
              @o_config[:instance_name], File.join($FORJ_DATA_PATH, 'forj.log')
          )
      )

      o_cloud.Create(:forge)
    end
  end
end
