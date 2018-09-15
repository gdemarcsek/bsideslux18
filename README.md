# Introduction

Slides:

* LSM
* MAC
* AppArmor confinement model
* Then lab setup slide and we are kicking off...



# Lab setup

## Required software
 * VirtualBox
 * Vagrant

## Environment setup
Follow the download link to get the Vagrant box and install it:

```
$ vagrant box add --name bsideslux18/apparmor virtualbox-gdemarcs-bsideslux18.box
```



Then spin up the virtual machine:



```
$ git clone --depth=1 --branch master https://github.com/gdemarcsek/bsideslux18.git
$ cd bsideslux18
$ vagrant up && vagrant ssh
$ ls -la /vagrant
```

## Web app setup

This step will only be needed later, but this is how you can set up the Python web app:

```
$ cd ~/vulnerable-web-app
$ sudo pip install virtualenv
$ virtualenv -p python3 --system-site-packages virtualenv
$ source ./virtualenv/bin/activate
$ pip install -r requirements.txt
```

## Building the image

The Vagrant image can also be built locally but it takes quite some time:

```
$ cd image
$ packer build workshop.json
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
sudo journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode 2>/dev/null | grep AVC
```

Checking only access denied events:

```
sudo journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode 2>/dev/null | grep AVC | grep 'apparmor="DENIED"'
```

[EXTRA-EXPLANATION]

Checking status events
```
sudo journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode 2>/dev/null | grep AVC | grep 'apparmor="STATUS"'
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

## Easy profile generation with `aa-logprof / aa-genprof`
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

*Explanation*:

- /etc/nsswitch.conf and /etc/services are needed for DNS and protocol name <-> port resolutions done by netcat
- w needs /etc/passwd and /etc/nsswitch.conf to get user information; it needs /run/utmp because that file contains the login records; it needs a bunch of files from /proc to display the uptime and load averages, CPU time and the command line of itself while /proc/sys/kernel/osrelease is probably needed because different kernels use slightly different utmp file format, fin

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
    owner /tmp/wlog.* w,

  }
}

```

*Explanation*:

What the heck is `/lib/x86_64-linux-gnu/ld-*.so mr` for?  That's the dynamic linker, but then we should see some open and mmap calls to it then when we invoke a dynamically linked executable, right?

```
$ ldd $(which pwd)
$ strace pwd
```

Notice the first few syscalls:

```
execve("/bin/pwd", ["pwd"], 0x7ffe813b04a0 /* 24 vars */) = 0
brk(NULL)                               = 0x560a0dab7000
access("/etc/ld.so.nohwcap", F_OK)      = -1 ENOENT (No such file or directory)
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
fstat(3, {st_mode=S_IFREG|0644, st_size=35872, ...}) = 0
mmap(NULL, 35872, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7f771e606000
close(3)                                = 0
access("/etc/ld.so.nohwcap", F_OK)      = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
...
```

As we can see, instead of opening ld-2.27.so, we are accessing /etc/ld.so.cache - a file that contains library paths compliled by ld.so and it can be used as a cache to find the location of shared objects, like libc - the program gets the location of libc from this file and opens it. So do we really need the read and mmap right for the dynamic linker? Shouldn't we have a rule instead that allows reading and mapping /etc/ld.so.cache? Yep, right, so here is the deal. aa-genprof uses aa-autodep to generate the initial profile before inspecing any logs. Now aa-autodep invoked `ldd` to figure out which shared libraries are required by an ELF executable because it wants to help your life by putting the required shared libraries into the profile automatically. Now  `ldd` shows the loaded libraries after resolution and even those that are mapped automatically by the kernel - these libraries will not show up in the output of `strace` either. 



This is confusing, because if we check the profile of `/bin/ping` , we see no such entry either that would allow the reading and mapping of `/lib/x86_64-linux-gnu/ld-*.so mr` but now we are kind of sure that it would be necessary. 



Enter the base abstraction! Abstractions are common, reusable policies that try to describe privileges needed to perform certain higher level functions, for example:

```
/etc/apparmor.d/abstractions/nameservice - For programs that wish to perform nameservice-like operations (including LDAP, passwd, DNS, etc.)
/etc/apparmor.d/abstractions/python - Adds read and map rights for common standard Python library locations and other shared objects used by the Python interpreter
/etc/apparmor.d/abstractions/bash - Common file access rights needed by bash - thus most shell scripts as well
/etc/apparmor.d/abstractions/consoles - Provides access to terminal devices
/etc/apparmor.d/abstractions/user-tmp - Provides read-write access to per-user and global tmp directories and files in them
/etc/apparmor.d/abstractions/authentication - Access to files commonly needed by apps that perform user authentication (e.g.: PAM modules, /etc/shadow, etc.)
/etc/apparmor.d/abstractions/ssl_certs - Read access to common certificate store locations (almost always needed by clients and servers using TLS)
/etc/apparmor.d/abstractions/gnome - Common access rights generally needed by GNOME applications
/etc/apparmor.d/abstractions/base - Common permissions needed by almost all Linux programs to function
```

The base policy provides a bunch of common permissions that are needed by the vast majority of Linux executables to run, in particular, it takes care of defining rules that allow the loading of shared libraries:

```
$ cat /etc/apparmor.d/abstractions/base | grep ld
```

So, `aa-autodep` is not perfect - it should have recognized that it's adding a duplicate rule. In other words, yes, we could remove those lines, but not because they are not needed, but because they are already present in the base abstraction. 



Let's put the profile back into enforce mode and run the script again:

```
$ sudo aa-enforce /etc/apparmor.d/vagrant.aa_hello_world.sh
$ rm /tmp/wlog.*
$ ./aa_hello_world.sh
$ cat /tmp/wlog.*
```

As we can see, the script works again as expected.



## Using rule qualifiers

Let's create a profile that:

* Allows to read any files in home directories owned by the current user, except for SSH keys and configs (files under ~/.ssh)
* It allows the use of networking, but it will enforce auditing network-related syscalls
* Execute any other program with the same profile



Our target program will be little shell script in `/vagrant/aa_qualifiers.sh` . First we are going to create an initial profile:

```
sudo aa-autodep /vagrant/aa_qualifiers.sh
```



We are going to do this together line by line of course, but the resulting profile should look something like this:



```
# Last Modified: Wed Sep 12 16:08:41 2018
#include <tunables/global>

/vagrant/aa_qualifiers.sh {
  #include <abstractions/base>
  #include <abstractions/bash>

  /bin/bash ix,
  /home/vagrant/aa_qualifiers.sh r,
  /lib/x86_64-linux-gnu/ld-*.so mr,

  owner /home/vagrant/ r,	# the vagrant home dir itself
  owner /home/vagrant/** r,	# all files within the home dir
  owner /home/vagrant/**/ r,    # all directories within the home dir

  deny /home/vagrant/.ssh r,	 # deny read to the .ssh directory itself
  deny /home/vagrant/.ssh/** r,  # deny read to all files within
  deny /home/vagrant/.ssh/**/ r, # deny read to all directories within

  audit network, # audit all network access requests
  /** ix, # allow running any other program with the same confinement
}
```

Running the script we should see error messages when it is trying to read the `authorized_keys` file, thanks to the `deny` qualifier:



```
$ /usr/bin/head: cannot open '/home/vagrant/.ssh/authorized_keys' for reading: Permission denied
```

Now let's create a world-readable root-owned file in vagrant's home directory:

```
$ echo "test" > testfile
$ sudo chown root:root ./testfile
$ sudo chmod o=r ./testfile
```

And add the following line to the `aa_qualifiers.sh` script:

```
/usr/bin/head /home/vagrant/testfile
```

If we try to run again, we should see the following error message in the very end:

```
/usr/bin/head: cannot open '/home/vagrant/testfile' for reading: Permission denied
```

The `owner` qualifier only lets the program read the files that are owned by the same fsuid.



We can inspect the audit records of the network operations attempted by `nc`:

```
$ sudo journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode 2>/dev/null | grep AVC | grep 'apparmor="AUDIT"
Sep 12 16:26:31 vagrant audit[1349]: AVC apparmor="AUDIT" operation="create" profile="/home/vagrant/aa_qualifiers.sh" pid=1349 comm="nc" family="unix" sock_type="stream" protocol=0 requested_mask="create" addr=none
Sep 12 16:26:31 vagrant audit[1349]: AVC apparmor="AUDIT" operation="create" profile="/home/vagrant/aa_qualifiers.sh" pid=1349 comm="nc" family="inet" sock_type="stream" protocol=6 requested_mask="create"
Sep 12 16:26:31 vagrant audit[1349]: AVC apparmor="AUDIT" operation="connect" profile="/home/vagrant/aa_qualifiers.sh" pid=1349 comm="nc" family="inet" sock_type="stream" protocol=6 requested_mask="connect"
Sep 12 16:26:31 vagrant audit[1349]: AVC apparmor="AUDIT" operation="getsockopt" profile="/home/vagrant/aa_qualifiers.sh" pid=1349 comm="nc" laddr=127.0.0.1 lport=53468 faddr=127.0.0.1 fport=80 family="inet" sock_type="stream" protocol=6 requested_mask="getopt"
Sep 12 16:30:53 vagrant audit[8078]: AVC apparmor="AUDIT" operation="create" profile="/home/vagrant/aa_qualifiers.sh" pid=8078 comm="nc" family="unix" sock_type="stream" protocol=0 requested_mask="create" addr=none
Sep 12 16:30:53 vagrant audit[8078]: AVC apparmor="AUDIT" operation="create" profile="/home/vagrant/aa_qualifiers.sh" pid=8078 comm="nc" family="unix" sock_type="stream" protocol=0 requested_mask="create" addr=none
Sep 12 16:30:53 vagrant audit[8078]: AVC apparmor="AUDIT" operation="create" profile="/home/vagrant/aa_qualifiers.sh" pid=8078 comm="nc" family="inet" sock_type="stream" protocol=6 requested_mask="create"
Sep 12 16:30:53 vagrant audit[8078]: AVC apparmor="AUDIT" operation="connect" profile="/home/vagrant/aa_qualifiers.sh" pid=8078 comm="nc" family="inet" sock_type="stream" protocol=6 requested_mask="connect"
Sep 12 16:30:53 vagrant audit[8078]: AVC apparmor="AUDIT" operation="getsockopt" profile="/home/vagrant/aa_qualifiers.sh" pid=8078 comm="nc" laddr=127.0.0.1 lport=53470 faddr=127.0.0.1 fport=80 family="inet" sock_type="stream" protocol=6 requested_mask="getopt"
...
```



## Inspecting the vulnerabilities of the web application

Let's briefly go through the potential vulnerabilities our web application suffers from. First of all, let's have a screen session inside the VM - just so we can have multiple terminals - and start the web application (assuming the web app is set up as shown in the earlier chapter and we are already in the virtualenv in `/vagrant/vulnerable-web-app/`):



```
$ gunicorn -c gunicorn.conf.py wsgi
```

Now if you used the Vagrantfile f rom the repository, port forwarding should be set up so unless there was a port collision, you can take your browser and navigate to:

```
http://localhost:8080/
```

First of all, let's try it with something inoccous: try and resize `payloads/innocent.jpg` - we will get back the resized version. In the background, the web application called a CLI utility of the ImageMagick image processing library to rescale the picture. 



*Together: Check the code of the application*



Now as we can see our little web service is quite simple and looks pretty much secure Unfortunately though, the ImageMagick library and - thus the convert utility as well - is vulnerable to various attack vectors, including arbitrary command execution, local file read, local file deletion and server side request forgery. I'm pretty sure that you know what we are seeing here - we are dealing with the infamous shitbucket often referred to as "ImageTragick". 



So let's quickly try our a few scenarios, just to prove that the vulnerabilities are really there:



```
payloads/rce.jpg - Execute arbitrary command (the file you-are-owned will appear)
payloads/read.jpg - Read /etc/passwd
payloads/delete.jpg - Delete the .bash_history file of the vagrant user
```

*Explanation*: Briefly explain how the vulnerabilities work, without going very much into details as it is not very important in the context of this workshop. 

 

## Writing our AppArmor profile for a vulnerable web application

Let's stop the web service for a while. We are going to create a profile in 2 phases:

1. Startup and serving requests - first we. only start and stop the application to see what common access rights are needed
2. We are going to exercise the app with a legitimate payload (innocent.jpg)

But first, which process are we trying to confine? To answer that question, we must ask ourselves: which file is executed to start the server process? Well it is unicorn:

```
$ which gunicorn
/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn
```

Well obviously, there could be some other shell scripts wrapping the gunicorn process, but that's OK, our app would still be confined. The problem arises when somebody starts our WSGI applciation with an alternative web server, say Flask's development server or Tornado. If the service is started without executing the gunicorn file, our web app would stay unconfined and unprotected. We are going to address this later on, but for the moment, let's just ignore this problem for a second, we will get back to this.





## Privilege separation using `aa_change_hat`





## Kernel hardening and what happens if we don't have it





## Risks of not scrubbing the environment





## Application-initiated confinement (or `aa_change_profile`)



## Some bypass routes



TODO: 

* cap_sys_module
* writes to /etc/cron.d/** or ~/.bashrc etc.
* 




## Next steps
