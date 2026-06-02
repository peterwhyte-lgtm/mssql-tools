# Blog — sqldba.blog post drafts

This folder contains draft blog posts for [sqldba.blog](https://sqldba.blog). Each post has its own folder containing `index.md` (the draft) and `images/` (placeholder for screenshots).

**Repo:** <https://github.com/peterwhyte-lgtm/dba-scripts>

---

## How this folder works

This is a **one-directional staging area**. The workflow is:

```
draft here  →  screenshots added  →  published on sqldba.blog  →  done
```

Once a post is published:
- The `blog/` folder is **not updated** — it was a draft, the canonical version is the live post.
- The matching SQL script gets a `-- Blog:` tag added to its header pointing to the live URL.
- That `-- Blog:` link in the script is the permanent connection between the repo and the post.

### Script header convention (after publishing)

```sql
-- Blog: https://sqldba.blog/sql-server-index-fragmentation/
```

Add this line to the script's comment header once the post is live. That's the only repo update required after publishing.

### Screenshot workflow

Each post draft marks where screenshots go with a comment like:
```
<!-- SCREENSHOT: [description of what to capture] -->
```
Make the screenshot in SSMS or the web UI, save it to the post's `images/` folder, and replace the comment with the `<img>` tag before publishing.

---

## Post index

Status key: `draft` = written, needs screenshots/review · `planned` = outline exists, not written yet

### dba-scripts category (script-backed posts)

| Folder | Title | Status | Category | Scripts |
|--------|-------|--------|----------|---------|
| [blocking-sessions/](blocking-sessions/index.md) | Finding and Diagnosing SQL Server Blocking | draft | Performance | Get-BlockingSummary, Get-BlockingSessions |
| [blocking-chains/](blocking-chains/index.md) | SQL Server Blocking Chain Analysis with Execution Plans | draft | Performance | Get-BlockingChains, Get-BlockingChainsWithPlan |
| [missing-indexes/](missing-indexes/index.md) | Finding Missing Indexes in SQL Server | draft | Performance | Get-MissingIndexes |
| [index-fragmentation/](index-fragmentation/index.md) | Diagnosing and Fixing SQL Server Index Fragmentation | draft | Performance | Get-IndexFragmentation, Generate-IndexMaintenanceScript |
| [statistics-health/](statistics-health/index.md) | Finding and Fixing Stale SQL Server Statistics | draft | Performance | Get-StatisticsHealth |
| [query-store/](query-store/index.md) | Finding Top Queries and Regressions with Query Store | draft | Performance | Get-QueryStoreTopQueries |
| [vlf-count/](vlf-count/index.md) | SQL Server VLF Count — The Hidden Log Performance Problem | draft | Performance | Get-VlfCount, Get-TransactionLogSizeAndUsage |
| [autogrowth-history/](autogrowth-history/index.md) | SQL Server Autogrowth History from the Default Trace | draft | Monitoring | Get-AutogrowthHistory |
| [database-sizes-free-space/](database-sizes-free-space/index.md) | SQL Server Database Sizes and Free Space | draft | Monitoring | Get-DatabaseSizesAndFreeSpace, Get-Databases |
| [backup-coverage/](backup-coverage/index.md) | How to Audit SQL Server Backup Coverage | draft | Backups | Get-BackupCoverage |
| [health-check-workflow/](health-check-workflow/index.md) | One-Command SQL Server Health Check | draft | Monitoring | Invoke-HealthCheckCollection, Review-HealthCheckOutput |
| [migration-risk-assessment/](migration-risk-assessment/index.md) | SQL Server Pre-Migration Risk Assessment | draft | Migration | Get-MigrationRiskAssessment, Get-DatabaseInventory |

### Security

| Folder | Title | Status | Scripts |
|--------|-------|--------|---------|
| [sysadmin-audit/](sysadmin-audit/index.md) | SQL Server sysadmin and Login Security Audit | draft | Get-SysadminMembers, Get-WeakLoginSettings, Get-ServerRoleMembers |
| [orphaned-users/](orphaned-users/index.md) | Finding SQL Server Orphaned Database Users | draft | Get-OrphanedUsers |

### Monitoring and health

| Folder | Title | Status | Category | Scripts |
|--------|-------|--------|----------|---------|
| [instance-configuration-audit/](instance-configuration-audit/index.md) | SQL Server Instance Configuration Audit | draft | Monitoring | Get-InstanceConfigurationScore |
| [dbcc-checkdb-history/](dbcc-checkdb-history/index.md) | DBCC CHECKDB History and Integrity Status | draft | Monitoring | Get-LastDbccCheckdb, Get-SuspectPages, Get-DatabaseIntegrityChecks |
| [sql-agent-job-failures/](sql-agent-job-failures/index.md) | SQL Server Agent Job Failure Summary | draft | Monitoring | Get-SqlAgentJobFailureSummary, Get-SqlAgentJobOverview, Get-JobScheduleSummary |
| [availability-group-health/](availability-group-health/index.md) | Availability Group Health and Latency Check | draft | HA/DR | Get-AvailabilityGroupReplicaState, Get-AvailabilityGroupLatency |
| [tempdb-contention/](tempdb-contention/index.md) | tempdb Contention and Usage Analysis | draft | Monitoring | Get-TempdbHotspots, Get-TempdbUsage |

### Performance — queries and indexes

| Folder | Title | Status | Scripts |
|--------|-------|--------|---------|
| [top-cpu-queries/](top-cpu-queries/index.md) | Finding the Top CPU and I/O Queries | draft | Get-TopCpuQueries, Get-TopIoQueries, Get-SlowQueriesFromCache |
| [deadlocks/](deadlocks/index.md) | Finding SQL Server Deadlocks from System Health | draft | Get-DeadlockSummary |
| [unused-indexes/](unused-indexes/index.md) | Finding Unused and Underused Indexes | draft | Get-UnusedIndexes, Get-IndexUsageStats |

### Wait statistics series (one post per wait type)

Each wait type is its own post in the `wait-statistics/` folder. The overview post (`wait-statistics/index.md`) introduces the series and links to each type.

| File | Wait Type | Status | Notes |
|------|-----------|--------|-------|
| [wait-statistics/index.md](wait-statistics/index.md) | Overview — script + how to use | draft | Existing solid draft |
| [wait-statistics/pageiolatch-sh.md](wait-statistics/pageiolatch-sh.md) | PAGEIOLATCH_SH | draft | Data file I/O waits |
| [wait-statistics/writelog.md](wait-statistics/writelog.md) | WRITELOG | draft | Log write waits |
| [wait-statistics/cxpacket.md](wait-statistics/cxpacket.md) | CXPACKET / CXCONSUMER | draft | Parallelism waits |
| [wait-statistics/async-network-io.md](wait-statistics/async-network-io.md) | ASYNC_NETWORK_IO | draft | Often false positive |
| [wait-statistics/lck-m-x.md](wait-statistics/lck-m-x.md) | LCK_M_X / LCK_M_S / LCK_M_U | draft | Lock waits |
| [wait-statistics/resource-semaphore.md](wait-statistics/resource-semaphore.md) | RESOURCE_SEMAPHORE | draft | Memory grant waits |
| [wait-statistics/sos-scheduler-yield.md](wait-statistics/sos-scheduler-yield.md) | SOS_SCHEDULER_YIELD | draft | CPU pressure |
| [wait-statistics/pageiolatch-ex.md](wait-statistics/pageiolatch-ex.md) | PAGEIOLATCH_EX | draft | Data page write I/O |
| [wait-statistics/io-completion.md](wait-statistics/io-completion.md) | IO_COMPLETION | draft | Non-data I/O waits |
| [wait-statistics/threadpool.md](wait-statistics/threadpool.md) | THREADPOOL | draft | Worker thread exhaustion |
| [wait-statistics/hadr-sync-commit.md](wait-statistics/hadr-sync-commit.md) | HADR_SYNC_COMMIT | draft | AG synchronous commit lag |
| [wait-statistics/backupio.md](wait-statistics/backupio.md) | BACKUPIO / BACKUPBUFFER | draft | Backup I/O waits |
| [wait-statistics/writelog-tempdb.md](wait-statistics/writelog-tempdb.md) | WRITELOG (tempdb variant) | draft | tempdb log pressure |

---

## Folder structure

```text
blog/
  README.md                          this file — content map and workflow
  _template/
    index.md                         copy this when starting a new post
    images/
  [post-slug]/
    index.md                         draft post
    images/
      [slug]-output.png              screenshots go here (added before publishing)
  wait-statistics/
    index.md                         series overview post
    pageiolatch-sh.md                one file per wait type
    writelog.md
    images/
      pageiolatch-sh-output.png      shared images folder for the series
```

## How to add a new post

1. Copy the `_template/` folder, rename to the post slug
2. Fill in frontmatter: title, slug, scripts, seo fields, `published_url` (leave blank), `screenshots_needed` list
3. Write the draft following the template sections
4. Note screenshot requirements in `screenshots_needed` and in the post body with `<!-- SCREENSHOT: ... -->` comments
5. Take screenshots in SSMS or the web UI, save to `images/`, replace comments with `<img>` tags
6. Fill in the SEO block
7. Publish to sqldba.blog under the `dba-scripts` category
8. Add `-- Blog: https://sqldba.blog/[slug]/` to the SQL script header in the repo
9. Add a row to the index table above with status `published`
10. **Do not update the `blog/` folder after this point** — the live post is now canonical

## Content guidelines

- Lead with the DBA problem, not the script
- Include the complete SQL — readers should be able to copy it into SSMS
- Show the `run.ps1` command for repo users
- `<img src="images/filename.png" alt="..." title="...">` for all images (not Markdown `![]()`)
- Alt text ≤125 chars, descriptive, includes the keyphrase naturally
- Image title ≤60 chars
- Meta description 150–160 chars
- Explain every non-obvious output column
- Give thresholds — what's normal, what's a concern, what's an emergency
- End with the GitHub link and related scripts
