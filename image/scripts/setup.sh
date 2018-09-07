#!/bin/bash -eux

# Guest additions setup
# Mount the disk image
cd /tmp
mkdir /tmp/isomount
mount -t iso9660 -o loop /home/vagrant/VBoxGuestAdditions.iso /tmp/isomount

# Install the drivers
/tmp/isomount/VBoxLinuxAdditions.run

# Cleanup
umount isomount
rm -rf isomount /home/vagrant/VBoxGuestAdditions.iso

# Add vagrant user to sudoers.
echo "vagrant        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers

# Disable daily apt unattended updates.
echo 'APT::Periodic::Enable "0";' >> /etc/apt/apt.conf.d/10periodic

# Get workshop dependencies
apt update
apt install apparmor apparmor-profiles auditd apparmor-utils apparmor-easyprof libapparmor1 libapparmor-dev wget git vim python3 python-apparmor build-essential -y
pip install virtualenv

wget "https://www.imagemagick.org/download/releases/ImageMagick-6.8.9-10.tar.xz" && tar xf ImageMagick-6.8.9-10.tar.xz && pushd ImageMagick-6.8.9-10/ && ./configure --with-rsvg=yes && make && make install && popd && rm -rf ImageMagick-6.8.9-10/

# Add SSH key
mkdir -p /home/vagrant/.ssh
wget https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub -O /home/vagrant/.ssh/authorized_keys
chmod go-w /home/vagrant/
chmod 700 /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh

# More cleanup
apt autoremove
dd if=/dev/zero of=/EMPTY bs=1M
rm -f /EMPTY

sync

