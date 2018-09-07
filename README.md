# Introduction

## Linux Security Modules

## Mandatory Access Control

## Confinement with AppArmor

# Lab setup

## Required software
 * VirtualBox
 * Vagrant

## Environment setup
Start the virtual machine
```
$ git clone --depth=1 --branch master https://github.com/gdemarcsek/bsideslux18.git
$ cd bsideslux18
$ vagrant up && vagrant ssh
$ ls -la /vagrant
```

## Python packages
```
$ # in ~/vulnerable-web-app
$ sudo pip install virtualenv
$ virtualenv -p python3 --system-site-packages virtualenv
$ source ./virtualenv/bin/activate
$ pip install -r requirements.txt
```

## Building ImageMagick
```
$ tar xf ImageMagick-6.7.9-10.tar.xz
$ cd ImageMagick-6.7.9-10
$ ./configure --with-rsvg=yes
$ make
$ sudo make install
```

# Lab tasks

## Checking the kernel module
```
$ cat /sys/module/apparmor/parameters/enabled
```

## Making sure AppArmor is started at boot
```
$ sudo systemctl enable apparmor
```

## Checking confinement status
```
$ sudo aa-status
```

## Checking security context of running processes
Execute the `ping` utility in a terminal window:

```
$ ping 1.1.1.1
```

Then in another one, inspect the output of:

```
$ ps auxZ
```

Stop pinging. ;)

## Loading and unloading profiles
Let's disable the profile for `/usr/bin/ping` by running:

```
$ sudo aa-disable /bin/ping
```

Now try the same as in the previous section and observe the difference in the output of `ps`.

Put ping's profile into enforce mode:

```
$ sudo aa-enforce /bin/ping
```

## Hello World of AppArmor
Let's create a simple C program that tries to get the home directory of the user - this is quite a common task, because many programs work with configuration files placed in the user's home:

```c
// aa_hello_world.c
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <pwd.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    uid_t current_uid = geteuid();
    struct passwd *ent = getpwuid(current_uid);
    if (ent == NULL) {
        perror("getpwuid");
        return EXIT_FAILURE;
    }

    printf("Home directory: %s\n", ent->pw_dir);

    return EXIT_SUCCESS;
}
```

[EXTRA-EXPLANATION]

Let's compile it:

```
$ gcc aa_hello_world.c -o aa_hello_world
```

Let's run it, we should see:

```
Home directory: /home/vagrant
```

## Using `aa-autodep`
Let's generate a base profile for our hello world application:

```
$ sudo aa-autodep aa_hello_world
```

[EXTRA-EXPLANATION]

Now let's check the generated profile!

```
$ sudo cat /etc/apparmor.d/vagrant.aa_hello_world 
# Last Modified: Mon Sep  3 21:31:29 2018
#include <tunables/global>

/vagrant/aa_hello_world flags=(complain) {
  #include <abstractions/base>

  /vagrant/aa_hello_world mr,
  /lib/x86_64-linux-gnu/ld-*.so mr,

}
```

Now let's put it into enforce mode:

```
$ sudo aa-enforce /vagrant/aa_hello_world
```

And try to execute it again:

```
$ ./aa_hello_world
getpwuid: Permission denied
```

[EXTRA-EXPLANATION]

Now let's see what is happening under the hood:


```
openat(AT_FDCWD, "/etc/passwd", O_RDONLY|O_CLOEXEC) = -1 EACCES (Permission denied)
openat(AT_FDCWD, "/etc/passwd", O_RDONLY|O_CLOEXEC) = -1 EACCES (Permission denied)
```

[EXTRA-EXPLANATION]

Let's try running it as root, after all, root is above all mortal souls in Linux:

```
$ sudo ./aa_hello_world
getpwuid: Permission denied
```

[EXTRA-EXPLANATION]

Now let's fix the AppArmor profile:

```
# Last Modified: Mon Sep  3 21:31:29 2018
#include <tunables/global>

/vagrant/aa_hello_world {
  #include <abstractions/base>

  /vagrant/aa_hello_world mr,
  /lib/x86_64-linux-gnu/ld-*.so mr,
  /etc/passwd r,
}
```

We need to reload the profile into the kernel:

```
$ sudo apparmor_parser -r /etc/apparmor.d/vagrant.aa_hello_world
$ echo $?
```

Then try running the program again: `./aa_hello_world`. 

## Fixing profiles on the fly
You can fix a profile while the confined process is running - you do not have to restart it. Try changing the previous program to print the home directory in an infinite loop with some sleep. Then break the profile and make sure it is in enforce mode. (You will need to terminals for this or a screen session).

```c
// aa_hello_world.c
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <pwd.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    while (1) {
        uid_t current_uid = geteuid();
        struct passwd *ent = getpwuid(current_uid);
        if (ent == NULL) {
            perror("getpwuid");
            continue;
        }

        printf("Home directory: %s\n", ent->pw_dir);
        sleep(10);
    }
    return EXIT_SUCCESS;
}
```

You will see permission denied errors but as soon as you fix the AppArmor profile back and run:

```
$ sudo apparmor_parser -r /etc/apparmor.d/vagrant.aa_hello_world
```

to reload the policy into the kernel, the process will start to work again without a restart. This can be quite useful with for example, large Java services like Jenkins or Confluence where the cost of a restart is significant. This also applies to switching between confinement modes, so you don't have to restart the service to start enforcing a policy. 

On the other hand, there is a catch: a profile must be loaded into the kernel before the process it tries to confine is started. We can try this in practice, let's stop our program and unload its profile from the kernel by running:

```
$ sudo aa-disable /vagrant/aa_hello_world
```

Let's screw up the profile again in the file so we know it should normally break the program, but still do not load it. Now start the program and try to load and enforce the profile again using `aa-enforce` - notice that the program did not break, we see no permission denied messages because it is actually not confined, despite the corresponding profile is loaded into the kernel.


## Inspecting AppArmor logs

Checking all AppArmor events:

```
journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode 2>/dev/null | grep AVC
```

Checking only access denied events:

```
journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode 2>/dev/null | grep AVC | grep 'apparmor="DENIED"'
```

[EXTRA-EXPLANATION]

Checking status events
```
journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode 2>/dev/null | grep AVC | grep 'apparmor="STATUS"'
```

[EXTRA-EXPLANATION]

You might think that having auditd running, you will be able to use ausearch to find AppArmor events, but unfortunately ausearch just cannot handle the AVC message type for AppArmor for some mysterious reason - this is a bug that has been present for a long time:

```
$ sudo ausearch -ts recent -m avc # with AVC it will be the same
<no matches>
```

## Checking the standard profile layout
```
$ tree -d /etc/apparmor.d 
/etc/apparmor.d
├── abstractions
│   ├── apparmor_api
│   └── ubuntu-browsers.d
├── apache2.d
├── cache
├── disable
├── force-complain
├── local
└── tunables
    ├── home.d
    ├── multiarch.d
    └── xdg-user-dirs.d
```

[EXTRA-EXPLANATION]

## Easy profile generation with `aa-logprof`
This time, we are going to confine a shell script with AppArmor:

```
#!/bin/bash

OUTPUT="/tmp/wlog.$(date +%s)"
w > $OUTPUT
cat $OUTPUT | nc 127.0.0.1 1234 > /dev/null

exit 0
```

If we run this script, we should be able to see a file in tmp containing the logged in users.

Now let's generate the default profile and put it into enforce mode:

```
$ sudo aa-autodep ./aa_hello_world.sh
$ sudo aa-enforce /etc/apparmor.d/vagrant.aa_hello_world.sh 
```

Now let's try to run our script again:
```
$ ./aa_hello_world.sh 
./aa_hello_world.sh: line 3: /bin/date: Permission denied
./aa_hello_world.sh: line 4: /tmp/wlog.: Permission denied
./aa_hello_world.sh: line 5: /bin/nc: Permission denied
./aa_hello_world.sh: line 5: /bin/cat: Permission denied
```

[EXTRA-EXPLANATION]

Let's fix it using `aa-genprof`. First of all, let's put the profile back into complain mode:

```
$ sudo aa-complain /etc/apparmor.d/vagrant.aa_hello_world.sh
```

and then:

```
$ sudo aa-genprof ./aa_hello_world.sh
```

and run the script a couple of times in a separate terminal window. Then hit 'S' in the `aa-genprof` window to start generating the profile.

For each execution, create a child profile with environment scrubbing.

Then accept the following statements:

```
#include <abstractions/consoles>
owner /tmp/* w,
owner /tmp/* r,
/etc/nsswitch.conf r,
/etc/services r,
network inet stream,
/proc/sys/kernel/osrelease r,
/proc/ r,
/proc/*/stat r,
/etc/passwd r,
/proc/*/cmdline r,
/proc/uptime r,
/run/utmp rk,
/proc/loadavg r,
```


[EXTRA-EXPLANATION]

Resulting in a raw profile:

```
# Last Modified: Wed Sep  5 01:41:47 2018
#include <tunables/global>

/vagrant/aa_hello_world.sh flags=(complain) {
  #include <abstractions/base>
  #include <abstractions/bash>
  #include <abstractions/consoles>

  /bin/bash ix,
  /bin/cat Cx,
  /bin/date Cx,
  /bin/nc.openbsd Cx,
  /vagrant/aa_hello_world.sh r,
  /lib/x86_64-linux-gnu/ld-*.so mr,
  /usr/bin/w.procps Cx,
  owner /tmp/* w,


  profile /bin/cat flags=(complain) {
    #include <abstractions/base>

    /bin/cat mr,
    /lib/x86_64-linux-gnu/ld-*.so mr,
    owner /tmp/* r,

  }

  profile /bin/date flags=(complain) {
    #include <abstractions/base>

    /bin/date mr,
    /lib/x86_64-linux-gnu/ld-*.so mr,

  }

  profile /bin/nc.openbsd flags=(complain) {
    #include <abstractions/base>

    network inet stream,

    /bin/nc.openbsd mr,
    /etc/nsswitch.conf r,
    /etc/services r,
    /lib/x86_64-linux-gnu/ld-*.so mr,

  }

  profile /usr/bin/w.procps flags=(complain) {
    #include <abstractions/base>

    /etc/nsswitch.conf r,
    /etc/passwd r,
    /lib/x86_64-linux-gnu/ld-*.so mr,
    /proc/ r,
    /proc/*/cmdline r,
    /proc/*/stat r,
    /proc/loadavg r,
    /proc/sys/kernel/osrelease r,
    /proc/uptime r,
    /run/utmp rk,
    /usr/bin/w.procps mr,
    owner /tmp/* w,

  }
}

```

Let's put the profile back into enforce mode and run the script again:

```
$ sudo aa-enforce /etc/apparmor.d/vagrant.aa_hello_world.sh
$ rm /tmp/wlog.*
$ ./aa_hello_world.sh
$ cat /tmp/wlog.*
```

## Inspecting the vulnerabilities of the web application
Let's briefly go through the potential vulnerabilities our web application suffers from.

## Writing our AppArmor profile for a vulnerable web application


## Privilege separation using `aa_change_hat`


## Next steps
