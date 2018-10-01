#!/bin/bash
echo "Following AppArmor logs..."
journalctl -f -a _TRANSPORT=audit | grep 'apparmor=' | aa-decode 2>/dev/null
$SHELL

