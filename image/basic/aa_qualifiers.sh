#!/bin/bash

echo "screenrc"
/usr/bin/head -n1 /home/vagrant/.screenrc

echo "tmux config"
/usr/bin/head -n1 /home/vagrant/.tmux.conf

echo "authorized keys"
/usr/bin/head -n1 /home/vagrant/.ssh/authorized_keys

# uncomment when it's time
#/usr/bin/head /home/vagrant/testfile
