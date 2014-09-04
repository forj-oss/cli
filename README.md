Forj cli
========


Installation
------------

###Fedora/CentOS/Redhat rpm like package system

**For ruby 2.0**

    $ sudo yum install ruby-devel libxml2-devel libxslt-devel python-yaml gcc git -y
    $ sudo gem install forj

###Ubuntu/Debian deb like package system

**For ruby 1.9**

    $ sudo apt-get install ruby-dev build-essential libopenssl-ruby1.9.1 libssl-dev zlib1g-dev libxml2-dev libxslt-dev git -y
    $ sudo gem install forj


**For ruby 1.8**

    $ sudo apt-get install ruby1.8-dev ruby1.8 ri1.8 rdoc1.8 irb1.8 -y
    $ sudo apt-get install libreadline-ruby1.8 libruby1.8 libopenssl-ruby -y
    $ sudo apt-get install libxslt-dev libxml2-dev -y
    $ sudo gem install nokogiri
    $ sudo apt-get install ruby-bundler -y
    $ sudo gem install mime-types -v 1.25.1
    $ sudo gem install hpcloud
    $ sudo gem install forj

**Installation from source**
Perform one of the ruby installation steps without `gem install forj`.

    $ sudo apt-get -y install build-essential make libxslt-dev libxml2-dev
    $ sudo mkdir -p /opt/config/production/git
    $ cd /opt/config/production/git
    $ git clone https://review.forj.io/forj-oss/cli
    $ cd cli
    $ gem install bundler --no-rdoc --no-ri
    $ gem install rake --no-rdoc --no-ri
    $ bundle install --gemfile Gemfile
    $ rake install

Quick steps: How to create a forj?
----------------------------------

    forj setup # follow the instructions

1.  Setup your first forj account.

    `$ forj setup [Provider]`

    Ex: `forj setup hpcloud`. In this example, your account will be named 'hpcloud'.
    **WARNING!!!** [Provider] is currently not supported. By default, it is using hpcloud as default provider.

2.  Create your forge on your default account

    `$ forj boot <blueprint> on hpcloud as <InstanceName>`

    Ex: `forj boot redstone on hpcloud as MyForge`


###Forj options:

To get forj cli help, just type:

    $ forj

To get help on specific action, just type:

    $ forj help boot

 Examples of possible actions:

Commands:
  forj boot <Blueprint> on <Provider> as <InstanceName> [options]  # boot a Maestro box and instruct it to provision the blueprint
  forj down                                                        # delete the Maestro box and all systems installed by the blueprint
  forj help [action]                                               # Describe available FORJ actions or one specific action
  forj setup                                                       # set the credentials for forj cli
  forj show defaults                                               # Show list of predefined value you can update in your ~/.forj/config.yaml
  forj ssh 


#### config.yaml description

While building your forge, forj needs to load some data by default. Those are listed in forj-<version>/lib/defaults.yaml

If you need to change one of this default value, update a ~/.forj/config.yaml file, with any kind of data that need to be changed.

Here are the variables list you can set:

     default:
       account_name: name       # Default forj account used to connect to your cloud. This setting is automatically set to the first account created with forj setup <CloudProvider>
       maestro_url: url         # Maestro GIT repository for clone.
       infra_repo: path         # Path to the default Infra repository used to store your specific bootstrap/build environment. By default: ~/.forj/infra
       image: imageName         # NOT CURRENTLY USED. Still under development.
                                # Image used to create Maestro and all forge boxes. By default, it is 'Ubuntu Precise 12.04.4 LTS Server 64-bit 20140414 (Rescue Image)'
                                # If you have created the generic proto2b image, you can set it here.
       flavor: flavorName       # NOT CURRENTLY USED. Still under development.
                                # Maestro Flavor name. This flavor is for Maestro only. Your blueprint layout defines each node flavors on needs.
                                # By default: standard.xsmall
       ports: [Port1,Port2,...] # list of additional ports to add in your cloud security group.
                                # This list is added to the default one in defaults.yaml
       keypair_path: path       # Define the file path to your OpenSSH private key. Useful to access your box with ssh command line.
                                # By default. ~/.forj/keypairs/nova
       keypair_name: name       # keypair name defined in your cloud to access your server. By default we named it 'nova'. If it doesn't exist, it will be created.
       router: name             # Router name used by your forge boxes will use to access internet.
       security_group: name     # Security group name to configure and attach to each forge boxes.
       network: name            # Network name to attach to each forge boxes. By default we use 'private'. If it doesn't exist, it will be created.
       # Internal use.
       build_config: name       # forj cli use 'build.sh' to create Maestro. See build_config option on build.sh to get more information. By default 'box'
       branch: name             # forj cli use 'build.sh' to create Maestro. See gitbranch option on build.sh to get more information. By default 'master'
       box_name: maestro        # forj cli use 'build.sh' to create Maestro. See box_name option on build.sh to get more information. By default 'maestro'

To ssh into a server

    forj ssh <name> <node>
    e.g. forj ssh maestro_01 [maestro, ci, util, review] # the nodes from your blueprint


Contributing to Forj
=====================
We welcome all types of contributions.  Checkout our website (http://docs.forj.io/en/latest/dev/contribute.html)
to start hacking on Forj.  Also join us in our community (https://www.forj.io/community/) to help grow and foster Forj for
your development today!


Developping on FORJ:
===================

Development installation:
-------------------------

**WARNING!!!** forj cli is still under intensive development.

### For ruby 2.0

**Fedora/CentOS/Redhat rpm like package system**

    $ sudo yum install git gcc ruby-devel libxml2-devel rubygem-rspec libxslt-devel python-yaml rubygem-nokogiri -y
    $ gem install rspec-rake rspec-mocks rspec-expectations 

**Ubuntu/Debian deb like package system (not tested)**

    $ sudo apt-get install git ruby-dev build-essential libopenssl-ruby1.9.1 libssl-dev zlib1g-dev -y
    $ gem install rspec rspec-rake rspec-mocks rspec-expectations 

Then execute the following:

    $ gem install forj # To install all gem required for running it.
    $ mkdir -p ~/src/forj-oss
    $ cd ~/src/forj-oss
    $ git clone https://github.com/forj-oss/cli

To update `forj` from the repository:

    $ cd ~/src/forj-oss/cli
    $ git pull

To test `forj` cli, do the following:

    $ cd ~/src/forj-oss/cli
    $ bin/forj

To run unit-test, do the following:

    $ cd ~/src/forj-oss/cli
    $ rspec -c

License:
========
Forj Cli is licensed under the Apache License, Version 2.0.  See LICENSE for full license text.
