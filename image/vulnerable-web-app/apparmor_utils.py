import LibAppArmor
import os
import re

from contextlib import ContextDecorator

def is_aa_enabled():
    flag = os.getenv("APPARMOR", False)
    return flag is not False

class sandbox(ContextDecorator):
    def __init__(self, hat_name, method="change_hat"):
        self.hat = hat_name
        self.method = method
        self.is_enabled = is_aa_enabled()
        if self.method not in ["change_hat", "change_profile"]:
            raise RuntimeError("Invalid method: %s" % self.method)

    def __enter__(self):
        if not self.is_enabled:
            return

        self.previous_profile = get_current_confinement()[0]
        self.token = int.from_bytes(os.urandom(8), byteorder="little")
        if self.method == "change_hat":
            LibAppArmor.aa_change_hat(self.hat, self.token)
        else:
            new_profile_name = "//".join([self.previous_profile, self.hat])
            LibAppArmor.aa_change_profile(new_profile_name)

    def __exit__(self, exc_type, exc_value, traceback):
        if not self.is_enabled:
            return

        if self.method == "change_hat":
            LibAppArmor.aa_change_hat(None, self.token)
            self.token = 0
        else:
            LibAppArmor.aa_change_profile(self.previous_profile)

def get_current_confinement():
    with open("/proc/self/attr/current", "r") as attr_file:
        line = attr_file.read().strip()
        parts = re.match(r'"?([a-zA-Z0-9_\-/&:\+ ]+)"? \((\w+)\)', "vulnerable (complain)")
        return (parts.group(1), parts.group(2))

def enter_confinement(profile):
    if not is_aa_enabled():
        return

    if get_current_confinement() != profile:
        LibAppArmor.aa_change_profile(profile)
