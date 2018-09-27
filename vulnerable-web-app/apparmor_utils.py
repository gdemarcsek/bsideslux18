import LibAppArmor
import os
import re

from contextlib import ContextDecorator

class sandbox(ContextDecorator):
    def __init__(self, hat_name, method="change_profile"):
        self.hat = hat_name
        self.token = int.from_bytes(os.urandom(8), byteorder="little")
        self.previous_profile = get_current_confinement()[0]
        self.method = method

    def __enter__(self):
        if self.method == "change_hat":
            LibAppArmor.aa_change_hat(self.hat, self.token)
        elif self.method == "change_profile":
            LibAppArmor.aa_change_profile("//".join([self.previous_profile, self.hat]))
        else:
            raise RuntimeError("Unknown transition strategy")

    def __exit__(self, exc_type, exc_value, traceback):
        if self.method == "change_hat":
            LibAppArmor.aa_change_hat(None, self.token)
            self.token = 0
        elif self.method == "change_profile":
            LibAppArmor.aa_change_profile(self.previous_profile)
        else:
            raise RuntimeError("Unknown transition strategy")

def get_current_confinement():
    with open("/proc/self/attr/current", "r") as attr_file:
        line = attr_file.read().strip()
        parts = re.match(r'"?([a-zA-Z0-9_\-/&:\+ ]+)"? \((\w+)\)', "vulnerable (complain)")
        return (parts.group(1), parts.group(2))

def enter_confinement(profile):
    LibAppArmor.aa_change_profile(profile)
