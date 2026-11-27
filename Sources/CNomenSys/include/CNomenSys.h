// Thin wrappers over the few system calls Nomen needs that differ between Darwin and
// Linux. All functions never follow symlinks and return -1 with errno set on failure.
#pragma once
#include <sys/types.h>
#include <stddef.h>

/// Renames `from` to `to`, failing with EEXIST instead of replacing an existing `to`.
/// Darwin: renamex_np(RENAME_EXCL). Linux: renameat2(RENAME_NOREPLACE).
int nomen_rename_exclusive(const char *from, const char *to);

/// Extended attributes, without following symlinks. On Linux, names are placed in the
/// "user." namespace so the same attribute names work on both systems.
ssize_t nomen_getxattr(const char *path, const char *name, void *value, size_t size);
int nomen_setxattr(const char *path, const char *name, const void *value, size_t size);
int nomen_removexattr(const char *path, const char *name);
ssize_t nomen_listxattr(const char *path, char *buffer, size_t size);

/// File system type name and whether the volume is local ("apfs", "hfs", "ext4" …).
int nomen_volume_info(const char *path, char *type_name, size_t type_size, int *is_local);

/// BSD file flags (UF_IMMUTABLE, SF_DATALESS …). Always 0 on Linux.
int nomen_file_flags(const char *path, unsigned int *flags);
int nomen_flag_immutable(void);
int nomen_flag_dataless(void);
int nomen_flag_hidden(void);
