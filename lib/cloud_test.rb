#!/usr/bin/env ruby

# require 'byebug'

APP_PATH = File.dirname(__FILE__)
LIB_PATH = File.expand_path(File.join(File.dirname(APP_PATH), 'lib'))

LOAD_PATH << LIB_PATH

LOAD_PATH << File.join(LIB_PATH, 'lib-forj', 'lib')

require 'appinit.rb'

# Initialize forj paths
AppInit.forj_initialize

# Initialize global Log object
FORJ_LOGGER = ForjLog.new

require 'lib-forj.rb'

Logging.set_level(Logger::DEBUG)

# Load global Config
o_config = ForjConfig.new

a_processes = []

# Defines how to manage Maestro and forges
# create a maestro box. Identify a forge instance, delete it,...
a_processes << File.join(LIB_PATH, 'forj', 'ForjCore.rb')

# Defines how cli will control FORJ features
# boot/down/ssh/...
a_processes << File.join(LIB_PATH, 'forj', 'ForjCli.rb')

# PrcLib.core_level = 3 # verbose

infra_dir = File.expand_path(o_config.get(:infra_repo))

# Ask information if needed.
unless Dir.exist?(File.expand_path(infra_dir))
  Logging.warning(<<-END
Your infra workspace directory is missing.

Forj uses an infra workspace directory to store any kind of data that are
 private to you.
We provides ways to send those data securily to your new Forge instance,
 as metadata.
In production case, we suggest you to keep it safe in your SCM preferred
 database.

If you already have an existing infra workspace,
 use 'forj set infra_repo=<PathToYourRepo>' to set it and restart.

Otherwise, we will build a new one with some predefined data,
 you can review and update later.
   END
  )
  s_ask = format(
    'Do you want to create a new one from Maestro (yes/no)?',
    infra_dir
  )
  b_build_infra = agree(s_ask)
  unless b_build_infra
    puts 'Process aborted on your demand.'
    exit 0
  end
end

o_cloud = ForjCloud.new(o_config, 'hpcloud', a_processes)

# o_config.set(:instance_name, "test")
# o_cloud.Create(:metadata)
# o_cloud.Create(:infra_repository)
# o_cloud.Create(:userdata)

# o_cloud.Setup(:server, 'hpcloud')
# o_cloud.Setup(:forge, 'hpcloud')

# o_cloud.Create(:forge)

# o_config.set(:instance_name, 'servertestluis')
# o_cloud.Create(:forge)

o_forge = o_cloud.Get(:forge, 'luistest')

# Ask the user to get server(s) to destroy
server_id_length = 0
server_name_length = 0

o_forge[:server].each do |server|
  if server[:id].length >  server_id_length
    server_id_length = server[:id].length
  end

  if server[:name].length >  server_name_length
    server_name_length = server[:name].length
  end
end

server_index = 1
# Display headers
puts format(
  '|%s |%s |%s |',
  'Index '.ljust(6),
  'Name'.ljust(server_name_length),
  'ID'.ljust(server_id_length)
     )
# Display Forge servers detail
o_forge[:server].each do |server|
  puts format(
    '|%s |%s |%s |',
    server_index.to_s.ljust(6),
    server[:name].to_s.ljust(server_name_length),
    server[:id].to_s.ljust(server_id_length)
       )
  server_index += 1
end

o_high_line = HighLine.new

index = o_high_line.ask(
  'Select the index of the server to create the ssh connection',
  Integer
) do |q|
  q.below = o_forge[:server].count + 1
  q.above = 0
end

o_config.set(:instance_name, 'luistest')
o_config.set(:forge_server, o_forge[:server][index - 1][:id])
o_config.set(:server_name, o_forge[:server][index - 1][:name])
# o_config.set(:box, 'maestro')
# o_config.set(:instance_name, 'luistest')
# o_config.Create(:server)
o_cloud.Create(:ssh)

# o_cloud.Query(:server, 'maestro')
