# Capacity and local durability

Protocol 1 retains these server bounds:

| Resource | Limit |
|---|---|
| Document data | 16 KiB encoded UTF-8 JSON |
| Request / batch | 256 KiB / 32 operations |
| Namespace | 1,000 live documents / 4 MiB live JSON |
| Entire Connect agent | 16 MiB live JSON |
| Owner registrations / sessions | 8 / 32 |
| Journal | 1,024 batches / 1 MiB |
| Snapshots | 4 concurrently, expiring after 60 seconds |
| Mutation receipts / tombstones | 30 days |
| Per-session document requests | 120 per minute |

One app can hold at most four pending authorizations/codes and two snapshots. The global authorization pool remains 32 and the snapshot pool remains four. These per-app bounds leave room for another app under single-app saturation; they do not promise availability against callers impersonating every public client ID. Completed/expired/revoked requests release their applicable slots.

Live JSON is measured independently from metadata, RSS and physical pier/event-log size. Deleting live data does not erase historical events, tombstones or backups. Back up and provision disk space for measured event-log growth.

The alpha local outbox accepts at most 1,000 pending mutations or 16 MiB of encoded mutation requests per account. A capacity error rejects the new enqueue, keeps previously queued requests intact and leaves the editor input visible. Capacity is released after acknowledgement; conflict replacement must work even at the limit and must roll back if replacement fails. A queued edit is not **Saved on your ship**.

SQLite uses full synchronous WAL transactions. Supported migrations keep exact queued request bytes, IDs and dependencies. Disk-full and interrupted writes must fail atomically. Confirmed cache data can be reconstructed from the ship; unsent drafts cannot. Do not delete drafts to meet a storage budget. See the final alpha evidence for measured database/WAL usage and implemented cache budgets; physical-device storage qualification is outside this Simulator milestone.

Each local database is limited to 128 MiB, with a 64-page automatic WAL checkpoint and a 1 MiB journal-size limit at checkpoint. A churn regression checks that the active WAL remains below 1.4 MiB. The private app directory retains at most 16 account databases (up to 2 GiB of database pages, plus bounded WAL/shared-memory files). Re-pairing an existing account is allowed at that limit. A seventeenth account is refused before consent; no account or unsent draft is evicted. Use **Review retained drafts** to read/export an older account, then deliberately remove it if space is needed. Existing over-limit legacy data is retained for recovery; new writes still obey the limits.

Todo stores a list and its tasks in one document. Once its encoded list reaches 16 KiB, keep the rejected task or edit visible and split future work into another list. The list schema is unchanged. A conflict compares the revision that was actually displayed; resolving it never silently overwrites a newer revision.
