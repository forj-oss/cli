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

  s.version     = '1.0.16'
  s.date        = '2015-06-25'
  s.summary     = 'forj command line'
  s.description = 'forj cli - See https://www.forj.io for documentation/information'

  s.authors     = ['forj team']
  s.email       = %w(forj@forj.io)

  s.files         = `git ls-files -z`.split("\x0")
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.homepage    = 'https://forj.io'
  s.license     = 'Apache License, Version 2.0.'
  s.post_install_message = 'Go to docs.forj.io for more information on how to use forj cli'
  s.required_ruby_version = '>= 1.9.3'

  s.bindir = 'bin'

  ## This gets added to the $LOAD_PATH so that 'lib/NAME.rb' can be required as
  ## require 'NAME.rb' or'/lib/NAME/file.rb' can be as require 'NAME/file.rb'
  s.require_paths = %w[lib]

  s.add_runtime_dependency 'thor', '>=0.16.0'
  s.add_runtime_dependency 'git', '>=1.2.7'
  s.add_runtime_dependency 'highline', '>= 1.6.21'
  s.add_runtime_dependency 'ansi', '>= 1.4.3'
  s.add_runtime_dependency 'encryptor', '>=1.3.0'
  s.add_runtime_dependency 'json', '1.7.5'
  s.add_runtime_dependency 'bundler'
  s.add_runtime_dependency 'nokogiri','1.5.11'
  s.add_runtime_dependency 'lorj_cloud', '>= 0.1.6'

  s.add_development_dependency "rake", "~> 10.0"
  s.add_development_dependency "rspec", "~> 3.1.0"
  if RUBY_VERSION.match(/1\.8/)
    s.add_development_dependency "ruby-debug"
  elsif RUBY_VERSION.match(/1\.9/)
    s.add_development_dependency "debugger"
    s.add_development_dependency "rubocop", ">= 0.30.0"
  else
    s.add_development_dependency "byebug"
    s.add_development_dependency "rubocop", ">= 0.30.0"
  end
  s.rdoc_options << '--title' << 'Lorj - The Process Controllers framework system' <<
  '--main' << 'README.md'
end
