# DBA Scripts Roadmap

This repo is being shaped as a practical production DBA toolkit for the blog and for day-to-day SQL Server operations.

## What the repo already covers

The current layout now includes practical coverage for:
- performance troubleshooting and wait/blocking analysis
- storage and capacity review
- backup and restore basics and readiness checks
- configuration, memory, MAXDOP, and SQL Agent reviews
- security and permission auditing
- HA/DR and lab-style database generation
- integrity/readiness checks before DBCC validation work

## What we should prioritize next

This pass has already covered the highest-value operational areas. The remaining next wave should focus on:

1. SQL Agent health and job failure analysis
   - completed: job history and failure visibility via Get-SqlAgentJobOverview.sql and Get-SqlAgentJobFailureSummary.sql
2. TempDB and I/O diagnostics
   - completed: usage and I/O views via Get-TempdbUsage.sql and Get-DatabaseIoUsage.sql
3. Deadlock and blocking deep dives
   - completed: blocking and wait summaries via Get-BlockingSessions.sql and Get-DeadlockSummary.sql
4. Backup/restore validation and DR rehearsal
   - completed: backup coverage and restore estimates via Get-BackupCoverage.sql, Get-BackupRestoreDurationEstimate.sql, Generate-BackupScript.sql, and Generate-RestoreScript.sql
5. Migration inventory and change prep
   - completed: inventory and checklist helpers via Get-LinkedServerAndJobInventory.sql and Get-MigrationChecklist.sql
6. Corruption and integrity checks
   - added: Get-DatabaseIntegrityChecks.sql as a pre-check and DBCC guidance script

## Work completed in this update

- Added a practical local SQL runner for quick validation: powershell/helpers/Invoke-SqlFile.ps1
- Fixed the test-database wrapper path and examples: powershell/dba-lab-scripts/Run-CreateTestDatabases.ps1
- Added integrity and readiness checks for DBCC validation planning: sql/maintenance-and-reliability/Get-DatabaseIntegrityChecks.sql
- Updated the catalog and quick-start docs to reflect the current script set

## Current focus

- Keep scripts easy to copy into SSMS and Azure Data Studio
- Preserve simple, production-friendly comments and notes
- Expand the most useful DBA workflows first, not just the most theoretical ones
- Keep category names aligned with real troubleshooting tasks and blog topics
