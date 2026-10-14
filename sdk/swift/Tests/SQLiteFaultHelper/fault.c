/* Test-only SQLite VFS: one real xWrite returns SQLITE_FULL, then rollback works.
 * All other files and operations use the platform's original VFS unchanged. */
#include "SQLiteFaultHelper.h"
#include <sqlite3.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct tracked_file {
    sqlite3_file *file;
    const sqlite3_io_methods *original;
    sqlite3_io_methods methods;
    struct tracked_file *next;
} tracked_file;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static sqlite3_vfs *original_vfs;
static sqlite3_vfs test_vfs;
static tracked_file *files;
static char target[4096];
static int writes_left = -1;

static tracked_file *find_file(sqlite3_file *file) {
    for (tracked_file *entry = files; entry; entry = entry->next)
        if (entry->file == file) return entry;
    return NULL;
}
static int fault_write(sqlite3_file *file, const void *data, int count, sqlite3_int64 offset) {
    pthread_mutex_lock(&lock);
    tracked_file *entry = find_file(file);
    int (*write)(sqlite3_file *, const void *, int, sqlite3_int64) = entry->original->xWrite;
    int fail = writes_left == 0;
    if (writes_left >= 0) writes_left--;
    pthread_mutex_unlock(&lock);
    return fail ? SQLITE_FULL : write(file, data, count, offset);
}
static int fault_close(sqlite3_file *file) {
    pthread_mutex_lock(&lock);
    tracked_file **link = &files;
    while (*link && (*link)->file != file) link = &(*link)->next;
    tracked_file *entry = *link;
    *link = entry->next;
    file->pMethods = entry->original;
    pthread_mutex_unlock(&lock);
    int result = entry->original->xClose(file);
    free(entry);
    return result;
}
static int fault_open(sqlite3_vfs *vfs, const char *path, sqlite3_file *file, int flags, int *out_flags) {
    (void)vfs;
    int result = original_vfs->xOpen(original_vfs, path, file, flags, out_flags);
    if (result != SQLITE_OK || !path || !file->pMethods) return result;
    pthread_mutex_lock(&lock);
    const char *leaf = strrchr(path, '/'); leaf = leaf ? leaf + 1 : path;
    const char *wanted = strrchr(target, '/'); wanted = wanted ? wanted + 1 : target;
    /* UUID directory plus file name avoids /var vs /private/var canonicalization. */
    const char *directory = strstr(target, "connect-capacity-");
    size_t length = strlen(wanted);
    int matches = directory && strstr(path, directory) && length && strncmp(leaf, wanted, length) == 0 &&
        (leaf[length] == '\0' || strcmp(leaf + length, "-wal") == 0 || strcmp(leaf + length, "-journal") == 0);
    if (matches) {
        tracked_file *entry = calloc(1, sizeof(*entry));
        if (!entry) { pthread_mutex_unlock(&lock); file->pMethods->xClose(file); return SQLITE_NOMEM; }
        entry->file = file; entry->original = file->pMethods; entry->methods = *file->pMethods;
        entry->methods.xWrite = fault_write; entry->methods.xClose = fault_close;
        entry->next = files; files = entry; file->pMethods = &entry->methods;
    }
    pthread_mutex_unlock(&lock);
    return SQLITE_OK;
}
int connect_test_vfs_install(const char *database_path) {
    if (!database_path || strlen(database_path) >= sizeof(target)) return SQLITE_MISUSE;
    pthread_mutex_lock(&lock);
    original_vfs = sqlite3_vfs_find(NULL);
    test_vfs = *original_vfs;
    test_vfs.zName = "connect-fault-test"; test_vfs.pNext = NULL; test_vfs.xOpen = fault_open;
    strcpy(target, database_path); writes_left = -1;
    int result = sqlite3_vfs_register(&test_vfs, 1);
    pthread_mutex_unlock(&lock);
    return result;
}
void connect_test_vfs_fail_after(int successful_writes) {
    pthread_mutex_lock(&lock); writes_left = successful_writes; pthread_mutex_unlock(&lock);
}
void connect_test_vfs_reset(void) {
    pthread_mutex_lock(&lock); writes_left = -1; target[0] = '\0';
    if (original_vfs) sqlite3_vfs_register(original_vfs, 1);
    pthread_mutex_unlock(&lock);
}
int connect_test_vfs_tracked_count(void) {
    pthread_mutex_lock(&lock);
    int count = 0;
    for (tracked_file *entry = files; entry; entry = entry->next) count++;
    pthread_mutex_unlock(&lock);
    return count;
}
