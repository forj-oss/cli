You can test forj cli (and lorj as well) from any OS, like linux/windows or mac thanks to vagrant.

There is 2 differents implementations of forj cli working on fedora or ubuntu.

Choose the one you want.

To test forj cli, do the following:

1. install [virtualbox | https://www.virtualbox.org/wiki/Downloads] or vmware workstation

2. install [vagrant|https://www.vagrantup.com/]

3. clone the forj repository.

    $ `git clone https://review.forj.io/forj-oss/forj`

4. run vagrant up

    $ `cd forj/vagrant/fedora`

    $ `vagrant up`

If you want to test both forj and lorj from source, use this different way:
For more information about lorj, a process/controller library, see https://github.com/forj-oss/lorj

3. clone the forj and lorj repository.

    $ `git clone https://review.forj.io/forj-oss/forj`
    $ `git clone https://review.forj.io/forj-oss/lorj`

4. run vagrant up

    $ `cd forj/vagrant/fedora`
    $ `lorj_src=../lorj vagrant up`

Now you are in, under fedora in this example, and forj cli installed from source.
You are in a linux environment, where you can do anything you need.


Example use cases:

- you want to install the latest forj cli package

    sudo gem uninstall forj
    sudo gem install forj

- You want to test an update in forj

    1. update your code under your host, on in vagrant, /srv/forj/...
    2. update the installation with sources. This will execute rubocop and rspec, before any install.
    sudo /srv/forj/vagrant/configure/install.sh

# fog openstack V3 auth

To use the latest openstack authentication v3 (including domain), you need to get fog 1.30 or get it from source. hphelion 1.1 uses openstack authentication V3.

Currently, gem fog 1.30 doesn't exist. So, this section will explain what needs to be done to get the latest patch from github

We assume vagrant is installed and working perfectly.

1. clone fog, cli and lorj patches from source.

    $ mkdir -p ~/tmp/src
    $ cd ~/tmp/src
    $ git clone https://github.com/clarsonneur/fog.git
    $ cd fog
    $ sed -i 's/1.29/1.30/g' fog.gemspec
    $ cd -
    $ git clone https://github.com/forj-oss/lorj.git
    $ cd lorj
    $ git fetch https://review.forj.io/forj-oss/lorj refs/changes/55/2555/4 && git cherry-pick FETCH_HEAD
    $ cd -
    $ git clone https://github.com/forj-oss/cli.git
    $ cd cli
    $ git fetch https://review.forj.io/forj-oss/cli refs/changes/47/2547/6 && git cherry-pick FETCH_HEAD
    $ cd -

2. set some tasks to execute before install forj cli

    $ src="~/tmp/src/fog:bundler install ;gem build fog.gemspec ;gem install fog-1.30.0.gem"
    $ src="$src;|~/src/cdk/forj/lorj/:bundler install ;rake install"
    $ export src
    $ cd ~/tmp/src/cli/vagrant/fedora # You can try ubuntu as well in ../ubuntu
    $ vagrant up  # The box is going to be created and provisionned.
    $ vagrant ssh # You are in!

3. if needed, you can set the SSL_CERT_FILE, or SSL_CERT_PATH if you having trouble with https certificates.
  We assume you are still in your vagrant box.
    $ export

4. Do any forj task, like forj setup, boot or destroy...
