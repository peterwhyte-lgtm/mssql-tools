# ARCHIVED — do not use

The scripts in this folder are stale copies from an earlier repo layout. They are not maintained and may contain bugs that have been fixed in the canonical scripts.

**Use `sql/` and `powershell/` instead.**

```
sql/monitoring/     — health, memory, MAXDOP, jobs, AG, TempDB, DBCC
sql/performance/    — waits, blocking, long queries, indexes, I/O
sql/backups/        — coverage, history, restore generation
sql/security/       — roles, permissions, orphans, weak logins
sql/migration/      — database/login/job/linked-server inventory

powershell/inventory/        — storage, growth, disk, snapshots
powershell/reporting/        — performance wrappers, healthcheck collection + review
powershell/health-checks/    — DBCC, suspect pages, TempDB hotspots
powershell/backup-automation/ — backup/restore execution wrappers
powershell/security/         — security audit wrappers
powershell/migration/        — migration inventory wrappers
```

This folder will be removed in a future cleanup pass.
