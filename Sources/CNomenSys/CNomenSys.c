#if defined(__linux__)
#define _GNU_SOURCE
#endif
#include "CNomenSys.h"
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/stat.h>

#if defined(__APPLE__)
#include <sys/xattr.h>
#include <sys/mount.h>
#include <sys/param.h>
#else
#include <sys/xattr.h>
#include <sys/vfs.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

int nomen_rename_exclusive(const char *from, const char *to) {
#if defined(__APPLE__)
    return renamex_np(from, to, RENAME_EXCL);
#else
#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif
    return (int)syscall(SYS_renameat2, AT_FDCWD, from, AT_FDCWD, to, RENAME_NOREPLACE);
#endif
}

#if !defined(__APPLE__)
static int linux_name(const char *name, char *out, size_t size) {
    if (strncmp(name, "user.", 5) == 0 || strncmp(name, "security.", 9) == 0 ||
        strncmp(name, "trusted.", 8) == 0 || strncmp(name, "system.", 7) == 0) {
        if (strlen(name) + 1 > size) { errno = ENAMETOOLONG; return -1; }
        strcpy(out, name);
        return 0;
    }
    if (strlen(name) + 6 > size) { errno = ENAMETOOLONG; return -1; }
    snprintf(out, size, "user.%s", name);
    return 0;
}
#endif

ssize_t nomen_getxattr(const char *path, const char *name, void *value, size_t size) {
#if defined(__APPLE__)
    return getxattr(path, name, value, size, 0, XATTR_NOFOLLOW);
#else
    char mapped[512];
    if (linux_name(name, mapped, sizeof mapped) != 0) return -1;
    return lgetxattr(path, mapped, value, size);
#endif
}

int nomen_setxattr(const char *path, const char *name, const void *value, size_t size) {
#if defined(__APPLE__)
    return setxattr(path, name, value, size, 0, XATTR_NOFOLLOW);
#else
    char mapped[512];
    if (linux_name(name, mapped, sizeof mapped) != 0) return -1;
    return lsetxattr(path, mapped, value, size, 0);
#endif
}

int nomen_removexattr(const char *path, const char *name) {
#if defined(__APPLE__)
    return removexattr(path, name, XATTR_NOFOLLOW);
#else
    char mapped[512];
    if (linux_name(name, mapped, sizeof mapped) != 0) return -1;
    return lremovexattr(path, mapped);
#endif
}

ssize_t nomen_listxattr(const char *path, char *buffer, size_t size) {
#if defined(__APPLE__)
    return listxattr(path, buffer, size, XATTR_NOFOLLOW);
#else
    return llistxattr(path, buffer, size);
#endif
}

int nomen_volume_info(const char *path, char *type_name, size_t type_size, int *is_local) {
    struct statfs info;
    if (statfs(path, &info) != 0) return -1;
#if defined(__APPLE__)
    strncpy(type_name, info.f_fstypename, type_size - 1);
    type_name[type_size - 1] = 0;
    *is_local = (info.f_flags & MNT_LOCAL) ? 1 : 0;
#else
    const char *name = "unknown";
    int local = 1;
    switch ((unsigned long)info.f_type) {
        case 0xEF53: name = "ext4"; break;
        case 0x9123683E: name = "btrfs"; break;
        case 0x58465342: name = "xfs"; break;
        case 0x01021994: name = "tmpfs"; break;
        case 0x794C7630: name = "overlay"; break;
        case 0x65735546: name = "fuse"; local = 0; break;
        case 0x6969: name = "nfs"; local = 0; break;
        case 0xFF534D42: name = "cifs"; local = 0; break;
        case 0x517B: name = "smb"; local = 0; break;
        case 0x4d44: name = "msdos"; break;
        case 0x2011BAB0: name = "exfat"; break;
        case 0x5346544E: name = "ntfs"; break;
        default: name = "unknown"; break;
    }
    strncpy(type_name, name, type_size - 1);
    type_name[type_size - 1] = 0;
    *is_local = local;
#endif
    return 0;
}

int nomen_file_flags(const char *path, unsigned int *flags) {
    struct stat info;
    if (lstat(path, &info) != 0) return -1;
#if defined(__APPLE__)
    *flags = info.st_flags;
#else
    *flags = 0;
#endif
    return 0;
}

int nomen_flag_immutable(void) {
#if defined(__APPLE__)
    return UF_IMMUTABLE;
#else
    return 0x2;
#endif
}

int nomen_flag_dataless(void) {
#if defined(__APPLE__) && defined(SF_DATALESS)
    return SF_DATALESS;
#else
    return 0x40000000;
#endif
}

int nomen_flag_hidden(void) {
#if defined(__APPLE__)
    return UF_HIDDEN;
#else
    return 0x8000;
#endif
}
