#include <tunables/global>

profile /vagrant/caveats/cap_problem.sh {
  #include <abstractions/base>
  #include <abstractions/bash>
  #include <abstractions/consoles>
  /** ix,
  /proc/** r,
  /vagrant/caveats/cap_problem.sh r,
  /vagrant/caveats/** mr,
  capability sys_module,
  deny /etc/shadow r, # explicit deny!!!
}
