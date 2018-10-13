#!/bin/bash

pushd /vagrant/vulnerable-web-app
virtualenv -p python3 --system-site-packages virtualenv
source ./virtualenv/bin/activate
pip install -r requirements.txt
popd

exit 0

