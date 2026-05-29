# DBA Runbook

## Quick triage commands

```powershell
# Full healthcheck — collect 19 scripts, review findings
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance . -Quiet
.\powershell\reporting\Review-HealthCheckOutput.ps1

# Live triage — what is happening right now
.\run.ps1 Get-ActiveSessions
.\run.ps1 Get-BlockingSummary
.\run.ps1 Get-LongRunningQueries

# Preflight
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance .
.\run.ps1 -List
```

---

## Daily checks

Run once per shift / once per day:

1. **Healthcheck collection** — `.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -Quiet`
2. **Review findings** — `.\powershell\reporting\Review-HealthCheckOutput.ps1`
3. **Check thresholds in the review output:**

| Severity | Rule | Action |
|----------|------|--------|
| CRITICAL | Suspect pages recorded | Run DBCC CHECKDB immediately on affected database |
| CRITICAL | SA login enabled | Disable or rename SA |
| CRITICAL | Database not ONLINE | Investigate `state_desc` — suspect, emergency, restoring |
| CRITICAL | No full backup ever | Take an immediate full backup; check backup job |
| WARNING  | Full backup > 25h old | Investigate backup job failures |
| WARNING  | Log backup > 4h (FULL recovery) | Check log backup schedule |
| WARNING  | DBCC CHECKDB > 7 days | Schedule CHECKDB run |
| WARNING  | Log > 80% used | Check log backup frequency |
| WARNING  | Max server memory unconfigured | Set `max server memory` (MB) appropriately |

---

## Weekly checks

```powershell
# Index fragmentation — per database (run against each user DB)
.\run.ps1 Get-IndexFragmentation -Database YourDatabase -OutputFormat Csv

# Cross-database fragmentation — run off-peak
.\run.ps1 Get-IndexFragmentationAcrossDatabases -OutputFormat Csv

# Missing indexes — review top results by impact_score
.\run.ps1 Get-MissingIndexes -OutputFormat Csv

# Slow queries from plan cache
.\run.ps1 Get-SlowQueriesFromCache -OutputFormat Csv

# Job schedule review
.\run.ps1 Get-JobScheduleSummary
```

Fragmentation thresholds (`recommended_action` column): `REBUILD` >= 30%, `REORGANIZE` 10–29%. Indexes < 1000 pages are excluded.

---

## Incident triage

### High CPU
```powershell
.\run.ps1 Get-WaitStatistics          # look for signal_wait_time_ms (CPU queue)
.\run.ps1 Get-TopCpuQueries -OutputFormat Csv
.\run.ps1 Get-LongRunningQueries
.\run.ps1 Get-SlowQueriesFromCache -OutputFormat Csv
```

### Blocking
```powershell
.\run.ps1 Get-BlockingSummary         # head blockers + affected session counts
.\run.ps1 Get-BlockingSessions        # full chain — who is blocked by whom
.\run.ps1 Get-ActiveSessions -OutputFormat Csv
.\run.ps1 Get-DeadlockSummary         # recent deadlocks from system_health ring buffer
```

### I/O pressure
```powershell
.\run.ps1 Get-WaitStatistics          # look for PAGEIOLATCH_SH / PAGEIOLATCH_EX
.\run.ps1 Get-DatabaseIoUsage         # read/write latency per database
.\run.ps1 Get-TopIoQueries -OutputFormat Csv
```
Latency concern thresholds: > 20ms read or > 10ms write on data files.

### TempDB pressure
```powershell
.\run.ps1 Get-TempdbUsage             # file sizes and free space per file
.\run.ps1 Get-TempdbHotspots          # sessions consuming TempDB right now
```

### Memory pressure
```powershell
.\run.ps1 Get-MemoryConfigurationAndUsage
.\run.ps1 Get-WaitStatistics          # look for RESOURCE_SEMAPHORE (memory grant waits)
```

### Backup / restore incident
```powershell
.\run.ps1 Get-BackupCoverage          # backup_status flag per database
.\run.ps1 Get-LastDatabaseBackupTimes
.\run.ps1 Get-SqlAgentJobFailureSummary
.\run.ps1 Get-BackupRestoreCompletionTime   # live progress on active backup/restore
.\run.ps1 Get-DatabaseBackupHistory -OutputFormat Csv
```

### Integrity concern
```powershell
.\run.ps1 Get-SuspectPages            # any entries = CRITICAL — run CHECKDB immediately
.\run.ps1 Get-LastDbccCheckdb         # last successful CHECKDB per database
.\run.ps1 Get-DatabaseIntegrityChecks # pre-CHECKDB readiness review
```

---

## Security review

```powershell
.\run.ps1 Get-SysadminMembers       -OutputFormat Csv
.\run.ps1 Get-ServerRoleMembers     -OutputFormat Csv
.\run.ps1 Get-DatabaseRoleMembers   -OutputFormat Csv
.\run.ps1 Get-OrphanedUsers         -OutputFormat Csv
.\run.ps1 Get-LoginPermissions      -OutputFormat Csv
.\run.ps1 Get-WeakLoginSettings     -OutputFormat Csv
.\run.ps1 Get-DatabaseMailAndXpCmdShell
```

---

## Pre-migration inventory

```powershell
.\run.ps1 Get-DatabaseInventory        -OutputFormat Csv
.\run.ps1 Get-LoginInventory           -OutputFormat Csv
.\run.ps1 Get-JobInventory             -OutputFormat Csv
.\run.ps1 Get-LinkedServerInventory    -OutputFormat Csv
.\run.ps1 Get-MigrationChecklist
.\run.ps1 Get-LinkedServerAndJobInventory -OutputFormat Csv
```

---

## Output files

| Location | What goes there |
|----------|----------------|
| `output-files\healthcheck\<server>-<timestamp>\` | Named CSVs from `Invoke-HealthCheckCollection.ps1` |
| `output-files\reviews\<category>\<script>-<timestamp>.csv` | Individual script runs via `Invoke-RepoSql.ps1` |

Clear all generated output: `.\helpers\maintenance\Clear-OutputFiles.ps1`
