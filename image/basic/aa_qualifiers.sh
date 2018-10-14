#!/bin/bash

echo ".vbox_version"
/usr/bin/head -n1 /home/vagrant/.vbox_version

echo "authorized keys"
/usr/bin/head -n1 /home/vagrant/.ssh/authorized_keys

# uncomment when it's time
#/usr/bin/head /home/vagrant/testfile
