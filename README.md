Forj cli
========


Installation
------------

Forj cli supports Ruby 1.9.3 or higher.

###Fedora/CentOS/Redhat rpm like package system

**For ruby 2.0**

    $ sudo yum install ruby-devel libxml2-devel libxslt-devel python-yaml gcc git -y
    $ sudo gem install forj

###Ubuntu/Debian deb like package system

**For ruby 1.9**

    $ apt-get -y update
    $ sudo apt-get install ruby1.9.3 ruby1.9.3-dev rubygems1.9.3 build-essential libopenssl-ruby1.9.3 libssl-dev zlib1g-dev libxml2-dev libxslt-dev git -y
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

        - [hp public cloud](http://www.hpcloud.com/) from HP. Tested successfully.
        - [hphelion](http://www8.hp.com/us/en/cloud/helion-overview.html) from HP. Not tested with access keys.

    - *openstack*: Use this provider to access any openstack installation (public or private) or Hphelion (public or private)
        Uses login and password authentication system

        If you want to test against a new local openstack cloud, you can consider :

        - [packstack](https://wiki.openstack.org/wiki/Packstack) from RedHat. Can be used for a notebook local installation. tested successfully.
        - [hphelion](http://www8.hp.com/us/en/cloud/helion-overview.html) from HP. Tested successfully with user/password.
        - [Ubuntu OpenStack](http://www.ubuntu.com/cloud) from Canonical. Not tested.

    For any other cloud, you need a provider in lorj library. Contribute to create a new provider!
    See

2.  Create your forge on your default account

    `$ forj boot <blueprint> <InstanceName>`

    Ex: `forj boot redstone myforge` - This command will start a Redstone forge named 'myforge' with the default FORJ account. Previous, we set it to be MyAccount.

NOTE: If you are creating a Forge in a corporate network, a proxy may be required. See section [Commmon issues]

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

When you create a new forj (`forj boot`), forj cli will load data from several layers of configuration:

1. Cloud account setting (`forj setup [account]` or `forj get -a <account>` list identified by 'account' origin)
2. Local configuration (`forj get` list identified by 'local' origin)
3. Application defaults and cloud model. (`forj get` list identified by 'forj_core' or 'default')

You can get a complete list of current values:

    $ forj get
or

    $ forj get -a <account>

If you need to change one of them:

    $ forj set "security_group=test"
or

    $ forj set "security_group=mysec" -a <account>

#### Connect to servers

To ssh into a server

    $ forj ssh <name> [node]
e.g.

    $ forj ssh myforge review # review is one node from redstone blueprint

Commmon issues
==============

Certificate Authorities
-----------------------

If your company certify your server with a private certificate authorities service, you may need to do the following:

Either your workstation and your cloud may needs to be configured with this CA certificate.

* From your workstation:

    You can instantly provide the CA certificate to forj cli, with SSL_CERT_FILE env variable<BR>
    ex:

        SSL_CERT_FILE=~/tmp/cacert.crt forj boot redstone [...]

    OR<BR>

    You can install this certificate in your workstation. This case depends on your OS.<BR>
    typical case:

    * debian like system:
        - cp file to /usr/share/ca-certificates/
        - Update /etc/ca-certificates.conf
        - call update-ca-certificates
    * rpm like system:
        - cp file to /etc/pki/ca-trust/source/anchors/
        - call update-ca-trust extract

* In your cloud:

    If your cloud is NOT preconfigured (images) with your Company CA certificate,
    you can call forj cli with --ca-root-cert at boot time, to configure your boxes with this missing certificate.

    ex:

        forj boot redstone myforge --ca-root-cert ~/tmp/cacert.crt

    You can ask server in your cloud to install it in specific path and file name

        forj boot redstone myforge --ca-root-cert '~/tmp/cacert-2015-1.crt#mycompany/cacrt.crt'

    You can also pre-configure your forj account with this certificate.

        forj set ca-root-cert=~/tmp/cacert-2015-1.crt -a myaccount
    or

        forj set 'ca-root-cert=~/tmp/cacert-2015-1.crt#mycompany/cacrt.crt' -a myaccount

HTTP/HTTPS proxy
----------------

If your cloud is NOT preconfigured (images) with your Company proxy setting,
you can ask forj cli to configure your server with the Proxy setting needed.


Ex: boot a redstone 'myforge' with a proxy setting.

    $ forj boot redstone myforge -a CorporateAccount -e webproxy=$http_proxy


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
