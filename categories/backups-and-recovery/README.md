# Backups and recovery

Backups, restores, backup age, and DR validation.

## What belongs here

- `sql/` — SSMS-ready queries for backup coverage, backup age, restore duration estimates, and backup/restore script generation.
- `powershell/` — automation and local validation wrappers for the same checks.

## Common entry points

```powershell
./run.ps1 Get-BackupCoverage
```
