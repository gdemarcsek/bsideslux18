import LibAppArmor
import os

from contextlib import ContextDecorator

class sandbox(ContextDecorator):
    def __init__(self, hat_name):
        self.hat = hat_name
        self.token = int.from_bytes(os.urandom(8), byteorder="little")

    def __enter__(self):
        LibAppArmor.aa_change_hat(self.hat, self.token)

    def __exit__(self, exc_type, exc_value, traceback):
        LibAppArmor.aa_change_hat(None, self.token)
        self.token = 0


def get_current_confinement():
    with open("/proc/self/attr/current", "r") as attr_file:
        return attr_file.read().strip()

def enter_confinement(profile):
    current = get_current_confinement()
    if current != profile:
        LibAppArmor.aa_change_profile(profile)
