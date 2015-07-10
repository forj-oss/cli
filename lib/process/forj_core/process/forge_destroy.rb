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

# Functions for :forge destroy
class ForjCoreProcess
  def delete_forge(_sCloudObj, hParams)
    PrcLib.state('Destroying server(s) of your forge')

    forge_serverid = hParams[:forge_server]

    o_forge = hParams[:forge]

    o_forge[:servers].each do|_type, server|
      next if forge_serverid && forge_serverid != server[:id]
      register(server)
      PrcLib.state("Destroying server '%s - %s'", server[:name], server[:id])
      process_delete(:server)
    end
    if forge_serverid.nil?
      PrcLib.high_level_msg("The forge '%s' has been destroyed. (all servers" \
                            " linked to the forge)\n", o_forge[:name])
    else
      PrcLib.high_level_msg("Server(s) selected in the forge '%s' has been"\
                            " removed.\n", o_forge[:name])
    end
  end
end
