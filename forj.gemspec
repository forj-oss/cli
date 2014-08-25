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

  s.version     = '0.0.36'
  s.date        = '2014-08-25'
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
                     lib/yaml_parse.rb
                     lib/defaults.yaml
                     lib/down.rb lib/boot.rb
                     lib/setup.rb
                     lib/repositories.rb
                     lib/ssh.rb
                     lib/ssh.sh
                     lib/log.rb
                     lib/helpers.rb
                     lib/build_tmpl/build-env.py
                     lib/forj-config.rb
                     spec/boot_spec.rb
                     spec/connection_spec.rb
                     spec/down_spec.rb
                     spec/network_spec.rb
                     spec/repositories_spec.rb
                     spec/setup_spec.rb
                     spec/spec_helper.rb
                     spec/ssh_spec.rb
                     spec/yaml_parse_spec.rb
                     spec/forj-config_spec.rb
                     Rakefile
                     Gemfile
                     README.md)

  s.homepage    = 'https://forj.io'
  s.license     = 'Apache License, Version 2.0.'
  s.post_install_message = 'Go to docs.forj.io for more information on how to use forj cli'
  s.required_ruby_version = '>= 1.8.5'

  s.bindir = 'bin'

  s.add_runtime_dependency 'thor', '>=0.16.0'
  s.add_runtime_dependency 'nokogiri', '~>1.5.11'
  s.add_runtime_dependency 'fog', '~>1.19.0'
  s.add_runtime_dependency 'hpcloud', '~>2.0.8'
  s.add_runtime_dependency 'git', '>=1.2.7'
  s.add_runtime_dependency 'rbx-require-relative', '~>0.0.7'
  s.add_runtime_dependency 'highline', '~> 1.6.21'
  s.add_runtime_dependency 'ansi', '>= 1.4.3'
end
