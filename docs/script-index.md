# Script Index

All scripts with one-line descriptions, organised by layer and category.
Re-generate with `.\tools\Generate-ScriptIndex.ps1` after adding scripts.

## SQL Scripts

Run directly in SSMS / Azure Data Studio, or via `.\run.ps1 <ScriptName>`.

### backups  (7 scripts)

| Script | Purpose |
|--------|---------|
| `Generate-BackupScript` | Generate a full backup script for all user databases for SSMS review. |
| `Generate-RestoreScript` | Generate a restore script for all user databases for DR and migration scenarios. |
| `Get-BackupCoverage` | Review backup coverage per database with a status flag for quick health assessment. |
| `Get-BackupRestoreCompletionTime` | Monitor active backup and restore operations with estimated completion time. |
| `Get-BackupRestoreDurationEstimate` | Analyze backup duration and throughput metrics from msdb for performance baseline. |
| `Get-DatabaseBackupHistory` | Review detailed backup history for all databases over the last 2 months. |
| `Get-LastDatabaseBackupTimes` | Display the latest backup timestamp per type (Full, Differential, Log) per database. |

### migration  (7 scripts)

| Script | Purpose |
|--------|---------|
| `Generate-AgentJobScript` | Generate sp_add_job DDL to recreate all SQL Agent jobs on the target server. |
| `Generate-LoginScript` | Generate CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved. |
| `Generate-UserMappingScript` | Generate CREATE USER and role membership DDL for all user databases. |
| `Get-DatabaseInventory` | Inventory user databases for migration readiness — compatibility level, recovery model, state. |
| `Get-JobInventory` | Inventory SQL Agent jobs with owner for migration dependency checks. |
| `Get-LinkedServerInventory` | Inventory linked servers for migration and connectivity dependency mapping. |
| `Get-LoginInventory` | Inventory server logins by type and status for migration and access review. |

### monitoring  (29 scripts)

| Script | Purpose |
|--------|---------|
| `Get-AvailabilityGroupLatency` | Display AG replica synchronization timing, queue health, and replication rates. |
| `Get-AvailabilityGroupReplicaState` | Show AG replica health, connection state, and synchronization status for failover readiness. |
| `Get-DatabaseFilesDetail` | Show per-file details for all user databases: path, size, max size, growth settings. |
| `Get-DatabaseGrowthEvents` | Show recent autogrowth events from the default trace for capacity planning. |
| `Get-DatabaseGrowthRisk` | Flag databases approaching their configured file size limits. |
| `Get-DatabaseHealth` | Review the health and sizing posture of user databases. |
| `Get-DatabaseIntegrityChecks` | Pre-check database readiness and configuration for integrity validation runs. |
| `Get-DatabaseSizesAndFreeSpace` | Show data and log file sizes with free space for all online user databases. |
| `Get-DiskSpace` | Show free and used space per volume that hosts SQL Server database files. |
| `Get-IndexFragmentation` | Indexes with significant fragmentation (>= 10%, >= 1000 pages) with recommended action. |
| `Get-InstanceConfigurationSnapshot` | Capture all sp_configure settings for baseline review and change tracking. |
| `Get-JobScheduleSummary` | Show enabled SQL Agent jobs with their schedules and next scheduled run time. |
| `Get-LastDbccCheckdb` | Show when each user database last had a successful DBCC CHECKDB run. |
| `Get-LinkedServerAndJobInventory` | Inventory logins, linked servers, and SQL Agent jobs for pre-migration reviews. |
| `Get-MaxdopConfiguration` | Show MAXDOP and cost threshold settings alongside current CPU topology. |
| `Get-MemoryConfiguration` | Show configured memory limits alongside current OS-level memory availability. |
| `Get-MemoryConfigurationAndUsage` | Show configured memory limits alongside current SQL Server memory consumption. |
| `Get-MigrationChecklist` | Pre-migration validation checklist for backups, compatibility, jobs, and permissions. |
| `Get-OsAndHardwareInfo` | Show OS version, hardware specs (CPU, RAM), and SQL Server uptime in one row. |
| `Get-RecentErrorLogEntries` | Show SQL Server error log entries from the last 24 hours, filtering routine noise. |
| `Get-ServicesInformation` | Show SQL Server service state, startup type, and service account details. |
| `Get-SqlAgentJobFailureSummary` | Show SQL Agent job failures from the last 7 days with readable timestamps and error messages. |
| `Get-SqlAgentJobOverview` | Show all SQL Agent jobs with enabled state, owner, and last run outcome. |
| `Get-SqlServerCpuTopologyAndSchedulerDetails` | CPU topology, NUMA layout, scheduler summary, and parallelism configuration in one row. |
| `Get-SuspectPages` | Show any pages recorded in msdb.dbo.suspect_pages — evidence of I/O or corruption errors. |
| `Get-TempdbHotspots` | Identify sessions consuming the most TempDB space for contention and spill triage. |
| `Get-TempdbUsage` | Show TempDB file sizes, free space, and allocation breakdown per file. |
| `Get-TransactionLogSizeAndUsage` | Show transaction log size, used space, free space, and percent used per database. |
| `Get-VersionAndEdition` | Display core instance version, edition, cluster status, and patch level. |

### performance  (15 scripts)

| Script | Purpose |
|--------|---------|
| `Get-ActiveSessions` | Show all active user sessions with current wait type, blocking, elapsed time, and statement. |
| `Get-BackupRestoreProgress` | Show active backup/restore progress and estimated completion for long-running operations. |
| `Get-BlockingSessions` | Show sessions involved in blocking chains with wait type, timing, and current statement. |
| `Get-BlockingSummary` | Head blockers with context — who is blocking, how many sessions, and what they are running. |
| `Get-DatabaseIoUsage` | Database I/O totals with percentage share, MB read/written, and latency breakdown. |
| `Get-DeadlockSummary` | Show recent deadlock events from the system_health XEvent ring buffer. |
| `Get-IndexFragmentationAcrossDatabases` | Check index fragmentation details across all user databases for maintenance planning. |
| `Get-IndexUsageStats` | Show how indexes across all user databases are being used — seeks, scans, lookups, updates. |
| `Get-LongRunningQueries` | Active requests with elapsed and wait details — ordered by elapsed time descending. |
| `Get-MissingIndexes` | Missing index candidates from DMVs, ranked by impact score (seeks x cost x impact). |
| `Get-SlowQueriesFromCache` | Top 20 queries by average elapsed time from the plan cache — identifies habitually slow queries. |
| `Get-TopCpuQueries` | List top 20 CPU-consuming queries with execution counts and timing metrics. |
| `Get-TopIoQueries` | Top 20 queries by total logical reads since last restart — primary I/O pressure source. |
| `Get-WaitStatistics` | Top wait types since last SQL Server restart, filtered to actionable waits only. |
| `Get-WorkerThreadsAndActiveSessions` | Active user sessions with CPU, elapsed time, and current worker thread pool usage. |

### security  (8 scripts)

| Script | Purpose |
|--------|---------|
| `Get-DatabaseMailAndXpCmdShell` | Review whether Database Mail, xp_cmdshell, and CLR are enabled for security audits. |
| `Get-DatabaseRoleMembers` | List database role memberships across all online user databases. |
| `Get-LoginPermissions` | Show explicit server-level permissions granted or denied to logins. |
| `Get-OrphanedUsers` | Find database users with no matching server login — common after migrations or login drops. |
| `Get-ServerRoleMembers` | List all members of every fixed and user-defined server role. |
| `Get-SysadminMembers` | List members of the sysadmin fixed server role for audits and privilege review. |
| `Get-UserPermissionsAudit` | List all SQL Server logins by type and disabled state for permissions review. |
| `Get-WeakLoginSettings` | Identify SQL logins with weak security settings: policy off, expiration off, or sa enabled. |

## PowerShell Scripts

Wrappers and orchestrators. Run via `.\run.ps1 <ScriptName>` or directly.

### backup-automation  (11 scripts)

| Script | Synopsis |
|--------|---------|
| `Backup-AllDatabases` | Backs up every user database on the instance to a target folder. |
| `Backup-SqlDatabases` | Backs up all user databases to a target folder. |
| `Generate-BackupScript` | Generates a full backup T-SQL script for all user databases to review in SSMS. |
| `Generate-RestoreScript` | Generates restore scripts for all user databases. |
| `Get-BackupAge` | Reports the age of the latest backup for each user database. |
| `Get-BackupCoverage` | Runs the backup coverage review query for the current SQL Server instance. |
| `Get-BackupRestoreCompletionTime` | Monitors active backup and restore operations with estimated completion time. |
| `Get-BackupRestoreDurationEstimate` | Shows backup duration and throughput metrics from msdb for baseline planning. |
| `Get-DatabaseBackupHistory` | Shows detailed backup history for all databases over the last 2 months. |
| `Get-LastDatabaseBackupTimes` | Shows the latest full, diff, and log backup timestamp and age per database. |
| `Restore-AllDatabases` | Restores all user databases from backup files in a folder. |

### health-checks  (6 scripts)

| Script | Synopsis |
|--------|---------|
| `Get-DatabaseHealth` | Runs the database health review query for the current SQL Server instance. |
| `Get-DatabaseIntegrityChecks` | Pre-CHECKDB readiness: database states, recovery models, and last backup times. |
| `Get-LastDbccCheckdb` | Shows when each user database last had a successful DBCC CHECKDB. |
| `Get-SuspectPages` | Shows any pages in msdb.dbo.suspect_pages -- evidence of corruption or I/O errors. |
| `Get-TempdbHotspots` | Shows sessions consuming the most TempDB space right now. |
| `Get-TempdbUsage` | Runs the TempDB usage review query. |

### inventory  (28 scripts)

| Script | Synopsis |
|--------|---------|
| `Export-MigrationInventory` | Exports a simple migration inventory for jobs, linked servers, and logins. |
| `Get-AvailabilityGroupLatency` | Shows AG replica synchronisation timing, queue sizes, and replication rates. |
| `Get-AvailabilityGroupReplicaState` | Shows AG replica health, connection state, and synchronisation status. |
| `Get-DatabaseFilesDetail` | Returns per-file details for all user databases: path, size, max size, and growth settings. |
| `Get-DatabaseGrowthEvents` | Shows recent autogrowth events from the default trace for capacity planning. |
| `Get-DatabaseGrowthRisk` | Runs the database growth risk review query. |
| `Get-DatabaseSizesAndFreeSpace` | Runs the database sizes and free space review query. |
| `Get-DiskSpace` | Shows free and used space per volume that hosts SQL Server database files. |
| `Get-DiskSpaceSummary` | Shows a friendly local disk space summary for the current machine. |
| `Get-InstanceConfigurationSnapshot` | Runs the instance configuration snapshot review query. |
| `Get-InstanceHealthSummary` | — |
| `Get-InstanceSnapshot` | Captures a quick SQL Server instance configuration snapshot. |
| `Get-JobScheduleSummary` | Shows enabled SQL Agent jobs with their schedules and next scheduled run time. |
| `Get-LargestFolders` | Shows the largest folders on a drive, sorted by size. |
| `Get-LinkedServerAndJobInventory` | Inventories logins, linked servers, and SQL Agent jobs for pre-migration review. |
| `Get-MaxdopConfiguration` | Shows MAXDOP and cost threshold for parallelism alongside current CPU topology. |
| `Get-MemoryAndMaxdop` | Shows memory and MAXDOP related configuration for a server. |
| `Get-MemoryConfiguration` | Shows configured memory limits alongside current OS-level memory availability. |
| `Get-MemoryConfigurationAndUsage` | Runs the memory configuration and usage review query. |
| `Get-OldestBackupFolderFiles` | Lists the oldest file in each backup subfolder and flags folders older than a threshold. |
| `Get-OsAndHardwareInfo` | Returns OS version, hardware specs, and SQL Server uptime for the target instance. |
| `Get-RecentErrorLogEntries` | Shows SQL Server error log entries from the last 24 hours, with routine noise filtered out. |
| `Get-ServicesInformation` | Shows SQL Server service state, startup type, and service accounts. |
| `Get-SqlAgentJobFailureSummary` | Runs the SQL Agent failure summary review query. |
| `Get-SqlAgentJobOverview` | Runs the SQL Agent job overview review query. |
| `Get-SqlServerCpuTopologyAndSchedulerDetails` | CPU topology, NUMA, scheduler summary, and parallelism config in one row. |
| `Get-TransactionLogSizeAndUsage` | Runs the transaction log size and usage review query. |
| `Get-VersionAndEdition` | Shows SQL Server version, edition, patch level, and instance details. |

### migration  (8 scripts)

| Script | Synopsis |
|--------|---------|
| `Generate-AgentJobScript` | Generates sp_add_job DDL to recreate all SQL Agent jobs on the target server. |
| `Generate-LoginScript` | Generates CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved. |
| `Generate-UserMappingScript` | Generates CREATE USER and role membership DDL for all user databases. |
| `Get-DatabaseInventory` | Inventories user databases for migration readiness — compatibility, recovery model, state. |
| `Get-JobInventory` | Inventories SQL Agent jobs with owner for migration dependency checks. |
| `Get-LinkedServerInventory` | Inventories linked servers for migration and connectivity dependency mapping. |
| `Get-LoginInventory` | Inventories server logins by type and status for migration and access review. |
| `Get-MigrationChecklist` | Pre-migration validation checklist — backups, compatibility, jobs, permissions, linked servers. |

### reporting  (18 scripts)

| Script | Synopsis |
|--------|---------|
| `Get-ActiveSessions` | Shows all active user sessions with wait type, blocking chain, elapsed time, and current statement. |
| `Get-BackupRestoreProgress` | Shows active backup/restore progress and estimated completion times. |
| `Get-BlockingSessions` | Returns sessions involved in blocking chains with wait type, timing, and current statement. |
| `Get-BlockingSummary` | Shows a summary of current blocking chains — head blockers and all waiting sessions. |
| `Get-DatabaseIoUsage` | Shows I/O read and write activity per database file since the last SQL Server restart. |
| `Get-DeadlockSummary` | Shows recent deadlock events from the system_health XEvent ring buffer. |
| `Get-IndexFragmentation` | Reports index fragmentation for a database. |
| `Get-IndexFragmentationAcrossDatabases` | Checks index fragmentation across all user databases — run off-peak on busy instances. |
| `Get-IndexUsageStats` | Shows index usage statistics across all user databases — seeks, scans, lookups, and updates. |
| `Get-LongRunningQueries` | Runs the long-running query review script for the current SQL Server instance. |
| `Get-MissingIndexes` | Lists missing index candidates from DMVs, ranked by impact score. |
| `Get-SlowQueriesFromCache` | Top 20 queries by average elapsed time from the plan cache — habitually slow queries. |
| `Get-TopCpuQueries` | Lists the top 20 CPU-consuming queries since the last SQL Server restart. |
| `Get-TopIoQueries` | Lists the top 20 queries by total logical reads since the last SQL Server restart. |
| `Get-WaitStatistics` | Runs the top wait-statistics review script for the current SQL Server instance. |
| `Get-WorkerThreadsAndActiveSessions` | Active user sessions with CPU/elapsed time and current worker thread pool utilisation. |
| `Invoke-HealthCheckCollection` | Runs a full DBA health-check collection and saves each result as a named CSV in a timestamped folder. |
| `Review-HealthCheckOutput` | Reads a health-check output folder and surfaces flagged findings with severity ratings. |

### security  (8 scripts)

| Script | Synopsis |
|--------|---------|
| `Get-DatabaseMailAndXpCmdShell` | Shows whether Database Mail, xp_cmdshell, and CLR are enabled on the instance. |
| `Get-DatabaseRoleMembers` | Lists database role memberships across all online user databases. |
| `Get-LoginPermissions` | Shows explicit server-level permissions granted or denied directly to logins. |
| `Get-OrphanedUsers` | Finds database users with no matching server login across all user databases. |
| `Get-ServerRoleMembers` | Lists all members of every fixed and user-defined server role. |
| `Get-SysadminMembers` | Lists all members of the sysadmin fixed server role. |
| `Get-UserPermissionsAudit` | Lists all SQL Server logins by type and disabled state for a permissions review. |
| `Get-WeakLoginSettings` | Identifies SQL logins with weak security settings — policy off, expiration off, or sa enabled. |
