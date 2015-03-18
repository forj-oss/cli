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

    $ apt-get -y update
    $ sudo apt-get install ruby1.9.1 ruby1.9.1-dev rubygems1.9.1 build-essential libopenssl-ruby1.9.1 libssl-dev zlib1g-dev libxml2-dev libxslt-dev git -y
    $ sudo gem install forj


**For ruby 1.8**

    $ sudo apt-get install ruby1.8-dev ruby1.8 ri1.8 rdoc1.8 irb1.8 rubygems -y
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

**For all OS including Linux/windows/mac
2 vagrant images has been written.
Read [vagrant/README.md] for details.

This solution helps to develop and test on forj and lorj

For more information about lorj, a process/controller library, see https://github.com/forj-oss/lorj

Quick steps: How to create a forj?
----------------------------------

    forj setup # follow the instructions

1.  Setup your first forj account.

    `$ forj setup [AccountName [provider]]`

    Ex: `forj setup MyAccount`. In this example, your account will be named 'MyAccount'.
         The first time you setup your account, it will become the default one.

    Supported provider: **hpcloud**, **openstack**. hpcloud is the default.

    If you uses hphelion as a provider, check the API authentication system to select hpcloud or openstack.

    - *hpcloud* : Use this provider for http://www.hpcloud.com/, or hphelion.
      Uses Access key and secret key authentication mechanism.

        - [hp public cloud|http://www.hpcloud.com/] from HP. Tested successfully.

    - *openstack*: Use this provider to access any openstack installation (public or private) or Hphelion (public or private)
        Uses login and password authentication system

        If you want to test against a new local openstack cloud, you can consider :

        - [packstack|https://wiki.openstack.org/wiki/Packstack] from RedHat. Can be used for a notebook local installation. tested successfully.
        - [hphelion|http://www8.hp.com/fr/fr/cloud/helion-overview.html] from HP. Tested successfully
        - [Ubuntu OpenStack|http://www.ubuntu.com/cloud] from Canonical. Not tested.

    For any other cloud, you need a provider in lorj library. Contribute to create a new provider!
    See

2.  Create your forge on your default account

    `$ forj boot <blueprint> <InstanceName>`

    Ex: `forj boot redstone myforge` - This command will start a Redstone forge named 'myforge' with the default FORJ account. Previous, we set it to be MyAccount.

NOTE: If you are creating a Forge in a corporate network, a proxy may be required for Maestro to access internet.
You can ask `forj` cli to send the proxy to use with -e

Ex: Thanks to a CorporateAccount setup with forj setup, the following will use it and set the webproxy metadata.

    `forj boot redstone myforge -a CorporateAccount -e webproxy=$http_proxy`

###Forj options:

To get forj cli help, just type:

    $ forj

To get help on specific action, just type:

    $ forj help boot

 Examples of possible actions:

Commands:
  forj boot <Blueprint> <InstanceName> [options] # boot a Maestro box and instruct it to provision the blueprint
  forj down                                      # delete the Maestro box and all systems installed by the blueprint
  forj help [action]                             # Describe available FORJ actions or one specific action
  forj setup                                     # set the credentials for forj cli
  forj show defaults                             # Show list of predefined value you can update in your ~/.forj/config.yaml
  forj ssh


#### Configuration

While building your forge, forj needs to load some data by default. Those are listed in the application.

You can show them with :

    $ forj show defaults

If you need to change one of them:

    $ forj set "keypair_name=MyKeypairName"

ex:
    forj set keypair_name=nova

You can check what kind of value, forj will use to boot/access your forge:

    $ forj get -a dev


#### Your config.yaml

The following list gives you some details about keys/values required to boot/access your forge.


~/.forj/config.yaml:

     default:
       account_name: name       # Default forj account used to connect to your cloud. This setting is automatically set to the first account created with forj setup <CloudProvider>
       maestro_url: url         # Maestro GIT repository for clone.
       infra_repo: path         # Path to the default Infra repository used to store your specific bootstrap/build environment. By default: ~/.forj/infra
       image: imageName         # Image used to create Maestro and all forge boxes. By default, it is 'Ubuntu Precise 12.04.4 LTS Server 64-bit 20140414 (Rescue Image)'
                                # If you have created the generic proto2b image, you can set it here.
       flavor: flavorName       # Maestro Flavor name. This flavor is for Maestro only. Your blueprint layout defines each node flavors on needs.
                                # By default: standard.medium
       bp_flavor: flavorName    # Blueprint nodes default flavor. Usually, blueprint node are smaller than Maestro.
                                # By default: standard.small
       ports: [Port1,Port2,...] # list of additional ports to add in your cloud security group.
                                # This list is added to the default one in defaults.yaml
       keypair_path: path       # Define the file path to your OpenSSH private key. Useful to access your box with ssh command line.
                                # By default. ~/.ssh/forj-id_rsa
       keypair_name: name       # keypair name defined in your cloud to access your server. By default we named it 'forj'. If it doesn't exist, it will be created.
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
