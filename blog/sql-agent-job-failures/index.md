---
title: "Script: SQL Server Agent Job Failure Summary"
slug: sql-server-agent-job-failures
published: 
published_url: 
status: draft
category: monitoring
tags: [sql-agent, jobs, monitoring, failures, automation]
scripts:
  - sql/monitoring/Get-SqlAgentJobFailureSummary.sql
  - sql/monitoring/Get-SqlAgentJobOverview.sql
  - sql/monitoring/Get-JobScheduleSummary.sql
  - powershell/inventory/Get-SqlAgentJobFailureSummary.ps1
  - powershell/inventory/Get-SqlAgentJobOverview.ps1
  - powershell/inventory/Get-JobScheduleSummary.ps1
seo_keyphrase: SQL Server Agent job failures
seo_title: "SQL Server Agent Job Failure Summary — What's Been Failing This Week"
seo_description: Find SQL Server Agent job failures from the last 7 days with job name, step, error message, and run time. Essential for catching silent maintenance failures. (155 chars)
screenshots_needed:
  - Get-SqlAgentJobFailureSummary output showing job_name, step_name, run_datetime, run_duration, and message columns with several failures visible
  - Get-SqlAgentJobOverview output showing enabled jobs with last_run_status and next_run columns
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server Agent Job Failure Summary

SQL Server Agent jobs are the backbone of database automation — backups, DBCC CHECKDB, index maintenance, statistics updates, log shipping, ETL processes. When a job fails, SQL Server logs it in `msdb` and optionally sends an email alert. The email goes to a mailbox that might be monitored, or might not. The job history sits in `msdb` waiting to be queried.

In practice, jobs fail silently all the time. A backup job fails because the destination ran out of space. An index maintenance job fails because it ran out of time. A DBCC CHECKDB job hasn't run in three weeks because the schedule was accidentally set to inactive. Nobody notices until something goes wrong downstream.

These scripts surface the last 7 days of job failures in a readable format, and give a snapshot of all enabled jobs with their current status.

## The scripts

### Get-SqlAgentJobFailureSummary.sql — failed steps in the last 7 days

```sql
SELECT
    j.name                                                                      AS job_name,
    h.step_id,
    h.step_name,
    msdb.dbo.agent_datetime(h.run_date, h.run_time)                            AS run_datetime,
    CAST(h.run_duration / 10000 AS VARCHAR(4)) + 'h '
    + RIGHT('0' + CAST(h.run_duration / 100 % 100 AS VARCHAR(2)), 2) + 'm '
    + RIGHT('0' + CAST(h.run_duration % 100 AS VARCHAR(2)), 2) + 's'          AS run_duration,
    h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs        AS j ON h.job_id = j.job_id
WHERE h.run_status = 0
  AND h.run_date >= CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, -7, GETDATE()), 112))
ORDER BY h.instance_id DESC;
```

### Get-SqlAgentJobOverview.sql — all jobs with their current status

Returns all SQL Agent jobs with enabled/disabled state, last run status, last run time, next scheduled run, and job category.

### Get-JobScheduleSummary.sql — scheduled jobs and their next run times

Returns enabled jobs with their schedule details — useful for verifying that maintenance jobs are scheduled and when they'll next run.

## How to run it from the repo

```powershell
# Job failures in the last 7 days
.\run.ps1 Get-SqlAgentJobFailureSummary

# All jobs with current status
.\run.ps1 Get-SqlAgentJobOverview

# Job schedules and next run times
.\run.ps1 Get-JobScheduleSummary

# Save to CSV for weekly review
.\run.ps1 Get-SqlAgentJobFailureSummary -OutputFormat Csv
```

## Reading the output — Get-SqlAgentJobFailureSummary

| Column | What it means |
|--------|---------------|
| `job_name` | Name of the SQL Agent job. |
| `step_id` | Which step within the job failed. Step 0 is the overall job outcome (failure is recorded here when any step fails and the job has no retry logic). |
| `step_name` | The name of the failing step. |
| `run_datetime` | When the step ran (converted from SQL Agent's YYYYMMDD integer format to a readable datetime). |
| `run_duration` | How long the step ran before failing, formatted as `NNh NNm NNs`. A job that failed after 2 hours of index maintenance is different from one that failed immediately. |
| `message` | The error message from the failing step. This is the key diagnostic column — it usually tells you exactly what failed and why. |

## Reading the output — Get-SqlAgentJobOverview

| Column | What it means |
|--------|---------------|
| `job_name` | Job name. |
| `enabled` | 0 = disabled, 1 = enabled. Disabled maintenance jobs are a common reason for missed CHECKDB, missed backups, etc. |
| `last_run_status` | 0 = failed, 1 = succeeded, 2 = retry, 3 = cancelled, 5 = unknown. |
| `last_run_date` | When the job last ran. A job with no recent run date on an enabled schedule means it's not running. |
| `next_run_date` | When the job is next scheduled to run. |

## Common failure patterns

**Backup failures** — destination disk full, network share unreachable, credentials expired on a backup account. The `message` column usually says "Operating system error 5: Access is denied" or "There is not enough space on the disk."

**Index maintenance timeout** — Ola Hallengren's maintenance solution and similar tools support a `MaxDuration` parameter. If the job is set to stop after 2 hours and index maintenance takes 4 hours, steps beyond the time limit fail with a timeout message.

**DBCC CHECKDB failures** — less common, but can happen due to I/O errors during the integrity check itself, or due to timeouts. A CHECKDB failure message that includes page numbers is a corruption finding.

**Statistics update failures** — usually caused by lock timeouts on tables that are under active write load when the maintenance job runs.

**Log shipping failures** — if log shipping jobs fail, the secondary starts falling behind. The message usually indicates a network issue or a full destination.

**Linked server issues** — ETL jobs that query via linked server fail when the linked server target is unavailable, credentials expire, or the remote server is under maintenance.

## What to do

For each failing job, read the `message` column carefully:

- **"Access is denied" or network errors** — check service account permissions to the destination, network connectivity, and whether the destination share is online.
- **"Not enough space"** — check disk space on the destination. Use `Get-DiskSpace` to check server drives.
- **"Timeout" or "Lock" errors** — the job is competing with production workload. Review the maintenance schedule — run at off-peak hours, or review the `MaxDuration` setting.
- **"Corruption" or page errors** — treat as critical. Run `Get-LastDbccCheckdb` and `Get-SuspectPages` immediately.

For disabled jobs that should be enabled:

```sql
-- Enable a specific job
EXEC msdb.dbo.sp_update_job
    @job_name = N'Your Job Name',
    @enabled = 1;
```

For verifying that a fixed job now runs successfully:

```sql
-- Manually start a job to test
EXEC msdb.dbo.sp_start_job @job_name = N'Your Job Name';

-- Check the result a few minutes later
.\run.ps1 Get-SqlAgentJobFailureSummary
```

## Making job failure monitoring routine

A daily or weekly review of job failures is a basic DBA practice that prevents small failures from becoming large incidents. The quickest approach is to run `Get-SqlAgentJobFailureSummary` as part of a morning routine and investigate any `run_status = 0` entries.

For automated alerting, SQL Agent can send email via Database Mail when a job fails. Configure this in SQL Agent job properties under "Notifications" — set "E-mail" to "When the job fails" and route to a monitored distribution list.

## Related scripts

- [`Get-BackupCoverage`](../backup-coverage/index.md) — verify backup coverage is the result of more than just checking that the backup job hasn't failed
- [`Get-LastDbccCheckdb`](../dbcc-checkdb-history/index.md) — a CHECKDB job that's been silently failing shows up here
- [`Get-InstanceConfigurationScore`](../instance-configuration-audit/index.md) — includes backup coverage check as part of a broader audit

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/monitoring/Get-SqlAgentJobFailureSummary.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-SqlAgentJobFailureSummary.sql)
- [`sql/monitoring/Get-SqlAgentJobOverview.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-SqlAgentJobOverview.sql)
- [`sql/monitoring/Get-JobScheduleSummary.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/monitoring/Get-JobScheduleSummary.sql)

---

## SEO

**Focus keyphrase:** SQL Server Agent job failures

**Meta description** (155 chars — target 150–160):  
Find SQL Server Agent job failures from the last 7 days with job name, step, error message, and run time. Essential for catching silent maintenance failures.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `job-failure-summary-output.png` | Get-SqlAgentJobFailureSummary output showing job_name, step_name, run_datetime, run_duration, and message column with several failures | Agent job failure summary |
| `job-overview-output.png` | Get-SqlAgentJobOverview output showing enabled jobs with last_run_status column highlighting failed jobs | SQL Agent job overview |
