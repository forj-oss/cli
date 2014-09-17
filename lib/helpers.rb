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

require 'fileutils' 

module Helpers
  def get_home_path
    File.expand_path('~')
  end

  def create_directory(path)
    unless File.directory?(path)
      Dir.mkdir path
    end
  end
  
  def dir_exists?(path)
    if File.exists?(path)
       if not File.directory?(path)
          msg = "'%s' is not a directory. Please fix it." % path
          if $FORJ_LOGGER
             Logging.fatal(1, msg)
          else
             raise msg
          end
       end
       if not File.readable?(path) or not File.writable?(path) or not File.executable?(path)
          msg = "%s is not a valid directory. Check permissions and fix it." % path
          if $FORJ_LOGGER
             Logging.fatal(1, msg)
          else
             raise msg
          end
       end
       return true
    end
    false
  end
  

  
end
