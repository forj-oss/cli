#!/usr/bin/env ruby

require 'byebug'

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

oCloud = ForjCloud.new(oConfig, 'test')
#oCloud = ForjCloud.new(oConfig)

oConfig.set(:blueprint, 'redstone')
#oConfig.set(:sg_desc, "Security group for blueprint '%s'" % [oConfig.get(:blueprint)])
#puts 'Compute:'
#oCloud.Create(:compute_connection)
#oCloud.Create(:router)
#oCloud.Create(:keypairs)


oCloud.Setup(:internet_server)
oCloud.config.ac_save
byebug
oCloud.Create(:internet_server)

oConfig.set(:server_name, 'test')
byebug
oCloud.Create(:server)

oConfig.set(:instance_name, 'test')

oForj = ForjObject(oConfig, sProcessClass = :ForjProcess)
oCloud.Create(:maestro_server)

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


#~ class A
    #~ def initialize(par1)
        #~ @par1 = par1
    #~ end
    #~ def func1()
        #~ puts "Call func1"
    #~ end
    #~ def func2()
        #~ puts "Call func2"
    #~ end
    #~
    #~ private
    #~ def provides(aArray)
        #~ @aArray = aArray
    #~ end
#~ end
#~
#~ class B < A
    #~ def initialize(par1, par2)
        #~ super(par1)
        #~ @par2 = par2
        #~ provides([:test3])
    #~ end
    #~ def func2()
        #~ byebug
        #~ puts "Call func3"
    #~ end
    #~
#~ end
#~
#~ myclass = Object.const_get('B')
#~
#~ byebug
#~ test = myclass.new(:test, :test2)
