#!/bin/bash

cd /vagrant/vulnerable-web-app
source ./virtualenv/bin/activate || echo "Virtualenv not setup" && echo "To run app, execute ' while true; do gunicorn -c gunicorn.conf.py wsgi ; sleep 5;  done '"
$SHELL
