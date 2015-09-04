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

INFRA_VERSION = '0.0.37'

# Functions for :infra_repository object type.
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
end

# Internal functions for :infra_repository object type
class ForjCoreProcess
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

# Internal functions for :infra_repository object type
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
