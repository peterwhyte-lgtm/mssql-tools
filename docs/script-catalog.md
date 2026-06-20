# Script catalog

All SQL scripts and unique PowerShell scripts in the repo. Thin PS wrappers exist for every SQL script listed below — they live in `powershell/wrappers/<category>/` (same category name as the SQL script).

---

## SQL scripts

### Monitoring — `sql/monitoring/`

| Script | Purpose |
|--------|---------|
| Get-AgentAlertsAndOperators | SQL Agent alerts and operators with severity gap analysis. Surfaces instances with no alerts for severity 19-25 (critical errors go unnoticed without these). |
| Get-AutogrowthHistory | Reads autogrowth events from the SQL Server default trace |
| Get-CdcAndChangeTracking | CDC (Change Data Capture) and Change Tracking enabled databases with retention, cleanup settings, and latency indicators. Both features impact transaction log growth and can stall if cleanup jobs are absent or delayed. |
| Get-DatabaseFilesDetail | Per-file details for all user databases: path, size, max size, growth settings |
| Get-DatabaseGrowthEvents | Recent autogrowth events from the default trace for capacity planning |
| Get-DatabaseGrowthForecast | Projects when database files will exhaust their configured size limits, using historical file size changes recorded by the DatabaseGrowth temporal collector. Requires Generate-CollectorJob-DatabaseGrowth.sql to be installed and collecting. |
| Get-DatabaseGrowthRisk | Flag databases approaching their configured file size limits |
| Get-DatabaseHealth | Health and sizing posture of user databases |
| Get-DatabaseIntegrityChecks | Pre-check database readiness for integrity validation runs |
| Get-DatabaseSizesAndFreeSpace | Data and log file sizes with used and free space for all online user databases |
| Get-DatabaseSummary | One-row-per-database view of every database on the instance: state, recovery model, log reuse wait, file sizes, backup currency, and configuration flags. |
| Get-Databases | All databases with key properties and allocated file sizes |
| Get-DiskSpace | Free and used space per volume hosting SQL Server database files |
| Get-ExtendedEventsSessions | Active Extended Events sessions — name, state, targets, and estimated disk impact. Surfaces unexpected or high-overhead XE sessions on inherited servers. |
| Get-IndexFragmentation | Top fragmented indexes across all user databases, ranked by fragmentation % |
| Get-InstanceConfigurationScore | Scores the instance across ~20 key configuration checks — PASS/WARN/FAIL per item |
| Get-InstanceConfigurationSnapshot | All sp_configure settings for baseline review and change tracking |
| Get-JobScheduleSummary | Enabled SQL Agent jobs with schedules and next scheduled run time |
| Get-LastDbccCheckdb | When each user database last had a successful DBCC CHECKDB run |
| Get-LinkedServerAndJobInventory | Logins, linked servers, and SQL Agent jobs for pre-migration reviews |
| Get-MaxdopConfiguration | MAXDOP and cost threshold settings alongside current CPU topology |
| Get-MemoryConfigurationAndUsage | Configured memory limits alongside current SQL Server memory consumption |
| Get-OsAndHardwareInfo | OS version, hardware specs (CPU, RAM), and SQL Server uptime in one row |
| Get-OsConfigurationChecks | DMV-accessible OS and hardware configuration checks: Lock Pages in Memory, NUMA topology, scheduler affinity, and Instant File Initialization (SQL 2019+). Surfaces common misconfigurations invisible from inside SQL Server. |
| Get-PatchLevel | SQL Server version, Cumulative Update level, edition, and build |
| Get-QueryStoreStatus | Query Store enablement, fill ratio, capture mode, and health across all user databases. Surfaces databases where QS is off, full, or auto-switched to READ_ONLY. |
| Get-RecentErrorLogEntries | SQL Server error log entries from the last 24 hours, filtering routine noise |
| Get-ResourceGovernorConfig | Resource Governor configuration — enabled state, resource pools, workload groups, and classifier function. An active but misconfigured RG can silently throttle queries or starve the DBA's own sessions on an inherited server. |
| Get-ServiceBrokerHealth | Service Broker health across all user databases. Orphaned/disconnected conversation endpoints accumulate silently over months, eventually degrading SB infrastructure. |
| Get-ServicesInformation | SQL Server service state, startup type, and service account details |
| Get-SqlAgentJobFailureSummary | SQL Agent job failures from the last 7 days with timestamps and error messages |
| Get-SqlAgentJobOverview | All SQL Agent jobs with enabled state, owner, and last run outcome |
| Get-SqlServerCpuTopologyAndSchedulerDetails | CPU topology, NUMA layout, scheduler summary, and parallelism configuration |
| Get-SuspectPages | Pages recorded in msdb.dbo.suspect_pages — evidence of I/O or corruption errors |
| Get-TempDbConfiguration | TempDB file configuration — file count, sizing parity, autogrowth settings |
| Get-TempdbHotspots | Sessions consuming the most TempDB space for contention and spill triage |
| Get-TempdbUsage | TempDB file sizes, free space, and allocation breakdown per file |
| Get-TraceFlags | Active global and session trace flags with descriptions. Reveals undocumented tuning decisions and flags inherited from previous DBAs. |
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
| Get-DuplicateIndexes | Exact duplicate and overlapping (prefix) indexes across all user databases. Duplicates waste storage and double/triple write overhead for every DML operation. |
| Get-Heaps | Tables with no clustered index across all user databases — ranked by size and forwarded records |
| Get-ImplicitConversions | Scans the plan cache for implicit conversion warnings. These cause index range scans instead of seeks and generate unnecessary CPU. |
| Get-IndexDesignIssues | Tables with index design problems: excessive index count (write amplification), wide key columns, and tables where Missing Index DMV has > 3 recommendations. |
| Get-IndexFragmentationAcrossDatabases | Index fragmentation across all user databases for maintenance planning |
| Get-IndexUsageStats | How indexes across all user databases are being used — seeks, scans, lookups, updates |
| Get-LockEscalationStats | Tables with the most lock escalations since last restart |
| Get-LongRunningQueries | Active requests with elapsed and wait details — ordered by elapsed time descending |
| Get-MemoryGrantSpills | Top queries by memory grant spills to TempDB. Spills occur when SQL grants less memory than a sort or hash join operator needs, forcing intermediate results to disk. |
| Get-MissingIndexes | Missing index candidates from DMVs, ranked by impact score |
| Get-PlanCacheHealth | Plan cache composition by object type — highlights single-use plan pressure |
| Get-QueryStoreForcedPlans | Forced plans in Query Store with failure counts, plan age, forcing reason, and whether the forced plan is still the cheapest available option. |
| Get-QueryStoreRegressions | Queries that regressed in the last 24 hours vs their 7-day average CPU/duration. Uses Query Store time-bucketed runtime stats to detect "what changed today". |
| Get-QueryStoreTopQueries | Top queries from Query Store by CPU, duration, execution count, or plan regressions |
| Get-SlowQueriesFromCache | Top 20 queries by average elapsed time from the plan cache |
| Get-StatisticsHealth | Stale, low-sample, and never-updated statistics in the current database |
| Get-TableSizes | Largest tables across all online user databases by total size (data + index). Essential for getting to know a new instance. |
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
| Get-BackupChainIntegrity | LSN continuity analysis for each user database. Verifies the log backup chain from the most recent full backup to now is unbroken. |
| Get-BackupCoverage | Backup coverage per database with a status flag for quick health assessment |
| Get-BackupEncryptionStatus | TDE status and backup encryption coverage per database |
| Get-BackupRestoreCompletionTime | Active backup and restore operations with estimated completion time |
| Get-BackupRestoreDurationEstimate | Backup duration and throughput metrics from msdb for performance baseline |
| Get-DatabaseBackupHistory | Detailed backup history for all databases over the last 2 months |
| Get-LastDatabaseBackupTimes | Latest backup timestamp per type (Full, Differential, Log) per database |

### Security — `sql/security/`

| Script | Purpose |
|--------|---------|
| Get-AuditSpecifications | SQL Server Audit objects and specifications with compliance gap analysis. Surfaces missing critical action groups (FAILED_LOGIN_GROUP, privilege changes) and database-level audit specifications across all user databases. |
| Get-CertificatesAndKeys | Server-level certificates and asymmetric keys with expiry, usage detection, and lifecycle risk flags. |
| Get-DatabaseMailAndXpCmdShell | Whether Database Mail, xp_cmdshell, and CLR are enabled — security surface check |
| Get-DatabasePermissions | Explicit object- and schema-level GRANT/DENY permissions in the current database |
| Get-DatabaseRoleMembers | Database role memberships across all online user databases |
| Get-DdlTriggers | Server-level DDL triggers. These fire on schema changes (CREATE/ALTER/DROP) and are often unknown to incoming DBAs. |
| Get-FailedLoginSummary | Aggregated failed login analysis from the SQL Server error log and current lockout state per SQL login. Surfaces brute-force patterns and locked accounts. |
| Get-LinkedServerSecurity | Linked servers with their security context — how local logins map to remote credentials |
| Get-LoginPermissions | Explicit server-level permissions granted or denied to logins |
| Get-OrphanedUsers | Database users with no matching server login — common after migrations or login drops |
| Get-ProxyAndCredentials | SQL Agent proxies and server-level credentials with their identity and subsystems |
| Get-ServerRoleMembers | Members of every fixed and user-defined server role |
| Get-SysadminMembers | Members of the sysadmin fixed server role for audits and privilege review |
| Get-TdeStatus | Transparent Data Encryption (TDE) status across all databases. Includes encryption state, key algorithm, encryptor type, and tempdb encryption side-effect awareness. |
| Get-UserPermissionsAudit | All SQL Server logins by type and disabled state for permissions review |
| Get-WeakLoginSettings | SQL logins with weak security: policy off, expiration off, or sa enabled |

### High Availability — `sql/high-availability/`

Scripts are in `always-on/` or `replication/` subfolders.

| Script | Purpose |
|--------|---------|
| Get-AgFailoverReadiness | Per-AG, per-database failover readiness with quantified RPO and RTO estimates. Answers "would a failover succeed RIGHT NOW and what would it cost?" |
| Get-AvailabilityGroupLatency | AG replica synchronization timing, queue health, and replication rates |
| Get-AvailabilityGroupReplicaState | AG replica health, connection state, and synchronization status |
| Get-ReadableSecondaryUsage | AG replica connection modes and read-only routing configuration |
| Get-ReplicationStatus | Show transactional replication status for local publisher and distributor. |

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

### Maintenance — `sql/maintenance/`

| Script | Purpose |
|--------|---------|
| Generate-BackupJobs | SQL Agent DDL for three scheduled backup jobs: Full, Diff, T-Log |
| Generate-IndexMaintenanceJobs | SQL Agent DDL for index rebuild/reorganize and statistics update jobs |
| Generate-IndexMaintenanceScript | ALTER INDEX REBUILD/REORGANIZE statements for fragmented indexes in the current DB |
| Generate-MaintenanceJobs | SQL Agent DDL for housekeeping jobs: DBCC CHECKDB, history cleanup, error log cycle |
| Get-MaintenanceJobStatus | Last run outcome, duration, and next scheduled run for all maintenance jobs |

### Collectors — `sql/collectors/`

SQL Agent job generators and delta-query scripts for the DBAMonitor collection infrastructure.

| Script | Purpose |
|--------|---------|
| Generate-CollectorAlertJob | Generates DDL to create the DBA - Collector Alert SQL Agent job. The job queries [DBAMonitor].[collector].* tables, applies threshold checks, outputs findings, and RAISERRORs on any CRITICAL result. |
| Generate-CollectorJob-AgHealth | Generates DDL to create the DBA - Collect AG Health SQL Agent job. Creates the target database and collector.AgHealthCurrent temporal table if absent, then outputs T-SQL to install a recurring AG replica state MERGE job. |
| Generate-CollectorJob-Blocking | Generates DDL to create the DBA - Collect Blocking SQL Agent job. Creates the target database and collector.Blocking table if absent, then outputs T-SQL to install a recurring blocking-chain collection job. |
| Generate-CollectorJob-DatabaseGrowth | Generates DDL to create the DBA - Collect Database Growth SQL Agent job. Creates the target database and collector.DatabaseGrowthCurrent temporal table if absent, then outputs T-SQL to install a recurring database file size MERGE job. |
| Generate-CollectorJob-Deadlocks | Generates DDL to create the DBA - Collect Deadlocks SQL Agent job. Creates the target database and collector.Deadlocks table if absent, then outputs T-SQL to install a recurring deadlock collection job. |
| Generate-CollectorJob-ErrorLog | Generates DDL to create the DBA - Collect Error Log SQL Agent job. Creates the target database and collector.ErrorLog table if absent, then outputs T-SQL to install a recurring error log collection job. |
| Generate-CollectorJob-IndexFragmentation | Generates DDL to create the DBA - Collect Index Fragmentation SQL Agent job. Creates the target database and collector.IndexFragmentation table if absent, then outputs T-SQL to install a weekly index fragmentation snapshot job. |
| Generate-CollectorJob-Perfmon | Generates DDL to create the DBA - Collect Perfmon SQL Agent job. Creates the target database and collector.Perfmon table if absent, then outputs T-SQL to install a recurring performance counter snapshot job. |
| Generate-CollectorJob-QueryStore | Generates DDL to create the DBA - Collect Query Store SQL Agent job. Creates the target database and collector.QueryStore table if absent, then outputs T-SQL to install a recurring Query Store collection job. |
| Generate-CollectorJob-StorageIO | Generates DDL to create the DBA - Collect Storage IO SQL Agent job. Creates the target database and collector.StorageIO table if absent, then outputs T-SQL to install a recurring I/O stats snapshot job. |
| Generate-CollectorJob-Tempdb | Generates DDL to create the DBA - Collect TempDB SQL Agent job. Creates the target database and collector.Tempdb table if absent, then outputs T-SQL to install a recurring TempDB space snapshot job. |
| Generate-CollectorJob-VlfCount | Generates DDL to create the DBA - Collect VLF Count SQL Agent job. Creates the target database and collector.VlfCountCurrent temporal table if absent, then outputs T-SQL to install a daily VLF count MERGE job. |
| Generate-CollectorJob-WaitStats | Generates DDL to create the DBA - Collect Wait Stats SQL Agent job. Creates the target database and collector.WaitStats table if absent, then outputs T-SQL to install a recurring wait stats snapshot job. |
| Get-PerfmonDelta | Computes interval deltas for cumulative performance counters between the two most recent snapshots in [DBAMonitor].[collector].[Perfmon]. |
| Get-StorageIODelta | Computes interval I/O deltas between the two most recent snapshots in [DBAMonitor].[collector].[StorageIO]. Shows read/write counts, bytes transferred, and derived average latency for the interval. |
| Get-WaitStatsDelta | Computes interval wait deltas between the two most recent snapshots in [DBAMonitor].[collector].[WaitStats]. Shows delta_wait_ms, task count, average wait per task, and percentage of total interval wait. |

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

### Multi-server — `powershell/reporting/multi-server/`

PowerShell-only scripts (WinRM/RPC) and SQL scripts run via `Invoke-Sqlcmd`. All scripts accept `-Servers` (comma-separated) and a `-Parallel` switch.

| Script | Purpose |
|--------|---------|
| MultiServer-GetBlockingSessions | Active blocking sessions across instances |
| MultiServer-GetBackupStatus | Backup coverage — last full/diff/log per database |
| MultiServer-GetDatabaseSizes | Data and log file sizes per database per instance |
| MultiServer-GetDiskSpace | Disk free/used per volume across hosts (WinRM) |
| MultiServer-GetFirewallRules | List local Windows Firewall rules (WinRM) |
| MultiServer-GetRecentEventLogs | Pull recent Error/Warning events from event logs (RPC) |
| MultiServer-GetServiceStatus | Check service running/stopped state across hosts (RPC) |
| MultiServer-GetWaitStats | Top wait types per instance (filters background noise) |
| MultiServer-RestartService | Restart a named Windows service on multiple hosts (WinRM) |
| MultiServer-TestSqlPort | Test TCP port 1433 reachability — no auth needed |

### Migration — `powershell/migration/`

| Script | Purpose |
|--------|---------|
| Export-MigrationBaseline | Capture baseline metrics from source for post-migration comparison |
| Generate-AgentJobScript | Capture SQL Agent job DDL for recreation on the target server |
| Generate-LinkedServerScript | Capture linked server DDL — flags stored credentials requiring manual re-entry |
| Generate-LoginScript | Capture CREATE LOGIN DDL with SIDs and hashed passwords for migration |
| Generate-RestoreWithMoveScript | Generate RESTORE WITH MOVE template for migration to servers with different drive paths |
| Generate-UserMappingScript | Capture database user and role membership DDL for post-restore mapping |
| Get-DatabaseInventory | User databases for migration readiness — compat level, recovery model, size, features |
| Get-JobInventory | SQL Agent jobs with owner for migration dependency checks |
| Get-LoginInventory | Server logins by type and status for migration and access review |
| Get-MigrationRiskAssessment | Pre-migration risk scan — HIGH/MEDIUM/INFO findings for compat, features, and config |
| Invoke-MigrationExport | One-command export of logins, jobs, linked servers, and server config |
| Invoke-MigrationPreFlightCheck | Catch migration blockers before the window — connectivity, version, permission checks |
| Invoke-PreMigrationAssessment | Full pre-migration assessment report |

### Maintenance wrappers — `powershell/wrappers/maintenance/`

| Script | Purpose |
|--------|---------|
| Generate-BackupJobs | Generate SQL Agent job DDL for backup automation (full daily, log every 15 mins, cleanup) |
| Generate-IndexMaintenanceJobs | Generate SQL Agent job DDL for index maintenance and statistics update |
| Generate-MaintenanceJobs | Generate SQL Agent job DDL for housekeeping (DBCC CHECKDB, history cleanup, error log cycling) |
| Get-MaintenanceJobStatus | Report last run outcome and next scheduled run for all DBA maintenance jobs |

### Backup wrappers — `powershell/wrappers/backups/`

| Script | Purpose |
|--------|---------|
| Generate-DiffBackupScript | Generate differential backup DDL for review and execution in SSMS |
| Generate-FullBackupScript | Generate full backup DDL for review and execution in SSMS |
| Generate-RestoreScript | Generate restore DDL for DR testing and migration planning |
| Generate-TLogBackupScript | Generate transaction log backup DDL for review and execution in SSMS |
| Get-BackupAge | Report the age of the most recent backup per user database using msdb history |
| Get-BackupChainIntegrity | Validate backup chain integrity and missing log backups |
| Get-BackupCoverage | Show backup coverage across databases and retention gaps |
| Get-BackupEncryptionStatus | Report backup encryption status and algorithm use |
| Get-BackupRestoreCompletionTime | Monitor current backup and restore operation completion times |
| Get-BackupRestoreDurationEstimate | Estimate restore duration from backup file age and history |
| Get-DatabaseBackupHistory | Show historical backup activity across databases |

### Disk space & file tools — `powershell/disk-space/`

| Script | Purpose |
|--------|---------|
| Get-BackupAge | Report the age of the most recent backup for each user database using msdb history |
| Get-DiskSpaceSummary | Display available disk space for all local fixed drives on the current machine |
| Get-LargestFolders | Find the largest folders on a drive to identify disk space candidates for cleanup |
| Get-OldestBackupFolderFiles | Review the age of backup sets in a backup root to identify stale or missing backup media |
