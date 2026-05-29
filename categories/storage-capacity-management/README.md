# Storage and capacity management

Growth, disk space, log usage, and capacity reviews.

## What belongs here

- `sql/` — SSMS-ready queries for database sizes and free space, transaction log usage, file growth, and capacity planning.
- `powershell/` — automation and local validation wrappers for the same checks.

## Common entry points

```powershell
./run.ps1 Get-DatabaseSizesAndFreeSpace
./run.ps1 Get-TransactionLogSizeAndUsage
```
