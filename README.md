# Introduction

This is the repository of my AppArmor workshop at BSides Luxembourg 2018



# Lab setup

## Required software
 * VirtualBox (>= 5.2.19)
 * Vagrant (>= 2.1.2) -- recommended

## Environment setup
Follow the download link to get the Vagrant box and install it:

```
$ vagrant box add --force --name bsideslux18/apparmor virtualbox-gdemarcs-bsideslux18.box
```

Then spin up the virtual machine:

```
$ git clone --depth=1 --branch master https://github.com/gdemarcsek/bsideslux18.git
$ cd bsideslux18
$ vagrant up && vagrant ssh
$ ls -la /vagrant
```

Note: Please make sure that port 8080 is free to bind to on your host OS while the workshop VM is running!

## Building the image

The Vagrant image can also be built locally but it takes quite some time - please do not do this during the workshop ;)

```
$ cd image
$ packer build workshop.json
```

# Lab tasks

## Checking confinement status

```
$ sudo aa-status
```

## Making sure AppArmor is started at boot
```
$ sudo systemctl enable apparmor
```

## Logging with auditd

Make sure auditd is running and enabled at boot:

```
$ sudo service auditd status # or start
$ sudo systemctl enable auditd
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

`aa-autodep` simply enumerates the output of `ldd aa_hello_world` to figure out the required shared libraries, plus it includes some trivial statements, like including the base abstraction (required for pretty much all profiles, we will see later on) and adding a statement that allows to execute the binary itself. It is also smart enough to parse the hashbang in the initial line of scripts - we will also see this later.

Now let's check the generated profile!

```
$ sudo cat /etc/apparmor.d/vagrant.aa_hello_world 
```

Load it and put it into enforce mode:

```
$ sudo aa-enforce /vagrant/aa_hello_world
```

And try to execute it again:

```
$ ./aa_hello_world
getpwuid: Permission denied
```

AppArmor is preventing our process form making certain syscalls. Let's see why using `strace`:


```
$ strace ./aa_hello_world 2>&1 | grep EACCES
openat(AT_FDCWD, "/etc/passwd", O_RDONLY|O_CLOEXEC) = -1 EACCES (Permission denied)
openat(AT_FDCWD, "/etc/passwd", O_RDONLY|O_CLOEXEC) = -1 EACCES (Permission denied)
```

Since the confinement model dictates deny by default for profiles in enforcement mode and our profile does not specify any allowed permissions for these files, AppArmor prevents the syscall from propagation. 

Let's try running it as root, after all, root is above all mortal souls in Linux:

```
$ sudo ./aa_hello_world
getpwuid: Permission denied
```

AppArmor enforces the policy for the root user too.



Now let's fix the AppArmor profile - we want it to allow all legal actions of our applications, in other words, our profile is a description of "normal" behaviour:

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
// aa_hello_world_2.c
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
        } else {
        	printf("Home directory: %s\n", ent->pw_dir);
        }
        sleep(5);
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
sudo journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode | grep AVC
```

Checking only access denied events:

```
sudo journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode | grep AVC | grep 'apparmor="DENIED"'
```

Interpretation:

* `apparmor`: Indicates the AppArmor event type (DENIED - access denial, ALLOWED - permission granted, STATUS - profile operations)
* `operation`: Indicates the intercepted syscall
* `profile`: The profile in which the process that made the syscall was confined within at the time of the call
* `name`: Name of the requested resource (e.g. filename)
* `pid`: Process ID of the caller process
* `comm`: Command line of the caller process
* `requested_mask`: The list of requested access rights
* `denied_mask`: The list of denied access rights (according to policy - not affected by confinement mode)
* `fsuid`: fsuid of the caller program
* `ouid`: Owner UID of the requested object



Checking status events

```
sudo journalctl --since yesterday -a _TRANSPORT=audit --no-pager | aa-decode | grep AVC | grep 'apparmor="STATUS"'
```

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

* abstractions: Collection of re-usable policy statements that provide a common set of rights for abstract program types
* tunables: Contains variable definitions
* cache: Cache of compiled profiles
* disable: Init script will disable profiles symlinked here
* force-complain: Init script will put profiles symlinked here into complain mode

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
- `w` needs `/etc/passwd` and `/etc/nsswitch.conf` to get user information; it needs /run/utmp because that file contains the login records; it needs a bunch of files from /proc to display the uptime and load averages, CPU time and the command line of itself while /proc/sys/kernel/osrelease is probably needed because different kernels use slightly different utmp file format, fin

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



OPTIONAL-CONTENT

----



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

As we can see, instead of opening `ld-2.27.so`, we are accessing `/etc/ld.so.cache` - a file that contains library paths compliled by `ld.so` and it can be used as a cache to find the location of shared objects, like libc - the program gets the location of libc from this file and opens it. So do we really need the read and `mmap/PROT_EXEC` right for the dynamic linker? Shouldn't we have a rule instead that allows reading and mapping `/etc/ld.so.cache`? Yep, right, so here is the deal. `aa-genprof` uses  `aa-autodep` (on the Python API level) to generate the initial profile before inspecing any logs. Now aa-autodep invoked `ldd` to figure out which shared libraries are required by an ELF executable because it wants to help your life by putting the required shared libraries into the profile automatically. Now  `ldd` shows the loaded libraries after resolution and even those that are mapped automatically by the kernel - these libraries will not show up in the output of `strace` either (see: `man vdso`)



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

But for some reason, none of these statements match the location of ld on this particular distribution, so that's why `aa-autodep` has to generate that rule.

```
$ sudo aa-enforce /etc/apparmor.d/vagrant.aa_hello_world.sh
$ rm /tmp/wlog.*
$ ./aa_hello_world.sh
$ cat /tmp/wlog.*
```

As we can see, the script works again as expected.

---





## Using rule qualifiers

Let's create a profile that:

* Allows to read any user-owned files in vagrant's home, except for SSH keys and configs (files under ~/.ssh)
* Allows the execution any other program with the same profile but with auditing enforced

Our target program will be little shell script in `/vagrant/aa_qualifiers.sh` . First we are going to create an initial profile:

```
$ sudo aa-autodep /vagrant/aa_qualifiers.sh
```



We are going to do this together line by line of course, but the resulting profile should look something like this:



```
# Last Modified: Wed Sep 12 16:08:41 2018
#include <tunables/global>

/vagrant/aa_qualifiers.sh {
  #include <abstractions/base>
  #include <abstractions/bash>

  /bin/bash ix,
  /vagrant/aa_qualifiers.sh r,
  /lib/x86_64-linux-gnu/ld-*.so mr,

  owner /home/vagrant/** r,	# all files and dirs within the home dir
  deny /home/vagrant/.ssh/** r,  # deny read to all files and dirs within

  audit /** ix, # allow running any other program with the same confinement
}
```

Running the script we should see error messages when it is trying to read the `authorized_keys` file, thanks to the `deny` qualifier:

```
$ /usr/bin/head: cannot open '/home/vagrant/.ssh/authorized_keys' for reading: Permission denied
```

Now let's create a world-readable root-owned file in vagrant's home directory:

```
$ echo "test" > /home/vagrant/testfile
$ sudo chown root:root /home/vagrant/testfile
$ sudo chmod o=r /home/vagrant/testfile
```

And add the following line to the `aa_qualifiers.sh` script:

```
/usr/bin/head /home/vagrant/testfile
```

If we try to run again, we should see the following error message in the very end:

```
/usr/bin/head: cannot open '/home/vagrant/testfile' for reading: Permission denied
```

The `owner` qualifier only lets the program read the files that are owned by the same fsuid (oid=fsuid). If we ran the script as root <--- I might have discovered an AppArmor bug here: TODO look into this!!!!



## Inspecting the vulnerabilities of the web application

Let's briefly go through the potential vulnerabilities our web application suffers from. First of all, let's have a `tmux` session inside the VM - just so we can have multiple terminals - and start the web application (assuming the web app is set up as shown in the earlier chapter and we are already in the virtualenv in `/vagrant/vulnerable-web-app/`):

```
$ gunicorn -c gunicorn.conf.py wsgi
```

Now if you used the Vagrantfile f rom the repository, port forwarding should be set up so unless there was a port collision, you can take your browser and navigate to:

```
http://localhost:8080/
```

First of all, let's try it with something inoccous: try and resize `payloads/innocent.jpg` - we will get back the resized version. In the background, the web application called a CLI utility of the ImageMagick image processing library to rescale the picture. 



Check the code of the application in `/vagrant/application.py` to see how it works.



Now as we can see our little web service is quite simple and looks pretty much secure. Unfortunately though, the ImageMagick library and - thus the `convert` utility as well - is vulnerable to various attack vectors, including arbitrary command execution, local file read, local file deletion and server side request forgery. I'm pretty sure that you know what we are seeing here - we are dealing with the infamous shitbucket often referred to as "ImageTragick". 



So let's quickly try our a few scenarios, just to prove that the vulnerabilities are really there:

```
payloads/rce.jpg - Execute arbitrary command (the file you-are-owned will appear)
payloads/read.jpg - Read /etc/passwd
payloads/delete.jpg - Delete the .bash_history file of the vagrant user
```

*Explanation*: Briefly explain how the vulnerabilities work, without going very much into details as it is not very important in the context of this workshop. 

 

## Writing our AppArmor profile for a vulnerable web application

We are going to immunize our web application to all of these flaws by carefully confining it with AppArmor. Let's kick things off with an initial profile - move it to `/etc/apparmor.d/vulnerable` and enforce it!

```
## SNIPPET-gunicorn-initial
# Last Modified: Sat Sep 15 09:40:15 2018
#include <tunables/global>

@{APP_ROOT} = /vagrant/vulnerable-web-app

profile vulnerable @{APP_ROOT}/virtualenv/bin/gunicorn {
  #include <abstractions/base>
  #include <abstractions/python>

  # Dynamic linker
  /lib/x86_64-linux-gnu/ld-*.so mr,

  # The app root DIRECTORY itself
  @{APP_ROOT}/ r,

  # Gunicorn and Python
  @{APP_ROOT}/virtualenv/bin/gunicorn r,
  @{APP_ROOT}/virtualenv/bin/python3 ix,

  # Python files and libs
  @{APP_ROOT}/__pycache__ r,
  @{APP_ROOT}/__pycache__/**/ r,
  @{APP_ROOT}/__pycache__/*.{py,pyc} mr,
  @{APP_ROOT}/*.{py,pyc} mr,
  @{APP_ROOT}/virtualenv/* r,
  @{APP_ROOT}/virtualenv/**/ r,
  @{APP_ROOT}/virtualenv/lib/**.{py,pyc} mr,

  @{APP_ROOT}/virtualenv/lib/python3.6/orig-prefix.txt r,
}
```

This is the point for me to say: I do not *generally* suggest to use `aa-logprof` / `aa-genprof` - it's quite full of bugs and doesn't provide so much of help in case of complex applications. So instead, let's just start from here, put it into enforce mode and work our way to making things work. Don't forget, first we will just focus on getting the Python service running, without exercising any functionality. 



The first problem will we see is that the service is not able to open a socket and listen on it:

```
[2018-09-15 11:52:53 +0000] [16954] [ERROR] Can't connect to ('0.0.0.0', 8080)
```

Not too surprising: we did not yet allow our program to use the network, so let's add the rule that allows TCP/IP networking:

```
network inet tcp
```

The next issue we will run into is that gunicorn tries to use some temporary files:

```
[2018-09-15 11:58:08 +0000] [17083] [INFO] Unhandled exception in main loop
Traceback (most recent call last):
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/site-packages/gunicorn/arbiter.py", line 202, in run
    self.manage_workers()
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/site-packages/gunicorn/arbiter.py", line 544, in manage_workers
    self.spawn_workers()
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/site-packages/gunicorn/arbiter.py", line 611, in spawn_workers
    self.spawn_worker()
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/site-packages/gunicorn/arbiter.py", line 564, in spawn_worker
    self.cfg, self.log)
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/site-packages/gunicorn/workers/base.py", line 57, in __init__
    self.tmp = WorkerTmp(cfg)
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/site-packages/gunicorn/workers/workertmp.py", line 23, in __init__
    fd, name = tempfile.mkstemp(prefix="wgunicorn-", dir=fdir)
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/tempfile.py", line 474, in mkstemp
    prefix, suffix, dir, output_type = _sanitize_params(prefix, suffix, dir)
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/tempfile.py", line 269, in _sanitize_params
    dir = gettempdir()
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/tempfile.py", line 435, in gettempdir
    tempdir = _get_default_tempdir()
  File "/vagrant/vulnerable-web-app/virtualenv/lib/python3.6/tempfile.py", line 370, in _get_default_tempdir
    dirlist)
FileNotFoundError: [Errno 2] No usable temporary directory found in ['/tmp', '/var/tmp', '/usr/tmp', '/vagrant/vulnerable-web-app']
```

Now if we looked at the syscall trace, we would notice that Python's tempfile implementation tries to create a file in several candidate directories for temp file storage to find the first one that could be used by the application. Now instead of trying to figure out what to do, let's use screen to set up a log monitor which will tail the audit logs for us so wen can see what access was denied exactly:

```
$ sudo journalctl -f -a _TRANSPORT=audit | aa-decode 2>/dev/null | grep 'apparmor="DENIED"'
```

Well, not too surprisingly, we will see:

```
Sep 15 12:37:09 vagrant audit[21265]: AVC apparmor="DENIED" operation="mknod" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/tmp/hptnmcg1" pid=21265 comm="gunicorn" requested_mask="c" denied_mask="c" fsuid=900 ouid=900
Sep 15 12:37:09 vagrant audit[21265]: AVC apparmor="DENIED" operation="mknod" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/var/tmp/4g3a6wxy" pid=21265 comm="gunicorn" requested_mask="c" denied_mask="c" fsuid=900 ouid=900
Sep 15 12:37:09 vagrant audit[21265]: AVC apparmor="DENIED" operation="mknod" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/vagrant/vulnerable-web-app/deal712z" pid=21265 comm="gunicorn" requested_mask="c" denied_mask="c" fsuid=900 ouid=900
```

So let's choose a temporary directory and provide write access to the files in it:

```
/tmp/** rw,
```

If we try the profile again, we will see that read access will also be required, so let's add the `r` permission as well.

We will see a few additional access request denials. For example, gunicorn needs to determine the current username so that it can query the corresponding complementary groups when setting ip the ownership of. worker processes - we can confirm that gunicorn calls `getpwuid()` using `ltrace` but the point is that when we trust that are system is not compromised, we should be OK with providing the necessary permissions without having the understand the exact reason behind them - it's cool if we do, but it's really not that important - on the other hand, as a side effect, AppArmor profiling gives us an opportunity to learn more about how our stuff works and what it is doing under the hood.



Having that said, the final profile that enables us to at least successfully start the `gunicorn` workers will look something like:



````
# Last Modified: Sat Sep 15 09:40:15 2018
#include <tunables/global>

@{APP_ROOT} = /vagrant/vulnerable-web-app

profile vulnerable @{APP_ROOT}/virtualenv/bin/gunicorn {
  #include <abstractions/base>
  #include <abstractions/python>

  # Dynamic linker
  /lib/x86_64-linux-gnu/ld-*.so mr,

  # The app root DIRECTORY itself
  @{APP_ROOT}/ r,

  # Gunicorn and Python
  @{APP_ROOT}/virtualenv/bin/gunicorn r,
  @{APP_ROOT}/virtualenv/bin/python3 ix,

  # Python files and libs
  @{APP_ROOT}/__pycache__ r,
  @{APP_ROOT}/__pycache__/** wmr,
  @{APP_ROOT}/__pycache__/*.{py,pyc} mr,
  @{APP_ROOT}/*.{py,pyc} mr,
  @{APP_ROOT}/virtualenv/* r,
  @{APP_ROOT}/virtualenv/**/ r,
  @{APP_ROOT}/virtualenv/lib/**.{py,pyc} mr,

  @{APP_ROOT}/virtualenv/lib/python3.6/orig-prefix.txt r,

  # Networking
  audit network inet tcp,

  # Temporary file access
  /tmp/** rw,

  # Reading the user database
  /etc/nsswitch.conf r,
  /etc/passwd r,

  # Read some process info
  owner /proc/@{pid}/fd r,
  owner /proc/@{pid}/mounts r,
}
````



If we try this and take a look at the error messages, we can still see issues like these:

```
Sep 22 20:10:01 vagrant audit[3970]: AVC apparmor="DENIED" operation="exec" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/sbin/ldconfig" pid=3970 comm="gunicorn" requested_mask="x" denied_mask="x" fsuid=900 ouid=0
Sep 22 20:10:01 vagrant audit[3968]: AVC apparmor="DENIED" operation="exec" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/usr/bin/x86_64-linux-gnu-gcc-7" pid=3968 comm="gunicorn" requested_mask="x" denied_mask="x" fsuid=900 ouid=0
Sep 22 20:10:01 vagrant audit[3971]: AVC apparmor="DENIED" operation="exec" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/usr/bin/x86_64-linux-gnu-gcc-7" pid=3971 comm="gunicorn" requested_mask="x" denied_mask="x" fsuid=900 ouid=0
Sep 22 20:10:01 vagrant audit[3973]: AVC apparmor="DENIED" operation="exec" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/usr/bin/x86_64-linux-gnu-ld.bfd" pid=3973 comm="gunicorn" requested_mask="x" denied_mask="x" fsuid=900 ouid=0
Sep 22 20:10:01 vagrant audit[3972]: AVC apparmor="DENIED" operation="exec" profile="/vagrant/vulnerable-web-app/virtualenv/bin/gunicorn" name="/usr/bin/x86_64-linux-gnu-ld.bfd" pid=3972 comm="gunicorn" requested_mask="x" denied_mask="x" fsuid=900 ouid=0
```

We might wonder why our program needs to execute `ld`, `gcc` and `ldconfig` - well, it is mainly because we are using CPython where a significant part of Python modules use C libraries via the `ctype` Python module - which uses these executables to locate loadable shared libraries. Now while often times, well written modules will fall back to Python implementations when a native library is not found, unfortunately we cannot really on that generally, so we are going to have to include permissions to execute these binaries - although it would make sense to create a child profile for them. 



OPTIONAL-CONTENT

---

Native extensions use ldconfig:

```
$ strace -f -e execve python
execve("/vagrant/vulnerable-web-app/virtualenv/bin/python", ["python"], 0x7ffdf49f3a38 /* 109 vars */) = 0
Python 3.6.5 (default, Apr  1 2018, 05:46:30)
[GCC 7.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import ctypes.util
>>> ctypes.util.find_library("c")
strace: Process 12642 attached
[pid 12642] execve("/sbin/ldconfig", ["/sbin/ldconfig", "-p"], 0x7fd2db080900 /* 2 vars */) = 0
[pid 12642] execve("/sbin/ldconfig.real", ["/sbin/ldconfig.real", "-p"], 0x55e199808bd0 /* 3 vars */) = 0
[pid 12642] +++ exited with 0 +++
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=12642, si_uid=900, si_status=0, si_utime=0, si_stime=0} ---
'libc.so.6'
>>> quit()
+++ exited with 0 +++
```

The `requests` package runs `uname` in a shell to identify the OS:

```
$ strace -f -e execve python
execve("/vagrant/vulnerable-web-app/virtualenv/bin/python", ["python"], 0x7fffdea4e518 /* 109 vars */) = 0
Python 3.6.5 (default, Apr  1 2018, 05:46:30)
[GCC 7.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import requests
strace: Process 20726 attached
[pid 20726] execve("/sbin/ldconfig", ["/sbin/ldconfig", "-p"], 0x7fbefe993ca8 /* 2 vars */) = 0
[pid 20726] execve("/sbin/ldconfig.real", ["/sbin/ldconfig.real", "-p"], 0x55a705863bd0 /* 3 vars */) = 0
[pid 20726] +++ exited with 0 +++
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=20726, si_uid=900, si_status=0, si_utime=0, si_stime=0} ---
strace: Process 20727 attached
[pid 20727] execve("/bin/sh", ["/bin/sh", "-c", "uname -p 2> /dev/null"], 0x1f6aac0 /* 111 vars */) = 0
strace: Process 20728 attached
[pid 20728] execve("/bin/uname", ["uname", "-p"], 0x555d612fd8f8 /* 111 vars */) = 0
[pid 20728] +++ exited with 0 +++
[pid 20727] --- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=20728, si_uid=900, si_status=0, si_utime=0, si_stime=0} ---
[pid 20727] +++ exited with 0 +++
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=20727, si_uid=900, si_status=0, si_utime=0, si_stime=0} ---
>>>
```

----



By the. time we go through all the things needed by the Python ecosystem, we should end up with this profile:



```
## SNIPPET-python-ecosystem
# Last Modified: Sat Sep 15 09:40:15 2018
#include <tunables/global>

@{APP_ROOT} = /vagrant/vulnerable-web-app

# We did this at this point because of an AppArmor bug that prevents subprofile transitions when the parent profile's name contains a variable but this will become useful for other reasons as well later!
profile vulnerable @{APP_ROOT}/virtualenv/bin/gunicorn {
  #include <abstractions/base>
  #include <abstractions/python>

  # Dynamic linker
  /lib/x86_64-linux-gnu/ld-*.so mr,
  
  # Gunicorn app abstraction
  #include <abstractions/gunicorn_app>
  
  # Reading the user database
  audit /etc/passwd r,
  /etc/nsswitch.conf r,
}
```

 We are creating our own abstraction here, as that part of the profile might be a good candidate for re-use in other applications. The contents of `abstractions/gunicorn_app` are as follows:

```
# The app root DIRECTORY itself
@{APP_ROOT}/ r,

# Gunicorn and Python
@{APP_ROOT}/virtualenv/bin/gunicorn r,
@{APP_ROOT}/virtualenv/bin/python3 ix,

# Python files and libs
@{APP_ROOT}/__pycache__ r,
@{APP_ROOT}/__pycache__/** wmr,
@{APP_ROOT}/__pycache__/*.{py,pyc} mr,
@{APP_ROOT}/*.{py,pyc} mr,
@{APP_ROOT}/virtualenv/* r,
@{APP_ROOT}/virtualenv/**/ r,
@{APP_ROOT}/virtualenv/lib/**.{py,pyc} mr,

@{APP_ROOT}/virtualenv/lib/python3.6/orig-prefix.txt r,

# Networking
network inet tcp,

# Temporary file access
/tmp/** rw,

# Read some process info
owner /proc/@{pid}/fd/ r,
owner /proc/@{pid}/mounts r,

# Often needed by native extensions
/bin/dash mrix,
/bin/uname mrix, # Some modules execute uname to figure out the current OS instead of using os.uname...
/{usr/bin/x86_64-linux-gnu-gcc-7,sbin/ldconfig,sbin/ldconfig.real,usr/bin/x86_64-linux-gnu-ld.bfd} mrix,
/bin/dash mrix,
/usr/bin/x86_64-linux-gnu-objdump mrix,
/tmp/* wr,
/usr/lib/gcc/x86_64-linux-gnu/7/collect2 mrix,
```

Now if we make our first request, we will notice that the application fails to read its configuration file, e.g.:

```
Sep 24 16:30:41 vagrant audit[24504]: AVC apparmor="DENIED" operation="open" profile="vulnerable" name="/vagrant/vulnerable-web-app/config.prod.cfg" pid=24504 comm="gunicorn" requested_mask="r" denied_mask="r" fsuid=900 ouid=900
```

so we can go ahead and add a new line allowing read access to the config file. If we read the source code carefully, we know that we will need it to have access to the HTML template files as well, so these are the two lines we need to add to load the page at `localhost:8080`:

```
 # Reading configuration file
 @{APP_ROOT}/config.prod.cfg r,

 # Reading template files
 @{APP_ROOT}/templates/*.html r,
```

We can work our way further in the application: the next is to cover `convert_user_file`: we could be following the logs, creating a child profile this time for ImageMagick. Nothing surprising will be there,, but in practice, we should stick with following the audit logs - those never lie (e.g. it will show you real paths resolving all symbolic links and because they are from the running application, we are seeing the results corresponding to the current runtime environment). Now to speed things up, we can just copy & paste this subprofile to the big one:

```
# SNIPPET-imagemagick-subprofile
@{UPLOADS_DIR} = /tmp/bsideslux18/uploads/
@{RESULTS_DIR} = /tmp/bsideslux18/converted/
/usr/local/bin/convert Cx -> imagemagick,
profile imagemagick {
    #include <abstractions/base>
    # convert cli
    /usr/local/bin/convert mrix,
    # ImageMagick shared libraries
    /usr/local/lib/*.so* mr,
    # ImageMagick config files
    /usr/local/{etc,share}/ImageMagick-6/* r,
    # User files (input and output)
    @{UPLOADS_DIR}/* r,
    @{RESULTS_DIR}/* rw,
}
```

The rule above specifies that the `convert` utility can be executed with environment scrubbing and the current profile must be changed to a child profile named `imagemagick` - should the child profile not exist, the profile transition and the command execution would fail.

With this updated profile, if we try out our application, it finally works perfectly! But what did we really accomplish here? Let's try to attack the app again with the ImageTragick payloads one by one and let's follow the logs in the meantime. Can we still exploit the vulnerabilities? 



## Privilege separation using the AppArmor API

Notice the following: in the parent profile, we could say that not all the privileges are needed by all parts of the program - certain permissions are only needed temporarily or only within some well-defined scope, e.g. a particular method. Namely:

* Access to the configuration file is only needed once, before the first request is made - this should most certainly be leveraged since config files often contain secrets in real-world examples
* Only the `index()` function needs to read the template files
* Our app only needs to be able to run ImageMagick from the convert_user_file() method
* Reading `/etc/passwd` and `/etc/nsswitch.conf` is really only needed by the gunicorn server during startup, otherwise we do not need it

These are all opportunities to further restrict what our application can and cannot do in terms of syscalls throughout its lifecycle. If you think about, child profiles are already a way to kind of switch between sets of permissions, but what if we want to do this programatically, from within the application so that we can implement this level of control - often referred to as privilege separation?

We can use the userspace AppArmor library  (`libapparmor`) .

Let's quickly review `apparmor_utils.py` a Python utility library that makes it easy to use the AppArmor API: it basically provides 3 utilities:

* the `sandbox` class is a context manager that can also be used as a function decorator in order to confine parts of the program in a special child profile, called "hat" - the difference between a hat and a (sub)profile is that the process is allowed to resume from a hat to its previous security context, so the parent profile, while this is not true for regular profiles unless there is an explicit rule that allows transition back to the parent profile
* the `get_current_confinement` function can be used for debugging - it returns the current security context of the process - this one actually uses the low-level interface instead of utilizing libapparmor (the reason behind this has to do with the fact that the Python binding of libapparmor is created with code generation and it is not so perfect nor comfortable to use but in general, the procfs-based interactions should be avoided as this interface may be subject to breaking changes contrary to the C API)
* `enter_confinement` is a convenience method to switch to a (sub)profile - this operation must be explicitly allowed by the parent profile, and as it was said earlier, this is a one-way translation unless explicitly allowed from the child profile as well to switch back. This method always uses `aa_change_profile` instead of `aa_change_hat` - the former is allowed for unconfined applications, but the latter is not. This also means that applications can initiate their own confinement using this method when they start by knowing their profile's name - which means that confinement no longer has to depend on matching the application executable's path to the profile attachment! That's pretty great because it makes it virtually impossible for the application to start unconfined! You can check this by uncommenting the call to `enter_confinement("vulnerable")` and removing the path attachment from the profile description (changing `profile vulnerable @{APP_ROOT}/virtualenv/bin/gunicorn {` to just `profile vulnerable {`).

(A note on nesting profiles: in principle, it is allowed to nest multiple subprofiles - the kernel component should definitely support it by now, however, this doesn't help us too much because the userspace APIs and tools do not fully support this feature. This is possible because the AppArmor profile language is just an intermediate language - in fact the kernel uses a compiled, binary version of the profiles internally. Howeber, `apparmor_parser` may not support all features of the internal language yet. Anyways, do not count on nesting subprofiles just yet, at least this is my experience.)



Let's uncomment the decorators from the endpoints in `application,py` and tranform our profile to the following:

```
# SNIPPET-privsep-final
#include <tunables/global>
#include <tunables/sys>

@{APP_ROOT} = /vagrant/vulnerable-web-app
@{UPLOADS_DIR} = /tmp/bsideslux18/uploads/
@{RESULTS_DIR} = /tmp/bsideslux18/converted/
@{PARENT_PROFILE} = vulnerable

profile vulnerable @{APP_ROOT}/virtualenv/bin/gunicorn {
  #include <abstractions/base>
  #include <abstractions/apparmor_api>
  #include <abstractions/gunicorn_app>

  # Dynamic linker
  /lib/x86_64-linux-gnu/ld-*.so mr,

  # Reading the user database
  /etc/passwd r,
  /etc/nsswitch.conf r,

  ^needs_config_file_access {
    #include <abstractions/base>
    #include <abstractions/gunicorn_app>
    #include <abstractions/apparmor_api>
    ## Reading configuration file
    @{APP_ROOT}/config.prod.cfg r,
  }

  ^needs_html_templates {
    # Reading template files
    #include <abstractions/base>
    #include <abstractions/gunicorn_app>
    #include <abstractions/apparmor_api>
    @{APP_ROOT}/templates/*.html r,
  }

  ^needs_imagemagick {
    #include <abstractions/base>
    #include <abstractions/gunicorn_app>
    #include <abstractions/apparmor_api>
    # Run imagemagick to convert stuff
    # convert cli
    /usr/local/bin/convert mrix,
    # ImageMagick shared libraries
    /usr/local/lib/*.so* mr,
    # ImageMagick config files
    /usr/local/etc/ImageMagick-6/* r,
    /usr/local/share/ImageMagick-6/* r,
    # User files (input and output)
    @{UPLOADS_DIR}/* r,
    @{RESULTS_DIR}/* rw,
  }
}
```

The `apparmor_api` abstraction allows us to use a low level interface of the AppArmor API with file operations over `/proc/$pid/attr/current`. Child profiles prefixed with the ^ are hats - there is no need to explicitly allow hat transitions - once defined, it is legal for the program to transition from the parent profile to one of its hats.



## Bypasses and privilege escalations

AppArmor (like everything else) is not snake oil - it is just as good at preventing incidents with sandboxing as your profiles are. (And it has its own share of bugs and problems and complexities just as any other piece of software).

* rename_problem + demo with caveats/rename_problem.c
* writes to `cron.d/*` files
* `sys_ptrace` + injection (`/proc/sys/kernel/yama/ptrace_scope` and  write to `/proc/<pid>/mem`)
* writes to `/proc/<pid>/attr/current` - changing AppArmor profile
* `cap_sys_module` and several other capability rules may be too permissive
* lack of environment scrubbing on execution (using lowercase `px` and `cx` instead of `Px` and `Cx`) may make it possible to exploit `LD_PRELOAD` to alter program execution,
* profile transitions do not automatically close open file descriptors which may cause information leakage from parent to child - for `execve`-initiated transitions, this can be mitigated by supplying the `O_CLOEXEC` flag when `open`-ing a file, but for transitions done through the AppArmor API (`aa_change_profile`, `aa_change_hat`) the programmer needs to take care of closing open file descriptors to sensitive files

 First of all, go to `/vagrant/caveats` and run `make` to put everything we need in place.

## Rename problem

In this scenario, the profile for `rename_problem` allows read-write access to all files and directories within `/home/vagrant` while explicitly denies read access to `/home/vagrant/.ssh/id_rsa` . This looks fine, one might think that this profile does not let an application read the SSH private key. That's what `rename_problem` tries to do nevertheless, just in a tricky way:

```
$ sudo aa-enforce /etc/apparmor.d/rename_problem
$ ./rename_problem
```

The bypass works by first exploiting the write permission in `/home/vagrant` and renaming the `.ssh` directory. Than because we have read access to all files except `/home/vagrant/.ssh/id_rsa` - but that is now, after the rename, called `/home/vagrant/.sshx/id_rsa` , we can read the renamed file without a problem. Then we may clean up our mess to remain undetected and not break SSH. Check `rename_problem.c` !



## Powerful capabilities

Certain capabilities can provide extremely powerful permissions. One of my favourites is `sys_module` which allows a program to load an arbitrary kernel module into the kernel. Thus an attacker can exploit this to load a module that bypasses AppArmor by simply not using any syscalls to access files, but instead use the VFS kernel API to carry out file operations. 



The profile of `/vagrant/caveats/cap_problem.sh` does not alllow any read access, yet, the process will steal information from `/etc/shadow` by loading a kernel module that directly reads it, bypassing the standard I/O system calls:

```
$ sudo aa-enforce /etc/apparmor.d/cap_problem
$ sudo ./cap_problem.sh
$ sudo dmesg
```

