# DBA Script Catalog

This catalog mirrors the current production DBA script set in the repo.

## Performance Troubleshooting
- Get-BlockingSessions.sql
- Get-DatabaseIoUsage.sql
- Get-DeadlockSummary.sql
- Get-IndexFragmentationAcrossDatabases.sql
- Get-LongRunningQueries.sql
- Get-MissingIndexes.sql
- Get-TopCpuQueries.sql
- Get-WaitStatistics.sql
- Get-WorkerThreadsAndActiveSessions.sql
- Get-BlockingSessions.ps1
- Get-IndexFragmentation.ps1

## Backups & Recovery
- Generate-BackupScript.sql
- Generate-RestoreScript.sql
- Get-BackupCoverage.sql
- Get-BackupRestoreCompletionTime.sql
- Get-BackupRestoreDurationEstimate.sql
- Get-DatabaseBackupHistory.sql
- Get-LastDatabaseBackupTimes.sql
- Backup-SqlDatabases.ps1

## Storage & Capacity Management
- Get-DatabaseSizesAndFreeSpace.sql
- Get-DiskSpace.sql
- Get-TransactionLogSizeAndUsage.sql
- Get-DiskSpaceSummary.ps1
- Get-LargestFolders.ps1

## Maintenance & Reliability
- Get-DatabaseGrowthEvents.sql
- Get-DatabaseHealth.sql
- Get-IndexFragmentation.sql
- Get-TempdbUsage.sql

## Configuration & Environment
- Get-CpuTopologyAndCoreCounts.sql
- Get-InstanceConfigurationSnapshot.sql
- Get-LinkedServerAndJobInventory.sql
- Get-MaxdopConfiguration.sql
- Get-MemoryConfiguration.sql
- Get-MemoryConfigurationAndUsage.sql
- Get-MigrationChecklist.sql
- Get-ServicesInformation.sql
- Get-SqlAgentJobFailureSummary.sql
- Get-SqlAgentJobOverview.sql
- Get-VersionAndEdition.sql

## Security & Permissions
- Get-DatabaseMailAndXpCmdShell.sql
- Get-SysadminMembers.sql
- Get-UserPermissionsAudit.sql

## High Availability & Disaster Recovery
- Get-AvailabilityGroupLatency.sql
- Get-AvailabilityGroupReplicaState.sql

## DBA Lab Scripts
- New-MultipleDatabases.ps1
- New-TestDatabases.sql
- Remove-DatabasesByPrefix.ps1
- Run-CreateTestDatabases.ps1
