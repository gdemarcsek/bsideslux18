obj-m += sys_module.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
	gcc rename_problem.c -o rename_problem
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
	rm rename_problem

