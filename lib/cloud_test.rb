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

$LIB_FORJ_DEBUG = 1 # Very verbose

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

oCloud.Create(:infra_repository)

# For debugging security_groups
#byebug

#~ server_name = "chl1"
#~ oConfig.set(:server_name, server_name)
#~
#~ server = oCloud.Query(:server, {:name => server_name})
#~
#~ oCloud.Create(:server) if not server

#oConfig.set(:blueprint, 'redstone')
#oConfig.set(:instance_name, instance_name)
#oCloud.Create(:forge)
#~ oConfig.set(:blueprint, 'redstone')

#~ oConfig.set(:instance_name, "test")
#~
#~ oCloud.Create(:forge)

#oConfig.set(:sg_desc, "Security group for blueprint '%s'" % [oConfig.get(:blueprint)])
#puts 'Compute:'
#oCloud.Create(:compute_connection)
#oCloud.Create(:router)

#~ oCloud.Setup(:internet_server)
#~ oCloud.config.ac_save
#~ byebug
#~ oCloud.Create(:internet_server)
#~
#~ oConfig.set(:server_name, 'test')
#~ byebug
#~ oCloud.Create(:server)
#~
#~ oConfig.set(:instance_name, 'test')
#~
#~ oForj = ForjObject(oConfig, sProcessClass = :ForjProcess)
#~ oCloud.Create(:maestro_server)

#hp_test.Create(:internet_network)
#puts 'ensure having an internet network'
#hp_test.Create(:internet_network)

#~ ForjProcess.boot(AccountInfo, InstanceName)
#~
#~ # Load Openstack Data
#~ oConfig = ForjConfig.new()
#~ oConfig.set(:account_name, 'openstack')
#~ oHPAccount = ForjAccount.new(oConfig)
#~ os_test = ForjCloud.new(Openstack.new(), oOSAccount)
#~
#~ os_test.ComputeConnect()
#~
#~
#~
#~
#~ # Load Mock Data
#~ oConfig = ForjConfig.new()
#~ oConfig.set(:account_name, 'mock')
#~ oMockAccount = ForjAccount.new(oConfig)
#~ mock_test = ForjCloud.new(Openstack.new(), oMockAccount)
#~
#~ mock_test.ComputeConnect()

# Load HPCloud Data
