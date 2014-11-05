#!/usr/bin/env ruby

#require 'byebug'

$APP_PATH = File.dirname(__FILE__)
$LIB_PATH = File.expand_path(File.join(File.dirname($APP_PATH),'lib'))

$LOAD_PATH << $LIB_PATH

$LOAD_PATH << File.join($LIB_PATH, 'lib-forj', 'lib')

require 'appinit.rb'

# Initialize forj paths
AppInit::forj_initialize()

# Initialize global Log object
$FORJ_LOGGER=ForjLog.new()

require 'lib-forj.rb'

Logging.set_level(Logger::DEBUG)

# Load global Config
oConfig = ForjConfig.new()

aProcesses = []

# Defines how to manage Maestro and forges
# create a maestro box. Identify a forge instance, delete it,...
aProcesses << File.join($LIB_PATH, 'forj', 'ForjCore.rb')

# Defines how cli will control FORJ features
# boot/down/ssh/...
aProcesses << File.join($LIB_PATH, 'forj', 'ForjCli.rb')

$LIB_FORJ_DEBUG = 3 # verbose

infra_dir = File.expand_path(oConfig.get(:infra_repo))

# Ask information if needed.
if not Dir.exist?(File.expand_path(infra_dir))
   Logging.warning(<<-END
Your infra workspace directory is missing.

Forj uses an infra workspace directory to store any kind of data that are private to you.
We provides ways to send those data securily to your new Forge instance, as metadata.
In production case, we suggest you to keep it safe in your SCM preferred database.

If you already have an existing infra workspace, use 'forj set infra_repo=<PathToYourRepo>' to set it and restart.

Otherwise, we will build a new one with some predefined data, you can review and update later.
   END
   )
   sAsk = "Do you want to create a new one from Maestro (yes/no)?" % [infra_dir]
   bBuildInfra=agree(sAsk)
   if not bBuildInfra
      puts 'Process aborted on your demand.'
      exit 0
   end
end

oCloud = ForjCloud.new(oConfig, 'hpcloud', aProcesses)

#oConfig.set(:instance_name, "test")
#oCloud.Create(:metadata)
#oCloud.Create(:infra_repository)
#oCloud.Create(:userdata)


#oCloud.Setup(:server, 'hpcloud')
#oCloud.Setup(:forge, 'hpcloud')

#oCloud.Create(:forge)

#oConfig.set(:instance_name, 'servertestluis')
#oCloud.Create(:forge)

oForge = oCloud.Get(:forge, "luistest")

#Ask the user to get server(s) to destroy
server_id_length = 0
server_name_length = 0

oForge[:server].each{ |server|
  if server[:id].length() >  server_id_length
    server_id_length = server[:id].length()
  end

  if server[:name].length() >  server_name_length
    server_name_length = server[:name].length()
  end
}

server_index = 1
#Display headers
puts "|%s |%s |%s |" % ["Index ".ljust(6), "Name".ljust(server_name_length), "ID".ljust(server_id_length) ]
#puts "|%s |%s |%s |" % ["0", "all".ljust(server_name_length), " ".ljust(server_id_length) ]
#Display Forge servers detail
oForge[:server].each{ |server|
  puts "|%s |%s |%s |" % [server_index.to_s().ljust(6), server[:name].to_s().ljust(server_name_length), server[:id].to_s().ljust(server_id_length) ]
  server_index = server_index + 1
}

oHighLine = HighLine.new()

index = oHighLine.ask("Select the index of the server to create the ssh connection", Integer)do |q|
  q.below=oForge[:server].count + 1
  q.above=0
end


oConfig.set(:instance_name, 'luistest')
oConfig.set(:forge_server, oForge[:server][index - 1][:id])
oConfig.set(:server_name, oForge[:server][index - 1][:name])
#oConfig.set(:box, 'maestro')
#oConfig.set(:instance_name, 'luistest')
#oConfig.Create(:server)
oCloud.Create(:ssh)

#oCloud.Query(:server, 'maestro')