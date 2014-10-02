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

module Forj
   module Settings
      def Settings.account_show_all(oConfig, account_name)
         oConfig.set(:account_name, account_name)

         oForjAccount = ForjAccount.new(oConfig)
         oForjAccount.ac_load()
         puts "List of account settings for provider '%s': " % [oForjAccount.get(:provider)]
         puts "%-15s %-12s :\n------------------------------" % ['key', 'section name']

         oForjAccount.metadata_each { |section, found_key, hValue|
            next if rhGet(hValue, :readonly)            
            sDesc = rhGet(hValue, :desc)
            puts "%-15s %-12s : %s" % [found_key, section, sDesc]
            }
         puts "\nUse `forj set KeyName=Value -a %s` to set one." % [ account_name]
         puts "Use `forj get -a %s`               to check current values." % [ account_name]
      end

      def Settings.config_show_all(oConfig)
         puts "List of available FORJ default settings:"
         puts "%-15s %-12s :\n------------------------------" % ['key', 'section name']
         oConfig.meta_each { |section, found_key, hValue|
            next if rhGet(hValue, :readonly)            
            sDesc = rhGet(hValue, :desc)
            puts "%-15s %-12s : %s" % [found_key, section, sDesc]
            }
         puts "\nUse `forj set KeyName=Value` to set one. "
         puts "Use `forj get`               to get current values. "
      end

      def Settings.account_set(oConfig, account_name, *p)
         bDirty = false

         oConfig.set(:account_name, account_name)

         oForjAccount = ForjAccount.new(oConfig)
         oForjAccount.ac_load()

         p.flatten!
         p.each { | key_val |
            mkey_val = key_val.match(/^(.*) *= *(.*)$/)
            
            Logging.fatal(1, "Syntax error. Please set your value like: 'key=value' and retry.") if not mkey_val

            key_to_set = mkey_val[1]
            key_value = mkey_val[2]

            sBef = "unset"
            sAft = "unset"
            
            Logging.fatal(1, "Unable to update protected '%s'. use `forj setup`, to update it." % key_to_set) if oForjAccount.readonly?(key_to_set)
            if oForjAccount.meta_type?(key_to_set) == :default
               Logging.fatal(1, "Unable set '%s' value. To update this one, use forj set %s, WITHOUT -a %s" % [key_to_set, key_to_set, account_name])
            end

            full_key = '%s/%s' % [ForjDefault.get_meta_section(key_to_set), key_to_set]

            old_value = oForjAccount.get(key_to_set)
            sBef = "'%s' (%s)" % [old_value, oForjAccount.exist?(key_to_set)] if oForjAccount.exist?(key_to_set)

            if old_value == key_value
               puts "%-25s: No update" % [full_key]
               next
            end
            bDirty = true

            if key_value == ""
               oForjAccount.del(key_to_set)
            else
               oForjAccount.set(key_to_set, key_value)
            end

            sAft = "'%s' (%s)" % [oForjAccount.get(key_to_set), oForjAccount.exist?(key_to_set)] if oForjAccount.exist?(key_to_set)
            puts "%-25s: %s => %s" % [full_key, sBef, ANSI.bold+sAft+ANSI.clear]
            }
         oForjAccount.ac_save() if bDirty
      end
      
      def Settings.config_set(oConfig, *p)
         bDirty = false

         p.flatten!
         p.each { | key_val |
            mkey_val = key_val.match(/^(.*) *= *(.*)$/)
            
            Logging.fatal(1, "Syntax error. Please set your value like: 'key=value' and retry.") if not mkey_val

            key_to_set = mkey_val[1]
            key_value = mkey_val[2]

            sBef = "unset"
            sAft = "unset"
            
            old_value = oConfig.get(key_to_set)
            sBef = "%s: '%s'" % [oConfig.exist?(key_to_set), oConfig.get(key_to_set)] if oConfig.exist?(key_to_set)
            
            if old_value == key_value
               puts "%-15s: No update" % [key_to_set]
               next
            end
            
            bDirty = true
            
            if key_value != ""
               oConfig.LocalSet(key_to_set, key_value)
            else
               oConfig.LocalDel(key_to_set)
            end

            sAft = "%s: '%s'" % [oConfig.exist?(key_to_set), oConfig.get(key_to_set)] if oConfig.exist?(key_to_set)
            puts "%-15s: %s => %s" % [key_to_set, sBef, ANSI.bold+sAft+ANSI.clear]
            }
         oConfig.SaveConfig() if bDirty
      end

      def Settings.account_get_all(oConfig, account_name)
         oConfig.set(:account_name, account_name)
         oForjAccount = ForjAccount.new(oConfig)
         Logging.fatal(1, "Unable to load account '%s'. Not found." % account_name) if not oForjAccount.ac_load
         
         puts "legend: default = Application defaults, local = Local default config, %s = '%s' account config\n\n" % [account_name, account_name]
         puts "%s %-15s(%-7s) %-12s:\n----------------------------------------" % ['U', 'key', 'origin', 'section name']
         oForjAccount.metadata_each { | section, mykey, hValue |
            key_exist = oForjAccount.exist?(mykey)

            sUpdMsg = '+'
            sUpdMsg = ' ' if rhGet(hValue, :readonly)

            if key_exist
               highlight = ''
               highlight = ANSI.bold if key_exist == account_name
               highlight = ANSI.bold + ANSI.yellow if key_exist == 'local'
               default_key = nil
               default_key = " (from default key '%s')" % rhGet(hValue, :default) if rhExist?(hValue, :default) == 1 and key_exist != account_name
               puts "%s %-15s(%s%-7s%s) %-12s: '%s'%s" % [sUpdMsg, mykey, highlight, key_exist, ANSI.clear, section, oForjAccount.get(mykey), default_key]
            else
               puts "%s %-15s(       ) %-12s: unset" % [sUpdMsg, mykey, section]
            end
            }
         puts "\nOn values identified by '+' you can:"
         puts "Use `forj set <key>=<value> -a %s` to update account data." % account_name
         puts "Or  `forj set <key>= -a %s`        to restore key default value." % account_name
      end
      
      def Settings.config_get_all(oConfig)
         puts "legend: default = Application defaults, local = Local default config\n\n"
         puts "%s %-15s(%-7s) %-12s:\n----------------------------------------" % ['U', '''key', 'origin', 'section name']
         
         oConfig.meta_each { |section, found_key, hValue|
            sUpdMsg = '+'
            sUpdMsg = ' ' if rhGet(hValue, :readonly)
            found_key = rhGet(hValue, :default) if rhExist?(hValue, :default) == 1
            
            where = oConfig.exist?(found_key)
            if where
               highlight = ''
               highlight = ANSI.bold + ANSI.yellow if where == 'local'
               puts "%s %-15s(%s%-7s%s) %-12s: '%s'" % [sUpdMsg, found_key, highlight, where, ANSI.clear, section, oConfig.get(found_key) ]
            else
               puts "%s %-15s(       ) %-12s: unset" % [sUpdMsg, found_key, section]
            end
            }
         puts "\nUse 'forj set <key>=<value>' to update defaults on values identified with '+'"

      end
      
      def Settings.account_get(oConfig, account_name, key)

         oConfig.set(:account_name, account_name)
         oForjAccount = ForjAccount.new(oConfig)

         Logging.fatal(1, "Unable to load account '%s'. Not found." % account_name) if not oForjAccount.ac_load

         if oForjAccount.exist?(key)
            puts "%s: '%s'" % [oForjAccount.exist?(key), oForjAccount.get(key)]
         elsif oForjAccount.exist?(key.parameterize.underscore.to_sym)
            key_symb = key.parameterize.underscore.to_sym
            puts "%s: '%s'" % [oForjAccount.exist?(key_symb), oForjAccount.get(key_symb)]
         else
            Logging.message("key '%s' not found"% [key])
         end
      end
      
      def Settings.config_get(oConfig, key)
         if oConfig.exist?(key)
            puts "%s:'%s'" % [oConfig.exist?(key), oConfig.get(key)]
         else
            Logging.message("key '%s' not found" % [key])
         end
      end
   end
end
