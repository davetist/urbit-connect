#ifndef CONNECT_SQLITE_FAULT_HELPER_H
#define CONNECT_SQLITE_FAULT_HELPER_H
int connect_test_vfs_install(const char *database_path);
void connect_test_vfs_fail_after(int successful_writes);
void connect_test_vfs_reset(void);
int connect_test_vfs_tracked_count(void);
#endif
