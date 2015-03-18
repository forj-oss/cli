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
