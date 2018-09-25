#!/bin/bash
echo "Following AppArmor logs..."
journalctl -f -a _TRANSPORT=audit | grep apparmor | aa-decode | peco -b 200
$SHELL

