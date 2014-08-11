Forj cli
=====================


Installation
=====================
For ruby 2.0

Fedora/CentOS/Redhat/rpm like system

    sudo yum install ruby-dev build-essential libopenssl-ruby libssl-dev zlib1g-dev -y
    sudo gem install forj

Ubuntu/Debian/debian like system (not tested)

    sudo apt-get install ruby-dev build-essential libopenssl-ruby1.9.1 libssl-dev zlib1g-dev -y
    sudo gem install forj

For ruby 1.9

    sudo apt-get install ruby-dev build-essential libopenssl-ruby1.9.1 libssl-dev zlib1g-dev -y
    sudo gem install forj

For ruby 1.8

    sudo apt-get install ruby1.8-dev ruby1.8 ri1.8 rdoc1.8 irb1.8 -y
    sudo apt-get install libreadline-ruby1.8 libruby1.8 libopenssl-ruby -y
    sudo apt-get install libxslt-dev libxml2-dev -y
    sudo gem install nokogiri
    sudo apt-get install ruby-bundler -y
    sudo gem install mime-types -v 1.25.1
    sudo gem install hpcloud
    sudo gem install forj


How to use forj cli
=====================
Setup forj

    forj setup # follow the instructions

Boot a forge

    forj boot <blueprint> on <cloud_provider> as <name>
    e.g. forj boot redstone on hpcloud as maestro_01

Optional arguments

    -u --build #Replace the default build.sh.
    -d --build_config_dir # Defines the build configuration directory to load the build configuration file.
    -c --build_config # The build config file to load <confdir>/<BoxName>.<Config>.env.
    -b --branch # The build will extract from git branch name.
    -t --test_box # Create test-box meta from the repository path provided.
    -r --git_repo # The box built will use a different git repository sent out to <user_data>.
    -h --boothook # By default, boothook file used is build/bin/build-tools/boothook.sh.
    -x --box_name # Defines the name of the box or box image to build.
    -k --key_name # Key pair name to import.
    -p --key_path # Public key pair data.
    -y --catalog # A path for the yaml file data about the blueprint

Catalog.yaml example

    redstone:
      image: proto2b
      flavor: standard.xsmall
      ports: [22, 80, 443, 3131, 3000, 3132, 3133, 3134, 3135, 4505, 4506, 5000, 5666, 8000, 8080, 8081, 8083, 8125, 8139, 8140, 8773, 8774, 8776, 9292, 29418, 35357]
      keypair_path: ~/.hpcloud/keypairs/nova
      keypair_name: nova
      router: private-ext
      security_group: default
      network: private
      # at this point you have to clone the infra project manually
      build_config_dir: ~/forj/infra/build/boxes/maestro
      build_config: box-13.5
      branch: master
      box_name: maestro
      infra: ~/.forj/infra
    default:
      maestro: https://github.com/forj-oss/maestro.git
To ssh into a server

    forj ssh <name> <node>
    e.g. forj ssh maestro_01 [maestro, ci, util, review] # the nodes from your blueprint


Contributing to Forj
=====================
We welcome all types of contributions.  Checkout our website (http://docs.forj.io/en/latest/dev/contribute.html)
to start hacking on Forj.  Also join us in our community (https://www.forj.io/community/) to help grow and foster Forj for
your development today!

License
=====================
Forj Cli is licensed under the Apache License, Version 2.0.  See LICENSE for full license text.
