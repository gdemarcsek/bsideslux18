#include <tunables/global>

profile /vagrant/caveats/rename_problem {
	#include <abstractions/base>
	/home/vagrant/** wr,
	deny /home/vagrant/.ssh/id_rsa r,
}
