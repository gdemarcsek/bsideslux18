#!/bin/bash

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
apt install apparmor \
            apparmor-profiles \
            auditd apparmor-utils \
            apparmor-easyprof \
            libapparmor1 \
            libapparmor-dev \
            wget curl \
            git \
            vim \
            python3 \
            python-apparmor \
            build-essential \
            python-pip \
            python3-distutils screen tmux \
            librsvg2-2 librsvg2-dev librsvg2-bin \
            libpng16-16 libpng-dev libpng-tools \
            libjpeg-dev \
            ghostscript gsfonts \
            tree ntp peco elf-dev -y

pip install virtualenv

IMAGETRAGICK_VERSION="6.8.6-10"
IMAGETRAGICK_URL="https://www.imagemagick.org/download/releases/ImageMagick-${IMAGETRAGICK_VERSION}.tar.xz"

wget "$IMAGETRAGICK_URL" && \
    tar xf ImageMagick-${IMAGETRAGICK_VERSION}.tar.xz && \
    pushd ImageMagick-${IMAGETRAGICK_VERSION}/ && \
    ./configure --with-jpeg=yes --with-png=yes --with-rsvg=yes && \
    make && make install && popd && rm -rf ImageMagick-${IMAGETRAGICK_VERSION}/

# Add SSH key
mkdir -p /home/vagrant/.ssh
wget https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub -O /home/vagrant/.ssh/authorized_keys
chmod go-w /home/vagrant/
chmod 700 /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh

# Do not pass LC and LANG env vars
sed -i 's/[^#]*\(AcceptEnv LANG LC_\*\)/#\1/g' /etc/ssh/sshd_config

# Clone imagemagick pocs
cd /home/vagrant
git clone "https://github.com/ImageTragick/PoCs.git" .imagetragick
chown -R vagrant:vagrant .imagetragick

# Generate SSH key
sudo -u vagrant ssh-keygen -t rsa -b 4096 -P lollollol -f /home/vagrant/.ssh/id_rsa

# More cleanup
apt autoremove
dd if=/dev/zero of=/EMPTY bs=1M
rm -f /EMPTY

sync

