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

    unless hParams[:maestro_repository, :maestro_repo_exist?]
      PrcLib.fatal(1, "Maestro repository doesn't exist. This is required for "\
                      "cloud_init user_data build. Check why '%s' "\
                      "doesn't exist.",
                   hParams[:maestro_repository, :maestro_repo])
    end

    meta_data = JSON.generate(hParams[:metadata, :meta_data])

    build_tmpl_dir = File.expand_path(File.join(LIB_PATH, 'build_tmpl'))

    PrcLib.state("Preparing user_data - file '%s'", mime)
    # generate boot_*.sh
    mime_cmd = "#{build_tmpl_dir}/write-mime-multipart.py"
    bootstrap = "#{build_tmpl_dir}/bootstrap_build.sh"

    cmd = format(
      "%s '%s' '%s' '%s' '%s' '%s' '%s' '%s'",
      bootstrap, # script
      # $1 = Forj data base dir
      PrcLib.data_path,
      # $2 = Maestro repository dir
      hParams[:maestro_repository, :maestro_repo],
      # $3 = Bootstrap directories
      hParams[:infra_repository, :infra_repo] + ' ' +
      config.get(:bootstrap_dirs, ''),
      # $4 = Bootstrap extra directory
      config[:bootstrap_extra_dir],
      # $5 = meta_data (string)
      meta_data,
      # $6: mime script file to execute.
      mime_cmd,
      # $7: mime file generated.
      mime
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
      Lorj.debug(5, "user_data temp file '%s' kept", mime)
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
