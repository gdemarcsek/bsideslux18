#include <stdio.h>
#include <pwd.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    uid_t current_uid = geteuid();
    struct passwd *ent = getpwuid(current_uid);
    if (ent == NULL) {
        printf("Failed to read user database\n");
        return EXIT_FAILURE;
    }

    printf("Home directory: %s\n", ent->pw_dir);

    return EXIT_SUCCESS;
}
