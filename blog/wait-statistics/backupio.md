---
title: "BACKUPIO and BACKUPBUFFER Wait Types — SQL Server"
slug: sql-server-wait-statistics-backupio
series: wait-statistics
series_position: 13
published: 
published_url: 
status: draft
category: performance
tags: [waits, performance, backups, backupio, backupbuffer, backup-throughput]
seo_keyphrase: SQL Server BACKUPIO wait
seo_title: "SQL Server BACKUPIO and BACKUPBUFFER — Backup I/O Waits"
seo_description: BACKUPIO and BACKUPBUFFER appear when backup operations are I/O bound. Learn whether the destination, the network, or production I/O competition is the cause. (155 chars)
screenshots_needed:
  - Get-WaitStatistics output during a backup window showing BACKUPIO prominent in the results
  - msdb.dbo.backupset query showing backup durations trending longer over time
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# BACKUPIO and BACKUPBUFFER — Backup I/O Waits

**Part of the [SQL Server Wait Statistics series](index.md)**

`BACKUPIO` and `BACKUPBUFFER` appear when backup operations are waiting on I/O:

- **`BACKUPIO`** — the backup writer thread is waiting for data to be written to the backup destination (disk, network share, VDI device, tape). The backup can't proceed until the previous write completes.
- **`BACKUPBUFFER`** — the backup process is waiting for an internal buffer to become available — specifically the buffer that bridges the read (from source data) and write (to destination) sides of the backup pipeline. This usually appears when the destination write speed is significantly slower than the source read speed, causing the pipeline to back up.

In practice, `BACKUPIO` is the more meaningful wait. `BACKUPBUFFER` accompanies it when there's a severe destination bottleneck.

## Is this wait expected?

**Yes, during backup windows.** If your full backup runs at midnight, you'll see `BACKUPIO` elevated during that window. That's normal and expected — backup I/O *is* I/O, and the wait type is just recording it. The question is whether your backups are completing in a reasonable time.

**No, outside backup windows.** `BACKUPIO` appearing during production hours when no scheduled backup is running means something unexpected is taking a backup — check for ad-hoc backups, third-party backup agents, or backup jobs that ran late and overlapped with business hours.

**It's a problem when:**
- Backup duration has been growing over time and now extends into business hours
- Backups are timing out or failing
- Backup I/O is competing with production I/O and causing `PAGEIOLATCH_*` waits to spike during the backup window

## Root causes

**Slow backup destination** — the most common cause. Writing to a UNC share over a 1 Gbps network, to a tape library, or to a remote backup server creates a write bottleneck. The backup can only write as fast as the destination accepts data. For a 1 TB database, 1 Gbps is about 100 MB/s maximum — a backup takes at least 10 minutes just for network throughput, and real-world overhead makes it longer.

**Backup destination I/O contention** — a shared NAS or backup target that receives backups from multiple servers simultaneously. Your server competes with other servers for write bandwidth on the destination.

**Backup competing with production reads** — a full backup reads every page in every data file. On a server with a large working set, a backup scan evicts data pages from the buffer pool (recently read backup pages displace cached production pages), causing a spike in production `PAGEIOLATCH_SH` during the backup. This is I/O read competition, not `BACKUPIO` specifically — but it's the companion problem.

**No backup compression** — uncompressed backups are proportionally larger and take proportionally longer to write. Compression is available since SQL Server 2008 Standard and later and is almost always worth enabling.

**Single backup file on a single destination** — backup I/O is sequential to a single destination by default. Striping across multiple backup files to multiple disks or network paths multiplies effective throughput.

## How to diagnose it

**Check backup history and duration trends:**

```sql
SELECT TOP 50
    bs.database_name,
    bs.type                         AS backup_type,
    bs.backup_start_date,
    bs.backup_finish_date,
    DATEDIFF(minute, bs.backup_start_date, bs.backup_finish_date) AS duration_min,
    bs.backup_size      / 1024 / 1024 / 1024.0                   AS backup_size_gb,
    bs.compressed_backup_size / 1024 / 1024 / 1024.0             AS compressed_size_gb,
    CASE WHEN bs.compressed_backup_size > 0
         THEN CAST(100.0 - (100.0 * bs.compressed_backup_size / bs.backup_size) AS DECIMAL(5,1))
         ELSE NULL END                                            AS compression_pct,
    bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.type = 'D'   -- D = full, I = differential, L = log
ORDER BY bs.backup_start_date DESC;
```

Look for:
- `duration_min` trending upward over weeks/months — the backup is getting slower
- `compression_pct` near 0 or NULL — compression may not be enabled
- `physical_device_name` pointing to a UNC share — network may be the bottleneck

**Check if backups are active right now:**

```sql
SELECT
    r.session_id,
    r.command,
    r.percent_complete,
    r.estimated_completion_time / 1000 / 60.0  AS est_remaining_min,
    DB_NAME(r.database_id)                      AS database_name,
    r.wait_type,
    r.wait_time / 1000.0                        AS wait_sec
FROM sys.dm_exec_requests r
WHERE r.command LIKE 'BACKUP%'
   OR r.command LIKE 'RESTORE%';
```

**Check if backup is competing with production I/O:**

During a backup window, run the `sys.dm_io_virtual_file_stats` query from the `PAGEIOLATCH_SH` post. If you see `avg_read_ms` spike on data files during the backup, the backup scan is evicting production pages and competing for read I/O.

## What to do

**Enable backup compression** — the single highest-impact change you can make to improve backup performance:

```sql
-- For a single backup:
BACKUP DATABASE [YourDatabase]
TO DISK = 'D:\Backups\YourDatabase.bak'
WITH COMPRESSION, STATS = 10;

-- Set as default for all future backups:
EXEC sp_configure 'backup compression default', 1;
RECONFIGURE;
```

Compression typically reduces backup size by 60–80% on mixed data, cutting both write I/O and network transfer time proportionally.

**Stripe across multiple backup files** — write to multiple destinations simultaneously:

```sql
BACKUP DATABASE [YourDatabase]
TO DISK = '\\backup1\share\YourDatabase_1.bak',
   DISK = '\\backup2\share\YourDatabase_2.bak',
   DISK = 'D:\LocalBackup\YourDatabase_3.bak'
WITH COMPRESSION, STATS = 5;
```

This spreads I/O across destinations and can multiply effective throughput.

**Move backups to faster or dedicated backup storage** — a dedicated backup LUN or a local fast disk for landing backups, followed by a secondary copy job, is faster than writing directly to a shared NAS over the network.

**Tune BUFFERCOUNT and MAXTRANSFERSIZE** — for large databases, increasing these can improve backup throughput:

```sql
BACKUP DATABASE [YourDatabase]
TO DISK = 'D:\Backups\YourDatabase.bak'
WITH COMPRESSION, MAXTRANSFERSIZE = 4194304, BUFFERCOUNT = 50;
```

`MAXTRANSFERSIZE = 4194304` (4 MB) is common for large databases. Increasing `BUFFERCOUNT` uses more memory but can improve throughput on fast destinations. Test before applying to production — wrong values can cause backups to fail.

**Offload to an AG secondary** — if you have an Always On AG, run full and differential backups against a secondary replica instead of the primary:

```sql
-- In the AG configuration:
ALTER AVAILABILITY GROUP [YourAG]
MODIFY REPLICA ON 'SecondaryServer'
WITH (BACKUP_PRIORITY = 50);

-- On primary:
ALTER AVAILABILITY GROUP [YourAG]
MODIFY REPLICA ON 'PrimaryServer'
WITH (BACKUP_PRIORITY = 0);  -- prefer secondary for backups
```

This removes backup read I/O from the primary entirely.

**Schedule backups to avoid peak hours** — if backups are running into business hours, either start them earlier (allowing more time) or break one large full into a differential strategy (smaller daily jobs, larger weekly full).

## Related scripts

- [`Get-WaitStatistics`](index.md) — the overview script
- [`Get-BackupCoverage`](../backup-coverage/index.md) — audit backup coverage across all databases
- [`Get-BackupAge`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/backup-automation/Get-BackupAge.ps1) — find databases with stale or missing backups
- [`Get-DatabaseBackupHistory`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/backup-automation/Get-DatabaseBackupHistory.ps1) — full backup history with durations

## Get the scripts

- [`sql/performance/Get-WaitStatistics.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-WaitStatistics.sql)
- [`powershell/reporting/Get-WaitStatistics.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-WaitStatistics.ps1)

---

## SEO

**Focus keyphrase:** SQL Server BACKUPIO wait

**Meta description** (155 chars — target 150–160):  
BACKUPIO and BACKUPBUFFER appear when backup operations are I/O bound. Learn whether the destination, the network, or production I/O competition is the cause.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `backupio-wait-stats.png` | SQL Server wait statistics during backup window with BACKUPIO in top wait types | BACKUPIO during backup window |
| `backupio-duration-trend.png` | Backup history query showing backup duration in minutes trending upward over several weeks | Backup duration trending up |
