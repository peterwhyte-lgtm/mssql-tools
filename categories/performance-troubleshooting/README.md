# Performance troubleshooting

Slow queries, waits, blocking, deadlocks, and I/O pain.

## What belongs here

- `sql/` — SSMS-ready queries for wait statistics, long-running queries, blocking and deadlock analysis, and I/O diagnostics.
- `powershell/` — automation and local validation wrappers for the same checks.

## Common entry points

```powershell
./run.ps1 Get-WaitStatistics
./run.ps1 Get-LongRunningQueries
```
