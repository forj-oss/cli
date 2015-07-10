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

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

$stdout.sync = true
$stderr.sync = true

task :default => [:lint, :spec]

task :build => [:lint, :spec]

desc 'Run the specs.'
RSpec::Core::RakeTask.new do |t|
  t.pattern = 'spec/*_spec.rb'
  t.rspec_opts = '-f doc'
end

desc 'Run RuboCop on the project'
RuboCop::RakeTask.new(:lint) do |task|
  task.formatters = ['progress']
  task.verbose = true
  task.fail_on_error = true
end
