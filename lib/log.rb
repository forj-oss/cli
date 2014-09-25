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


# create a forj.log file in ~/.hpcloud/forj.log

require 'rubygems'
require 'logger'

require 'require_relative'

require_relative 'helpers.rb'
include Helpers


#
# Logging module
#
module Logging

  class SSLErrorMgt
  
    def initialize()
       @iRetry=0
    end
    
    def ErrorDetected(message,backtrace)
      if message.match('SSLv2/v3 read server hello A: unknown protocol') 
         if @iRetry <5
            sleep(2)
            @iRetry+=1
            print "%s/5 try...\r" % @iRetry if $FORJ_LOGGER.level == 0
            return false
         else   
            Logging.error('Too many retry. %s' % message)
            return true
         end
      else   
         Logging.error("%s\n%s" % [message,backtrace.join("\n")])
         return true
      end
    end

  end 

  class ForjLog
     # Class used to create 2 log object, in order to keep track of error in a log file and change log output to OUTPUT on needs (option flags).
     
     attr_reader :level

     def initialize(sLogFile = 'forj.log', level = Logger::WARN)
        
        if not $FORJ_DATA_PATH 
           raise "Internal Error: Unable to initialize ForjLog - global FORJ_DATA_PATH not set"
        end

        if not Helpers.dir_exists?($FORJ_DATA_PATH)
           raise "Internal Error: Unable to initialize ForjLog - '%s' doesn't exist." % $FORJ_DATA_PATH
        end

        @oFileLogger = Logger.new(File.join($FORJ_DATA_PATH, sLogFile), 'weekly')
        @oFileLogger.level = Logger::DEBUG
        @oFileLogger.formatter = proc do |severity, datetime, progname, msg| 
            "#{progname} : #{datetime}: #{severity}: #{msg} \n"
         end   
        
        @oOutLogger = Logger.new(STDOUT)
        @level = level
        @oOutLogger.level = @level
        @oOutLogger.formatter = proc do |severity, datetime, progname, msg| 
            severity == 'ANY'?"#{msg} \n":"#{severity}: #{msg} \n"
         end   
     end

     def info?
        return(@oOutLogger.info?)
     end
     def debug?
        return(@oOutLogger.debug?)
     end
     def error?
        return(@oOutLogger.error?)
     end
     def fatal?
        return(@oOutLogger.fatal?)
     end
     
     def info(message)
        @oOutLogger.info(message + ANSI.clear_line)
        @oFileLogger.info(message)
     end
     def debug(message)
        @oOutLogger.debug(message + ANSI.clear_line)
        @oFileLogger.debug(message)
     end
     def error(message)
        @oOutLogger.error(message + ANSI.clear_line)
        @oFileLogger.error(message)
     end
     def fatal(message, e)
        @oOutLogger.fatal(message + ANSI.clear_line)
        @oFileLogger.fatal("%s\n%s\n%s" % [message, e.message, e.backtrace.join("\n")]) if e
		@oFileLogger.fatal(message)
     end

     def warn(message)
        @oOutLogger.warn(message + ANSI.clear_line)
        @oFileLogger.warn(message)
     end

     def set_level(level)
        @level = level
        @oOutLogger.level = level
     end

     def unknown(message)
        @oOutLogger.unknown(message + ANSI.clear_line)
     end
     
  end
       
  def message(message)
    $FORJ_LOGGER.unknown(message)
  end
     
  def info(message)
    $FORJ_LOGGER.info(message)
  end
  
  def debug(message)
    $FORJ_LOGGER.debug(message)
  end
  
  def warning(message)
    $FORJ_LOGGER.warn(message)
  end

  def error(message)
    $FORJ_LOGGER.error(message)
  end
  
  def fatal(rc, message, e = nil)
    $FORJ_LOGGER.fatal(message, e)
    puts 'Issues found. Please fix it and retry. Process aborted.'
    exit rc
  end

  def set_level(level)
    $FORJ_LOGGER.set_level(level)
  end
  
  def state(message)
     print("%s ...%s\r" % [message, ANSI.clear_line]) if $FORJ_LOGGER.level == Logger::INFO
  end
  
  def high_level_msg(message)
     # Not DEBUG and not INFO. Just printed to the output.
     puts ("%s" % [message]) if $FORJ_LOGGER.level > 1
  end

end
