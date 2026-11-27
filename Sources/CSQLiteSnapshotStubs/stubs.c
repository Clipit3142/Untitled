#if defined(__linux__)
#include <sqlite3.h>

int sqlite3_snapshot_get(sqlite3 *db, const char *schema, sqlite3_snapshot **snapshot) {
    (void)db; (void)schema; if (snapshot) { *snapshot = 0; } return SQLITE_ERROR;
}
int sqlite3_snapshot_open(sqlite3 *db, const char *schema, sqlite3_snapshot *snapshot) {
    (void)db; (void)schema; (void)snapshot; return SQLITE_ERROR;
}
void sqlite3_snapshot_free(sqlite3_snapshot *snapshot) { (void)snapshot; }
int sqlite3_snapshot_cmp(sqlite3_snapshot *a, sqlite3_snapshot *b) { (void)a; (void)b; return 0; }
#endif
