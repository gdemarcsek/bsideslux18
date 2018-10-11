obj-m += sys_module.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
	gcc rename_problem.c -o rename_problem
	sudo cp rename_problem.profile /etc/apparmor.d/rename_problem
	sudo cp cap_problem.profile /etc/apparmor.d/cap_problem
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
	rm -f rename_problem
	sudo rm -f /etc/apparmor.d/rename_problem
	sudo rm -f /etc/apparmor.d/cap_problem

