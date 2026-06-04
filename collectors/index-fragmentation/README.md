# Index Fragmentation Collector

Weekly point-in-time snapshot of index fragmentation across all user databases using SAMPLED mode. Tracks which indexes degrade fastest and provides recommended action (REBUILD / REORGANIZE / NONE).

## Why this exists

`Get-IndexFragmentation.sql` (in `sql/monitoring/`) gives you fragmentation on demand. This collector captures a weekly snapshot so you can answer: how fast does the Orders index fragment after a week of writes? Is fragmentation getting worse after reducing the maintenance window? Which databases have the most indexes consistently above 30%?

## Output

Weekly CSV at `output-files/collectors/index-fragmentation/`:

```text
<server>-<YYYYMMDD>.csv        one row per fragmented index per user database
<server>-collector.log
```

| Column | Description |
|--------|-------------|
| `collection_time` | Snapshot time |
| `server_name` | `@@SERVERNAME` |
| `database_name` | Database name |
| `schema_name` | Schema of the table |
| `table_name` | Table name |
| `index_name` | Index name |
| `index_type` | CLUSTERED or NONCLUSTERED |
| `partition_number` | Partition (1 for non-partitioned tables) |
| `page_count` | Number of leaf pages in the index |
| `avg_fragmentation_pct` | Average fragmentation percentage (SAMPLED) |
| `fragment_count` | Number of fragments |
| `avg_fragment_size_pages` | Average pages per fragment |
| `recommended_action` | REBUILD (≥30%) / REORGANIZE (10–29%) / NONE (<10%) |

Only indexes with 100+ pages are included — smaller indexes are too small to benefit from defragmentation.

## Write condition

Only writes rows for indexes with 100+ pages (filtered in SQL). A database with no large indexes produces no rows. Runs with no significant fragmentation may still produce rows (NONE action) — useful for trending.

## SAMPLED vs DETAILED vs LIMITED

| Mode | Speed | Accuracy | This collector uses |
|------|-------|----------|-------------------|
| LIMITED | Fastest | No fragmentation data | No |
| SAMPLED | Fast (~1% page sample) | Good — suitable for scheduling | **Yes** |
| DETAILED | Slow (full scan) | Exact | Not recommended for scheduled use |

## Collection frequency

| Environment | Recommended interval |
|-------------|---------------------|
| Production | Weekly, off-peak (Sunday 2am) |
| Dev/test | Monthly |

Run at a quiet time — SAMPLED mode still reads index pages. On a large instance with many big indexes, allow 30–60 minutes.

## Running manually

```powershell
.\collectors\index-fragmentation\Collect-IndexFragmentation.ps1
.\collectors\index-fragmentation\Collect-IndexFragmentation.ps1 -ServerInstance PROD01\SQL2019
```

## SQL Agent job setup

```sql
USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'DBA Collectors';
GO

EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Index Fragmentation Collector',
    @description     = N'Weekly SAMPLED index fragmentation snapshot across all user databases.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',
    @enabled         = 1;

EXEC msdb.dbo.sp_add_jobstep
    @job_name  = N'DBA - Index Fragmentation Collector',
    @step_name = N'Collect',
    @subsystem = N'CmdExec',
    @command   = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\dba-scripts\collectors\index-fragmentation\Collect-IndexFragmentation.ps1"',
    @on_success_action = 1,
    @on_fail_action    = 2;

-- Weekly on Sunday at 2:00am
EXEC msdb.dbo.sp_add_schedule
    @schedule_name     = N'Weekly Sunday 2am',
    @freq_type         = 8,       -- weekly
    @freq_interval     = 1,       -- Sunday
    @freq_recurrence_factor = 1,
    @active_start_time = 020000;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'DBA - Index Fragmentation Collector', @schedule_name = N'Weekly Sunday 2am';
EXEC msdb.dbo.sp_add_jobserver   @job_name = N'DBA - Index Fragmentation Collector';
GO
```

**Permissions required:** `VIEW DATABASE STATE` on each user database.
