cmd_/vagrant/caveats/sys_module.ko := ld -r -m elf_x86_64 -z max-page-size=0x200000 -T ./scripts/module-common.lds --build-id  -o /vagrant/caveats/sys_module.ko /vagrant/caveats/sys_module.o /vagrant/caveats/sys_module.mod.o ;  true