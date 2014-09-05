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

require 'rubygems'


#
# Setup module call the hpcloud functions
#
module Setup
   def setup(oConfig)

      # TODO: Provide a way to re-edit all or partially elements set up by this function.
      begin
         oForjAccount = ForjAccount.new(oConfig)

         oForjAccount.ac_load()
         # TODO: Provide a way to update partially some account data.
         oForjAccount.setup() # any kind of setup, ask from users.

         oForjAccount.ac_save()

      rescue RuntimeError => e
         Logging.fatal(1,e.message)
      rescue  => e
         Logging.fatal(1,"Unable to run setup" , e)
      end
  end
end
