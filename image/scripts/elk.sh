#!/bin/bash

apt install -y openjdk-8-jre apt-transport-https wget nginx

if [[ $? -ne 0 ]]; then
    echo "failed to install packages"
    exit 100
fi

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/6.x/apt stable main" > /etc/apt/sources.list.d/elastic.list

apt update
apt install -y elasticsearch kibana

if [[ $? -ne 0 ]]; then
    echo "failed to install kibana"
    exit 100
fi

service auditd stop
systemctl disable auditd
curl -L -O https://artifacts.elastic.co/downloads/beats/auditbeat/auditbeat-6.4.2-amd64.deb
dpkg -i auditbeat-6.4.2-amd64.deb

if [[ $? -ne 0 ]]; then
    echo "failed to install auditbeat"
    exit 100
fi

echo "server.host: \"0.0.0.0\"" >> /etc/kibana/kibana.yml

systemctl enable auditbeat
systemctl enable elasticsearch
systemctl enable kibana

rm /etc/auditbeat/audit.rules.d/sample-rules-linux-32bit.conf

service kibana restart
service auditbeat start
