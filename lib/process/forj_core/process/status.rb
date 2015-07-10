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

# Implementation of ForgeStatus for forge_boot sequences
class ForjCoreProcess
  # Class to manage the Forge status at boot time.
  #
  class ForgeStatus
    attr_reader :status
    attr_accessor :prev_log, :error

    # At progress execution, execute a method
    # when status has changed to a special value
    def change_event(status, method, binding)
      @events[status] = [method, binding]
    end

    def initialize(status = :checking)
      @status = status
      @cur_act = 0
      @pending_count = 0
      @old_status = @status
    end

    def is(status)
      @status = status
    end

    def changed?
      ret = (@old_status != status)
      @old_status = @status
      ret
    end

    def running?
      @status != :active
    end

    def done
      @status = :active
    end

    def progress
      return if @cur_act == 4
      @pending_count = 0
      @cur_act += 1
      @cur_act = @cur_act % 4
      return if @old_status == @status || @event[@status].nil?
      task = method(@event[@status][0])
      task.call(@event[@status][1]) unless task.nil?
      @old_status = @status
    end

    def pending(state, maestro, hParams)
      unless state
        @cur_act = 0 if @cur_act == 4
        return
      end
      @pending_count += 1
      @cur_act = 4
      return unless @pending_count == 60
      highlight = ANSI.yellow('-' * 40)
      ssh_user = hParams[:image, :ssh_user]
      network_used = maestro[:meta_data, 'network_name']
      public_ip = maestro[:public_ip_addresses, network_used]
      key = hParams[:keypairs, :keys]
      PrcLib.warning("No more server activity detected.\n"\
                     "#{highlight}\n"\
                     "%s\n"\
                     "#{highlight}\n"\
                     "The server '%s' is not providing any output log for"\
                     " more than 5 minutes.\nPlease review the current "\
                     'output shown below to determine if this is a normal '\
                     "situation.\nYou can connect to the server if you "\
                     "want to.\nTo connect, use:\n"\
                     'ssh %s@%s -o StrictHostKeyChecking=no -i %s',
                     @prev_log, maestro[:name], ssh_user, public_ip, key)
    end

    # Function displaying the server status
    def display
      activity = '/-\\|?'
      if @cur_act < 4
        cur_act = 'ACTIVE'
      else
        cur_act = format('%s - %d s', ANSI.bold('PENDING'),
                         (@pending_count + 1) * 5)
      end

      state = {
        :checking   => 'Checking server status',
        :starting   => 'STARTING',
        :assign_ip  => '%s - %s - Assigning Public IP',
        :cloud_init => '%s - %s - Currently running cloud-init. Be patient.',
        :nonet      => '%s - %s - Currently running cloud-init. Be patient.',
        :restart    => 'RESTARTING - Currently restarting maestro box. '\
                       'Be patient.',
        :in_error   => 'The server creation is in error.',
        :active     => 'Server is active',
        :disappeared => 'The server has disappeared. Trying to get it back.'
      }
      case @status
      when :checking, :starting, :restart, :in_error, :disappeared
        PrcLib.state(state[@status])
      when :assign_ip, :cloud_init, :nonet
        PrcLib.state(state[@status], activity[@cur_act], cur_act)
      when :active
        PrcLib.info(state[@sStatus])
      end
    end
  end
end
