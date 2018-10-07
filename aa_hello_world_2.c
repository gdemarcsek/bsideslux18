#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <pwd.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    while (1) {
        uid_t current_uid = geteuid();
        struct passwd *ent = getpwuid(current_uid);
        if (ent == NULL) {
            perror("getpwuid");
        } else {
            printf("Home directory: %s\n", ent->pw_dir);
        }
        sleep(5);
    }
    return EXIT_SUCCESS;
}
