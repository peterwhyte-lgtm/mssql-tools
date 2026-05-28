# DBA Runbook

## Daily checks

1. Run Get-DiskSpaceSummary.ps1 to confirm storage headroom.
2. Run Get-BlockingSessions.ps1 to review current waits and blockers.
3. Run Get-IndexFragmentation.ps1 for maintenance prioritization.
4. Review Get-DatabaseHealth.sql in SSMS for database state and growth risks.

## Backup/restore notes

- Ensure backup paths are writable by the SQL Server service account.
- Test restores in non-production before using in production.
- Keep backup retention aligned with your SLA.
