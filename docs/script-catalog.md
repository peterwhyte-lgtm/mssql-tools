# Script catalog

All SQL scripts and unique PowerShell scripts in the repo. Thin PS wrappers exist for every SQL script listed below — they live in `powershell/wrappers/<category>/` (same category name as the SQL script).

---

## SQL scripts

### Monitoring — `sql/monitoring/`

| Script | Purpose |
|--------|---------|
| Get-AutogrowthHistory | Reads autogrowth events from the SQL Server default trace |
| Get-DatabaseFilesDetail | Per-file details for all user databases: path, size, max size, growth settings |
| Get-DatabaseGrowthEvents | Recent autogrowth events from the default trace for capacity planning |
| Get-DatabaseGrowthRisk | Flag databases approaching their configured file size limits |
| Get-DatabaseHealth | Health and sizing posture of user databases |
| Get-DatabaseIntegrityChecks | Pre-check database readiness for integrity validation runs |
| Get-DatabaseSizesAndFreeSpace | Data and log file sizes with used and free space for all online user databases |
| Get-Databases | All databases with key properties and allocated file sizes |
| Get-DiskSpace | Free and used space per volume hosting SQL Server database files |
| Get-IndexFragmentation | Top fragmented indexes across all user databases, ranked by fragmentation % |
| Get-InstanceConfigurationScore | Scores the instance across ~20 key configuration checks — PASS/WARN/FAIL per item |
| Get-InstanceConfigurationSnapshot | All sp_configure settings for baseline review and change tracking |
| Get-JobScheduleSummary | Enabled SQL Agent jobs with schedules and next scheduled run time |
| Get-LastDbccCheckdb | When each user database last had a successful DBCC CHECKDB run |
| Get-LinkedServerAndJobInventory | Logins, linked servers, and SQL Agent jobs for pre-migration reviews |
| Get-MaxdopConfiguration | MAXDOP and cost threshold settings alongside current CPU topology |
| Get-MemoryConfigurationAndUsage | Configured memory limits alongside current SQL Server memory consumption |
| Get-OsAndHardwareInfo | OS version, hardware specs (CPU, RAM), and SQL Server uptime in one row |
| Get-PatchLevel | SQL Server version, Cumulative Update level, edition, and build |
| Get-RecentErrorLogEntries | SQL Server error log entries from the last 24 hours, filtering routine noise |
| Get-ServicesInformation | SQL Server service state, startup type, and service account details |
| Get-SqlAgentJobFailureSummary | SQL Agent job failures from the last 7 days with timestamps and error messages |
| Get-SqlAgentJobOverview | All SQL Agent jobs with enabled state, owner, and last run outcome |
| Get-SqlServerCpuTopologyAndSchedulerDetails | CPU topology, NUMA layout, scheduler summary, and parallelism configuration |
| Get-SuspectPages | Pages recorded in msdb.dbo.suspect_pages — evidence of I/O or corruption errors |
| Get-TempDbConfiguration | TempDB file configuration — file count, sizing parity, autogrowth settings |
| Get-TempdbHotspots | Sessions consuming the most TempDB space for contention and spill triage |
| Get-TempdbUsage | TempDB file sizes, free space, and allocation breakdown per file |
| Get-TransactionLogSizeAndUsage | Transaction log size, used space, free space, and percent used per database |
| Get-VersionAndEdition | Core instance version, edition, cluster status, and patch level |
| Get-VlfCount | Virtual log file (VLF) count per database transaction log |

### Performance — `sql/performance/`

| Script | Purpose |
|--------|---------|
| Get-ActiveRequests | Point-in-time snapshot of all active requests — sessions with a current executing query |
| Get-ActiveRequestsWithPlan | Active requests with XML execution plan — use via Get-ActiveRequests.ps1 -IncludePlan |
| Get-ActiveSessions | All active user sessions with wait type, blocking, elapsed time, and statement |
| Get-BackupRestoreProgress | Active backup/restore progress and estimated completion for long-running operations |
| Get-BlockingChains | All active blocking chains via recursive CTE — full chain structure and wait details |
| Get-BlockingChainsWithPlan | Blocking chains with query plan — use via Get-BlockingChains.ps1 -IncludePlan |
| Get-BlockingSessions | Sessions involved in blocking chains with wait type, timing, and current statement |
| Get-BlockingSummary | Head blockers with context — who is blocking, how many sessions, and what they are running |
| Get-ContentionAnalysis | Unified contention summary across lock waits, latch waits, and TempDB allocation |
| Get-DatabaseIoUsage | Database I/O totals with percentage share, MB read/written, and latency breakdown |
| Get-DeadlockSummary | Recent deadlock events from the system_health XEvent ring buffer |
| Get-Heaps | Tables with no clustered index across all user databases — ranked by size and forwarded records |
| Get-IndexFragmentationAcrossDatabases | Index fragmentation across all user databases for maintenance planning |
| Get-IndexUsageStats | How indexes across all user databases are being used — seeks, scans, lookups, updates |
| Get-LockEscalationStats | Tables with the most lock escalations since last restart |
| Get-LongRunningQueries | Active requests with elapsed and wait details — ordered by elapsed time descending |
| Get-MissingIndexes | Missing index candidates from DMVs, ranked by impact score |
| Get-PlanCacheHealth | Plan cache composition by object type — highlights single-use plan pressure |
| Get-QueryStoreTopQueries | Top queries from Query Store by CPU, duration, execution count, or plan regressions |
| Get-SlowQueriesFromCache | Top 20 queries by average elapsed time from the plan cache |
| Get-StatisticsHealth | Stale, low-sample, and never-updated statistics in the current database |
| Get-TopCpuQueries | Top 20 CPU-consuming queries with execution counts and timing metrics |
| Get-TopIoQueries | Top 20 queries by total logical reads since last restart |
| Get-UnusedIndexes | Non-clustered indexes with zero reads but non-zero write overhead — drop candidates |
| Get-WaitStatistics | Top wait types since last SQL Server restart, filtered to actionable waits only |
| Get-WorkerThreadsAndActiveSessions | Active user sessions with CPU, elapsed time, and current worker thread pool usage |

### Backups — `sql/backups/`

| Script | Purpose |
|--------|---------|
| Generate-DiffBackupScript | Generate a DIFFERENTIAL backup script for all online user databases |
| Generate-FullBackupScript | Generate a FULL backup script for all online user databases |
| Generate-RestoreScript | Generate a RESTORE DATABASE script for all online user databases |
| Generate-TLogBackupScript | Generate a transaction log backup script for all online user databases |
| Get-BackupCoverage | Backup coverage per database with a status flag for quick health assessment |
| Get-BackupEncryptionStatus | TDE status and backup encryption coverage per database |
| Get-BackupRestoreCompletionTime | Active backup and restore operations with estimated completion time |
| Get-BackupRestoreDurationEstimate | Backup duration and throughput metrics from msdb for performance baseline |
| Get-DatabaseBackupHistory | Detailed backup history for all databases over the last 2 months |
| Get-LastDatabaseBackupTimes | Latest backup timestamp per type (Full, Differential, Log) per database |

### Security — `sql/security/`

| Script | Purpose |
|--------|---------|
| Get-DatabaseMailAndXpCmdShell | Whether Database Mail, xp_cmdshell, and CLR are enabled — security surface check |
| Get-DatabasePermissions | Explicit object- and schema-level GRANT/DENY permissions in the current database |
| Get-DatabaseRoleMembers | Database role memberships across all online user databases |
| Get-LinkedServerSecurity | Linked servers with their security context — how local logins map to remote credentials |
| Get-LoginPermissions | Explicit server-level permissions granted or denied to logins |
| Get-OrphanedUsers | Database users with no matching server login — common after migrations or login drops |
| Get-ProxyAndCredentials | SQL Agent proxies and server-level credentials with their identity and subsystems |
| Get-ServerRoleMembers | Members of every fixed and user-defined server role |
| Get-SysadminMembers | Members of the sysadmin fixed server role for audits and privilege review |
| Get-UserPermissionsAudit | All SQL Server logins by type and disabled state for permissions review |
| Get-WeakLoginSettings | SQL logins with weak security: policy off, expiration off, or sa enabled |

### Migration — `sql/migration/`

| Script | Purpose |
|--------|---------|
| Fix-OrphanedUsers | Generate ALTER USER statements to re-map orphaned database users to their server login |
| Generate-AgentJobScript | sp_add_job DDL to recreate all SQL Agent jobs on the target server |
| Generate-LinkedServerScript | sp_addlinkedserver + sp_addlinkedsrvlogin DDL for all linked servers |
| Generate-LoginScript | CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved |
| Generate-RestoreWithMoveScript | RESTORE DATABASE WITH MOVE scripts for migration to a target with different drive paths |
| Generate-UserMappingScript | CREATE USER and role membership DDL for all user databases |
| Get-CompatibilityLevelAudit | All databases with current compat level vs instance native level — upgrade planning |
| Get-DatabaseInventory | User databases for migration readiness — compat level, recovery model, size, features |
| Get-DeprecatedFeaturesInUse | Deprecated SQL Server features in active use since the last service restart |
| Get-EditionFeatureUsage | Enterprise-only features in active use on this instance |
| Get-JobInventory | SQL Agent jobs with owner for migration dependency checks |
| Get-LinkedServerInventory | Linked servers for migration and connectivity dependency mapping |
| Get-LoginInventory | Server logins by type and status for migration and access review |
| Get-MigrationLoginAudit | All server-level principals classified by migration risk and required action |
| Get-MigrationRiskAssessment | Pre-migration risk scan — HIGH/MEDIUM/INFO findings for compat, features, and config |
| Get-PostMigrationValidation | Summary of key server state for side-by-side comparison between source and target |
| Get-VersionUpgradeReadiness | Pre-upgrade readiness summary for SQL Server version upgrades |

### High Availability — `sql/high-availability/`

| Script | Purpose |
|--------|---------|
| Get-AvailabilityGroupLatency | AG replica synchronization timing, queue health, and replication rates |
| Get-AvailabilityGroupReplicaState | AG replica health, connection state, and synchronization status |
| Get-ReadableSecondaryUsage | AG replica connection modes and read-only routing configuration |

### Maintenance — `sql/maintenance/`

| Script | Purpose |
|--------|---------|
| Generate-BackupJobs | SQL Agent DDL for three scheduled backup jobs: Full, Diff, T-Log |
| Generate-IndexMaintenanceJobs | SQL Agent DDL for index rebuild/reorganize and statistics update jobs |
| Generate-IndexMaintenanceScript | ALTER INDEX REBUILD/REORGANIZE statements for fragmented indexes in the current DB |
| Generate-MaintenanceJobs | SQL Agent DDL for housekeeping jobs: DBCC CHECKDB, history cleanup, error log cycle |
| Get-MaintenanceJobStatus | Last run outcome, duration, and next scheduled run for all maintenance jobs |

---

## PowerShell scripts

Unique scripts with real logic — orchestrators, DDL generators, automation, and OS tools. Thin wrappers (monitoring, performance, security, backups, high-availability categories) follow the same naming convention as the SQL scripts they wrap.

### Healthcheck & reporting — `powershell/reporting/`

| Script | Purpose |
|--------|---------|
| Get-ActiveRequests | Triage runaway queries, blocking chains, and TempDB consumers — supports -IncludePlan |
| Get-BlockingChains | Deep-dive blocking diagnostic with full chain structure — supports -IncludePlan |
| Invoke-HealthCheckCollection | Collect all key health-check data in one pass — saves named CSVs for offline review |
| Review-HealthCheckOutput | Turn raw CSV collection output into an actionable CRITICAL/WARNING/INFO findings list |
| Invoke-AssessmentReport | Generate a client-ready instance assessment report in markdown |
| Invoke-MultiServerHealthCheck | Estate-wide health check — flags which servers need attention across a server list |

### Migration — `powershell/migration/`

| Script | Purpose |
|--------|---------|
| Generate-LoginScript | Capture CREATE LOGIN DDL with SIDs and hashed passwords for migration |
| Generate-AgentJobScript | Capture SQL Agent job DDL for recreation on the target server |
| Generate-UserMappingScript | Capture database user and role membership DDL for post-restore mapping |
| Generate-LinkedServerScript | Capture linked server DDL — flags stored credentials requiring manual re-entry |
| Generate-RestoreWithMoveScript | Generate RESTORE WITH MOVE template for migration to servers with different drive paths |
| Invoke-MigrationExport | One-command export of logins, jobs, linked servers, and server config |
| Invoke-MigrationPreFlightCheck | Catch migration blockers before the window — connectivity, version, permission checks |
| Invoke-PreMigrationAssessment | Full pre-migration assessment report |
| Export-MigrationBaseline | Capture baseline metrics from source for post-migration comparison |

### Maintenance — `powershell/maintenance/`

| Script | Purpose |
|--------|---------|
| Generate-BackupJobs | Generate and write backup job DDL to a .sql file for review before deployment |
| Generate-IndexMaintenanceJobs | Generate and write index maintenance job DDL to a .sql file |
| Generate-MaintenanceJobs | Generate and write housekeeping job DDL to a .sql file |
| Invoke-MaintenanceDeployment | Deploy the maintenance framework across a fleet of servers |

### Backup automation — `powershell/backup-automation/`

| Script | Purpose |
|--------|---------|
| Backup-AllDatabases | Back up all user databases using SMO — supports compression and copy-only |
| Backup-SqlDatabases | Back up all user databases using SMO with configurable backup type |
| Restore-AllDatabases | Restore all user databases from a backup folder using SMO (HIGH IMPACT — use with care) |
| Generate-FullBackupScript | Generate full backup DDL for review and execution in SSMS |
| Generate-DiffBackupScript | Generate differential backup DDL for review and execution in SSMS |
| Generate-TLogBackupScript | Generate T-Log backup DDL for review and execution in SSMS |
| Generate-RestoreScript | Generate restore DDL for DR testing and migration planning |
| Get-BackupAge | Report age of the most recent backup per user database using msdb history |

### Inventory & OS — `powershell/inventory/`

| Script | Purpose |
|--------|---------|
| Get-DiskSpaceSummary | Available disk space for all local fixed drives on the current machine |
| Get-InstanceHealthSummary | Server name, edition, version, and key configuration settings at a glance |
| Get-InstanceSnapshot | SQL Server instance configuration for baseline, migration, or incident prep |
| Get-LargestFolders | Largest folders on a drive — identify disk space cleanup candidates |
| Get-OldestBackupFolderFiles | Age of backup sets in a backup root — flag stale or missing backup media |
