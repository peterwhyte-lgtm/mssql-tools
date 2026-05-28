# powershell

Operational PowerShell scripts grouped by purpose.

## Subfolders

- helpers/ - local SQL execution and reusable automation helpers
- dba-lab-scripts/ - test-database creation and cleanup helpers
- backups-and-recovery/ - restore and backup workflow helpers
- configuration-and-environment/ - instance and environment checks
- performance-troubleshooting/ - blocking, waits, and fragmentation helpers
- storage-capacity-management/ - disk and file-space reporting helpers

## Quick validation example

Use the local SQL runner to test one of the repo scripts from PowerShell:

powershell -ExecutionPolicy Bypass -File .\powershell\helpers\Invoke-SqlFile.ps1 -ScriptPath .\sql\performance-troubleshooting\Get-LongRunningQueries.sql
