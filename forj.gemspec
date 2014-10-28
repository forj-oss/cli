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

Gem::Specification.new do |s|
  s.name        = 'forj'
  s.homepage = 'https://www.forj.io'

  s.version     = '1.0.1'
  s.date        = '2014-10-28'
  s.summary     = 'forj command line'
  s.description = 'forj cli - See https://www.forj.io for documentation/information'

  s.authors     = ['forj team']
  s.email       = %w(forj@forj.io)

  s.executables = ['forj']
  s.files       = %w(bin/forj
                     lib/compute.rb
                     lib/connection.rb
                     lib/network.rb
                     lib/security.rb
                     lib/defaults.yaml
                     lib/down.rb
                     lib/appinit.rb
                     lib/forj-settings.rb
                     lib/repositories.rb
                     lib/ssh.rb
                     lib/ssh.sh
                     lib/log.rb
                     lib/helpers.rb
                     lib/forj-config.rb
                     lib/forj-account.rb
                     lib/build_tmpl/bootstrap_build.sh
                     lib/build_tmpl/write-mime-multipart.py                     
                     lib/forj/ForjCore.rb
                     lib/forj/ForjCli.rb
                     lib/forj/process/ForjProcess.rb
                     lib/lib-forj/lib/providers/templates/compute.rb
                     lib/lib-forj/lib/providers/templates/network.rb
                     lib/lib-forj/lib/providers/templates/core.rb
                     lib/lib-forj/lib/providers/hpcloud/security_groups.rb
                     lib/lib-forj/lib/providers/hpcloud/Hpcloud.rb
                     lib/lib-forj/lib/providers/hpcloud/compute.rb
                     lib/lib-forj/lib/providers/hpcloud/network.rb
                     lib/lib-forj/lib/core_process/global_process.rb
                     lib/lib-forj/lib/core_process/CloudProcess.rb
                     lib/lib-forj/lib/core_process/network_process.rb
                     lib/lib-forj/lib/core/definition.rb
                     lib/lib-forj/lib/core/core.rb
                     lib/lib-forj/lib/core/definition_internal.rb
                     lib/lib-forj/lib/lib-forj.rb
                     spec/boot_spec.rb
                     spec/connection_spec.rb
                     spec/down_spec.rb
                     spec/network_spec.rb
                     spec/repositories_spec.rb
                     spec/setup_spec.rb
                     spec/spec_helper.rb
                     spec/ssh_spec.rb
                     spec/forj-config_spec.rb
                     Rakefile
                     Gemfile
                     README.md)

  s.homepage    = 'https://forj.io'
  s.license     = 'Apache License, Version 2.0.'
  s.post_install_message = 'Go to docs.forj.io for more information on how to use forj cli'
  s.required_ruby_version = '>= 1.8.5'

  s.bindir = 'bin'

  ## This gets added to the $LOAD_PATH so that 'lib/NAME.rb' can be required as
  ## require 'NAME.rb' or'/lib/NAME/file.rb' can be as require 'NAME/file.rb'
  s.require_paths = %w[lib]

  s.add_runtime_dependency 'thor', '~>0.16.0'
  s.add_runtime_dependency 'nokogiri', '~>1.5.11'
  s.add_runtime_dependency 'fog', '~>1.19.0'
  s.add_runtime_dependency 'hpcloud', '~>2.0.9'
  s.add_runtime_dependency 'git', '>=1.2.7'
  s.add_runtime_dependency 'rbx-require-relative', '~>0.0.7'
  s.add_runtime_dependency 'highline', '~> 1.6.21'
  s.add_runtime_dependency 'ansi', '>= 1.4.3'
  s.add_runtime_dependency 'encryptor', '1.3.0'
  s.add_runtime_dependency 'json', '1.7.5'

end
