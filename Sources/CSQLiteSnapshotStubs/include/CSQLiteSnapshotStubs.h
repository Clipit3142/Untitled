// Linux-only link stubs. GRDB is compiled with SQLITE_ENABLE_SNAPSHOT, but the
// SQLite shipped by Ubuntu omits the snapshot API. Nomen never opens WAL
// snapshots, so these stubs only satisfy the linker. They are excluded on Apple
// platforms, where the system SQLite provides the real functions.
#pragma once
