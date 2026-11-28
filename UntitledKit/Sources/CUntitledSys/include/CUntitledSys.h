// Thin wrappers over the few system calls Untitled needs that differ between Darwin and
// Linux. All functions never follow symlinks and return -1 with errno set on failure.
#pragma once
#include <sys/types.h>
#include <stddef.h>

/// Renames `from` to `to`, failing with EEXIST instead of replacing an existing `to`.
/// Darwin: renamex_np(RENAME_EXCL). Linux: renameat2(RENAME_NOREPLACE).
int untitled_rename_exclusive(const char *from, const char *to);

/// Extended attributes, without following symlinks. On Linux, names are placed in the
/// "user." namespace so the same attribute names work on both systems.
ssize_t untitled_getxattr(const char *path, const char *name, void *value, size_t size);
int untitled_setxattr(const char *path, const char *name, const void *value, size_t size);
int untitled_removexattr(const char *path, const char *name);
ssize_t untitled_listxattr(const char *path, char *buffer, size_t size);

/// File system type name and whether the volume is local ("apfs", "hfs", "ext4" …).
int untitled_volume_info(const char *path, char *type_name, size_t type_size, int *is_local);

/// Birth (creation) time of a path without following symlinks. Returns -1 when the file
/// system does not record it; then `seconds` and `nanoseconds` are 0.
int untitled_birth_time(const char *path, long long *seconds, long *nanoseconds);

/// Device, inode and birth time of an open descriptor.
int untitled_fd_identity(int fd, unsigned long long *device, unsigned long long *inode, long long *birth_seconds, long *birth_nanoseconds);

/// BSD file flags (UF_IMMUTABLE, SF_DATALESS …). Always 0 on Linux.
int untitled_file_flags(const char *path, unsigned int *flags);
int untitled_flag_immutable(void);
int untitled_flag_dataless(void);
int untitled_flag_hidden(void);
