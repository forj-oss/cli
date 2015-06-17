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

        if account.get(:account_name) == old_accountname
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
        if options.key?(opt_key)
          value = yield(opt_key, options[opt_key])
          @account.set(ac_key, value) unless value.nil?
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
  end
  # rubocop: disable Metrics/CyclomaticComplexity
  # rubocop: disable Metrics/MethodLength

  #
  module Boot
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

      options[:tb_path] = nil if options.key?(:test_box) &&
                                 !options.key?(:tb_path)
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
                      :tb_path        => :test_box_path,
                      :ca_root_cert   => :ca_root_cert,
                      :extra_metadata => :extra_metadata,
                      :webproxy       => :webproxy }

      load_options(options, options_map) { |k, v| complete_boot_options(k, v) }

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
  # rubocop: enable Metrics/CyclomaticComplexity
  # rubocop: enable Metrics/MethodLength

  #
  module Boot
    # Take care of special options cases for boot.
    def self.complete_boot_options(key, value)
      case key
      when :test_box
        value = tb_repo_detect(value)
      when :tb_path
        value = tb_bin_detect(value)
      when :ca_root_cert
        value = ca_root_file_detect(value)
      end
      value
    end

    # Function to check the repository path passed.
    def self.tb_repo_detect(paths)
      res = {}
      paths.each do |path|
        PrcLib.debug("tb_repo_detect: checking #{path}")
        cmd = <<-CMD
cd "#{path}"
git rev-parse --show-toplevel 2>/dev/null 1>&2
if [ $? -ne 0 ]
then
   exit 1
fi
REPO_TO_ADD="$(LANG= git remote show origin -n |
                     awk '$1 ~ /Fetch/ { print $3 }')"
if [ "$REPO_TO_ADD" = "" ]
then
   exit 1
fi
echo $REPO_TO_ADD
pwd
        CMD
        cmd_res = `#{cmd}`.split
        # For any reason, $CHILD_STATUS is empty, while $? is not.
        # Ruby bug. tested with:
        # ruby 2.0.0p353 (2013-11-22 revision 43784) [x86_64-linux]
        # rubocop: disable Style/SpecialGlobalVars
        unless $?.exitstatus == 0
          PrcLib.warning("tb_repo_detect: #{path} seems not to be a GIT "\
                         "repo.\n"\
                         "#{cmd_res.join("\n")}")
          next
        end
        # rubocop: enable Style/SpecialGlobalVars
        repo_found = cmd_res[0].match(%r{.*/(.*)(.git)?})
        unless repo_found
          PrcLib.warning("tb_repo_detect: Unable to find the repo path.\n"\
                         "#{cmd_res.join("\n")}")

          next
        end
        res[repo_found[1]] = cmd_res[1]
        PrcLib.debug("tb_repo_detect: FOUND #{cmd_res[1]}")
      end
      res
    end

    # function to detect if test-box.sh is runnable
    #
    # It returns the script to execute.
    def self.tb_bin_detect(tb_path)
      tb_path = ENV['TEST_BOX'] if tb_path.nil?
      tb_path = File.expand_path(tb_path) unless tb_path.nil?

      script = 'test-box.sh'
      if tb_path && File.directory?(tb_path)
        script_found = tb_check_bin(tb_path)
        script = File.expand_path(File.join(tb_path, script))
        if script_found.nil?
          PrcLib.error("Test-box: '%s' is not a valid runnable script. "\
                       'test-box is disabled.', script)
          return nil
        end
        PrcLib.debug("tb_repo_detect: FOUND #{script_found}")
        return script_found
      end

      script_found = nil

      ENV['PATH'].split(':').each do |path|
        script_found = tb_check_bin(path)
        break unless script_found.nil?
      end
      PrcLib.debug("tb_repo_detect: FOUND #{script_found}")

      script_found
    end

    # Script to check the bin and path
    def self.tb_check_bin(tb_path)
      script = 'test-box.sh'
      script = File.expand_path(File.join(tb_path, script))
      return script if File.executable?(script)
      nil
    end

    def self.ca_root_file_detect(param)
      res_found = param.match(/^(.*)#(.*)$/)

      if res_found
        cert_file = File.expand_path(res_found[1])
      else
        cert_file = File.expand_path(param)
      end

      unless File.readable?(cert_file)
        PrcLib.error("Unable to read the Root Certificate file '%s'", cert_file)
        return nil
      end
      param
    end
  end
end
