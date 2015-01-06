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

require 'lorj'

# Module to initialize the application
# TODO: Cleanup about Global variables used. Should be replaced by PrcLib
#       or other kind of setting.
module AppInit
  def self.forj_initialize
    # Function to create FORJ paths if missing.

    # Defining Global variables
    $FORJ_DATA_PATH = File.expand_path(File.join('~', '.forj'))
    $FORJ_ACCOUNTS_PATH = File.join($FORJ_DATA_PATH, 'accounts')
    $FORJ_KEYPAIRS_PATH = File.join($FORJ_DATA_PATH, 'keypairs')
    $FORJ_BUILD_PATH = File.join($FORJ_DATA_PATH, '.build')
    $FORJ_CREDS_PATH = File.expand_path(File.join('~', '.cache', 'forj'))

    # TODO: To move to an hpcloud object.
    $HPC_KEYPAIRS = File.expand_path(File.join('~', '.hpcloud', 'keypairs'))
    $HPC_ACCOUNTS = File.expand_path(File.join('~', '.hpcloud', 'accounts'))

    AppInit.ensure_dir_exists($FORJ_DATA_PATH)
    AppInit.ensure_dir_exists($FORJ_ACCOUNTS_PATH)
    AppInit.ensure_dir_exists($FORJ_BUILD_PATH)
    AppInit.ensure_dir_exists($FORJ_KEYPAIRS_PATH)
    FileUtils.chmod(0700, $FORJ_KEYPAIRS_PATH)
    AppInit.ensure_dir_exists($FORJ_CREDS_PATH)
  end

  def self.ensure_dir_exists(path)
    unless PrcLib.dir_exists?(path)
      FileUtils.mkpath(path) unless File.directory?(path)
    end
  end
end
