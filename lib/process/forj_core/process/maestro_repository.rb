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

# Functions for boot - clone_or_use_maestro_repo
class ForjCoreProcess
  def clone_maestro_repo(maestro_url, path_maestro, config)
    PrcLib.state("Cloning maestro repo from '%s' to '%s'",
                 maestro_url, File.join(path_maestro, 'maestro'))
    if File.directory?(path_maestro)
      if File.directory?(File.join(path_maestro, 'maestro'))
        FileUtils.rm_r File.join(path_maestro, 'maestro')
      end
    end
    git = Git.clone(maestro_url, 'maestro', :path => path_maestro)
    git.checkout(config[:branch]) if config[:branch] != 'master'
    PrcLib.info("Maestro repo '%s' cloned on branch '%s'",
                File.join(path_maestro, 'maestro'), config[:branch])
  end

  def clone_or_use_maestro_repo(sObjectType, hParams)
    maestro_url = hParams[:maestro_url]
    maestro_repo = File.expand_path(
      hParams[:maestro_repo]
    ) unless hParams[:maestro_repo].nil?
    path_maestro = File.expand_path('~/.forj/')
    h_result = {}

    begin
      if maestro_repo && File.directory?(maestro_repo)
        PrcLib.info("Using maestro repo '%s'", maestro_repo)
        h_result[:maestro_repo] = maestro_repo
      else
        h_result[:maestro_repo] = File.join(path_maestro, 'maestro')
        clone_maestro_repo(maestro_url, path_maestro, config)
      end
   rescue => e
     PrcLib.error("Error while cloning the repo from %s\n%s\n%s"\
                  "\nIf this error persist you could clone the repo manually"\
                  " in '%s'",
                  maestro_url, e.message, e.backtrace.join("\n"),
                  h_result[:maestro_repo])
    end
    o_maestro = register(h_result, sObjectType)
    o_maestro[:maestro_repo] = h_result[:maestro_repo]
    o_maestro[:maestro_repo_exist?] = File.directory?(h_result[:maestro_repo])
    o_maestro
  end
end
