# Get-BackupCoverage

Category: backups-and-recovery

Purpose:
Review recent backup coverage for all user databases and spot backup-age or DR readiness gaps.

How to run:
- .\run.ps1 Get-BackupCoverage

What to look for:
- Missing recent full, diff, or log backups.
- Databases with long backup age or recovery models that require tighter monitoring.

Requirements:
- Read-only query.
- Access to `msdb` backup history is required.
