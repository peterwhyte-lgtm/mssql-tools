# Maintenance and reliability

Integrity, fragmentation, TempDB, and maintenance routines.

## What belongs here

- `sql/` — SSMS-ready queries for integrity checks, index/statistics maintenance, TempDB usage, and reliability routines.
- `powershell/` — automation and local validation wrappers for the same checks.

## Common entry points

```powershell
./run.ps1 Get-DatabaseHealth
./run.ps1 Get-TempdbUsage
```
