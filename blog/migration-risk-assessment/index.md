---
title: "Script: SQL Server Pre-Migration Risk Assessment"
slug: sql-server-pre-migration-risk-assessment
published: 
published_url: 
status: draft
category: migration
tags: [migration, risk-assessment, compatibility, pre-flight, linked-servers]
scripts:
  - sql/migration/Get-MigrationRiskAssessment.sql
  - sql/migration/Get-DatabaseInventory.sql
seo_keyphrase:    SQL Server pre-migration risk assessment
seo_title:        "Script: SQL Server Pre-Migration Risk Assessment"
seo_description:  Run a pre-migration risk scan across all databases before any SQL Server upgrade or platform move. Surfaces compatibility gaps, AG dependencies, orphaned owners, and sizing issues. (189 chars — trim)
screenshots_needed:
  - Get-MigrationRiskAssessment output showing risk_level, category, database_name, and finding columns — include CRITICAL rows in view
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server Pre-Migration Risk Assessment

Every SQL Server migration that goes badly wrong follows the same pattern: something was known in advance, nobody checked, and it surfaced at 11pm during the cutover. The compatibility level is still at 2014 on a server being migrated to 2022. The database owner's login doesn't exist on the target. There are linked server dependencies that nobody documented. The migration proceeds, something breaks, and the rollback takes three hours.

This pre-flight script surfaces the categories of risk that appear most often in real migrations. Run it on the source server before planning your migration window.

## The problem

Migrating SQL Server databases — whether you're moving to a new version, a new host, or a cloud platform — involves more than backing up and restoring. Several conditions on the source can cause silent failures or post-migration behaviour changes:

- **Compatibility level below instance native** — A database at compat level 120 (SQL 2014) running on a SQL 2022 instance won't benefit from the newer query optimiser, and some queries that worked under the old optimiser may perform differently when you finally raise the compat level.
- **Orphaned database owners** — If the `sa` or domain login that owns a database doesn't exist on the target, some operations (particularly SQL Agent jobs and SSMS right-click actions) will fail silently.
- **Linked servers** — Dependencies that must be recreated on the target, with potentially different server names or credentials.
- **Availability Group membership** — AG databases can't be migrated by simple backup/restore; they require removing from the AG on all replicas first.
- **AUTO_SHRINK / AUTO_CLOSE** — Both are off by default and should stay that way. Finding these on source databases before migration lets you fix them rather than carrying the problem forward.
- **Large databases** — A 2TB database that takes 8 hours to restore needs to be part of your migration window planning.

## The script

```sql
SET NOCOUNT ON;

DECLARE @instance_compat SMALLINT;
SELECT @instance_compat =
    CASE CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)
        WHEN 16 THEN 160  -- SQL 2022
        WHEN 15 THEN 150  -- SQL 2019
        WHEN 14 THEN 140  -- SQL 2017
        WHEN 13 THEN 130  -- SQL 2016
        WHEN 12 THEN 120  -- SQL 2014
        WHEN 11 THEN 110  -- SQL 2012
        ELSE 100
    END;

SELECT risk_category, risk_level, object_name, finding, recommendation
FROM (

    -- Compatibility level below instance native
    SELECT
        'Compatibility Level'                                AS risk_category,
        CASE
            WHEN d.compatibility_level < 100             THEN 'HIGH'
            WHEN d.compatibility_level < (@instance_compat - 10) THEN 'MEDIUM'
            ELSE 'INFO'
        END                                                  AS risk_level,
        d.name                                               AS object_name,
        'Compat level ' + CAST(d.compatibility_level AS VARCHAR(5)) +
            ' (instance native: ' + CAST(@instance_compat AS VARCHAR(5)) + ')' AS finding,
        'Test on non-prod with target compat level before cutover' AS recommendation
    FROM sys.databases d
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0
      AND d.compatibility_level < @instance_compat

    UNION ALL

    -- AUTO_SHRINK
    SELECT 'Database Settings', 'HIGH', d.name,
        'AUTO_SHRINK is ON',
        'Disable: ALTER DATABASE [' + d.name COLLATE DATABASE_DEFAULT + '] SET AUTO_SHRINK OFF'
    FROM sys.databases d
    WHERE d.is_auto_shrink_on = 1
      AND d.name NOT IN ('master','model','msdb','tempdb') AND d.state = 0

    UNION ALL

    -- AUTO_CLOSE
    SELECT 'Database Settings', 'MEDIUM', d.name,
        'AUTO_CLOSE is ON',
        'Disable: ALTER DATABASE [' + d.name COLLATE DATABASE_DEFAULT + '] SET AUTO_CLOSE OFF'
    FROM sys.databases d
    WHERE d.is_auto_close_on = 1
      AND d.name NOT IN ('master','model','msdb','tempdb') AND d.state = 0

    UNION ALL

    -- Non-ONLINE databases
    SELECT 'Database State', 'HIGH', d.name,
        'State: ' + d.state_desc COLLATE DATABASE_DEFAULT,
        'Resolve before migration - cannot migrate non-ONLINE databases'
    FROM sys.databases d
    WHERE d.name NOT IN ('master','model','msdb','tempdb') AND d.state <> 0

    UNION ALL

    -- Linked servers
    SELECT 'External Dependencies', 'HIGH', s.name,
        'Linked server: ' + s.name COLLATE DATABASE_DEFAULT +
            ' (' + ISNULL(s.product COLLATE DATABASE_DEFAULT,'unknown') +
            ' via ' + ISNULL(s.provider COLLATE DATABASE_DEFAULT,'unknown') + ')',
        'Validate linked server connectivity from target server before cutover'
    FROM sys.servers s WHERE s.is_linked = 1

    UNION ALL

    -- Orphaned owners
    SELECT 'Database Ownership', 'MEDIUM', d.name,
        'Orphaned owner SID - login does not exist on this instance',
        'Fix: ALTER AUTHORIZATION ON DATABASE::[' + d.name COLLATE DATABASE_DEFAULT + '] TO sa'
    FROM sys.databases d
    WHERE d.name NOT IN ('master','model','msdb','tempdb') AND d.state = 0
      AND SUSER_SNAME(d.owner_sid) IS NULL

    UNION ALL

    -- Availability Group membership
    SELECT 'Availability Groups', 'HIGH', d.name,
        'Database is in an Availability Group',
        'AG migration requires coordinated removal from AG on all replicas before migration'
    FROM sys.databases d
    JOIN sys.dm_hadr_database_replica_states hdrs ON d.database_id = hdrs.database_id
    WHERE hdrs.is_local = 1
      AND d.name NOT IN ('master','model','msdb','tempdb')

    UNION ALL

    -- Large databases
    SELECT 'Migration Sizing', 'INFO', d.name,
        'Data size: ' + CAST(CAST(SUM(mf.size) * 8.0 / 1048576 AS DECIMAL(10,1)) AS VARCHAR(20)) + ' GB',
        'Estimate backup/restore duration and verify network bandwidth before scheduling window'
    FROM sys.databases d
    JOIN sys.master_files mf ON d.database_id = mf.database_id AND mf.type = 0
    WHERE d.name NOT IN ('master','model','msdb','tempdb') AND d.state = 0
    GROUP BY d.name
    HAVING SUM(mf.size) * 8.0 / 1048576 > 100

) r
ORDER BY
    CASE r.risk_level WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
    r.risk_category, r.object_name;
```

## How to run from the repo

```powershell
# Run against the source server
.\run.ps1 Get-MigrationRiskAssessment

# Save findings to CSV — useful for migration documentation
.\run.ps1 Get-MigrationRiskAssessment -OutputFormat Csv -ServerInstance SOURCE_SERVER
```

Run this on the **source server** — the one you're migrating away from. The findings tell you what to fix before the migration and what to plan for during it.

## Reading the output

| Column | What it means |
|--------|---------------|
| `risk_level` | `HIGH` = blocks or breaks the migration. `MEDIUM` = known issue, fix before or document. `INFO` = awareness only. |
| `risk_category` | Groups related findings. Deal with all `HIGH` items in one category before moving to the next. |
| `object_name` | The database or linked server with the finding |
| `finding` | Plain-language description of the issue and any relevant values |
| `recommendation` | The SQL command or action to resolve it |

## How to work through the findings

**HIGH findings first — these block or break the migration:**

- **Non-ONLINE databases** — A database in RESTORING, SUSPECT, or EMERGENCY state cannot be migrated. Resolve or document these before scheduling the window.
- **Availability Group membership** — You cannot migrate an AG database with a simple backup/restore. You must remove it from the AG on all replicas, migrate, then re-add. The `recommendation` column gives you the starting point.
- **AUTO_SHRINK ON** — This setting causes random I/O spikes, fragmentation, and performance unpredictability. Disable it before migration. The recommendation column gives you the exact command.

**MEDIUM findings — fix before migration if possible:**

- **Orphaned owner SIDs** — Run the `ALTER AUTHORIZATION` command in the recommendation column on the source. Verify the target has a known owner login.
- **Compatibility level gaps** — A database at compat 120 on a SQL 2022 instance will work, but queries optimised for 2014 behaviour may change when you eventually raise the level. Test in non-prod first with `ALTER DATABASE [db] SET COMPATIBILITY_LEVEL = 160`.
- **AUTO_CLOSE** — Same as AUTO_SHRINK; just disable it.

**INFO findings — plan around these:**

- **Linked servers** — Document every linked server. Recreate them on the target with the new server name context. Test any cross-server queries before cutover.
- **Large databases (>100GB)** — These are flagged because they affect your maintenance window length. A full backup of 500GB over a 1Gb network is a 70+ minute transfer. Factor this into your RTO planning.

## Things this script doesn't check

Be aware of what's out of scope and run additional checks if relevant:

- **SQL Agent jobs** — Jobs referencing the old server name or specific file paths will need updating. Use `Get-JobInventory.sql` from the migration folder.
- **Login and permission gaps** — Logins that exist on the source but not the target. Use `Get-LoginInventory.sql` and `Generate-LoginScript.sql`.
- **Deprecated features in use** — `Get-DeprecatedFeaturesInUse.sql` checks for SQL syntax or features removed in newer versions.
- **CLR, FILESTREAM, full-text** — If any database uses these features, verify they're enabled on the target instance first.

## Gotchas

- **Run on the source server.** The compat level check compares against the instance's own native level. If you run this on the target instance against a database you've already moved, you'll get false negatives.
- **The AG check returns 0 rows on non-AG instances.** This is expected — not an error.
- **Orphaned owner check uses `SUSER_SNAME()`**, which resolves against the current instance's logins. An owner that's orphaned on the source may or may not exist on the target — check both.
- **If your source and target have different collations**, this script uses `COLLATE DATABASE_DEFAULT` on catalog string columns to avoid UNION ALL collation conflicts. If you're seeing unexpected errors, check that your master database collation is consistent.

## Related scripts in this repo

- [`Get-DatabaseInventory.sql`](../sql/migration/Get-DatabaseInventory.sql) — full database list with sizing, recovery model, and compat level
- [`Get-LoginInventory.sql`](../sql/migration/Get-LoginInventory.sql) — all logins, types, and disabled status for recreation on target
- [`Get-JobInventory.sql`](../sql/migration/Get-JobInventory.sql) — SQL Agent jobs that will need review after migration
- [`Get-DeprecatedFeaturesInUse.sql`](../sql/migration/Get-DeprecatedFeaturesInUse.sql) — deprecated syntax that may break on a newer engine version

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/migration/Get-MigrationRiskAssessment.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/migration/Get-MigrationRiskAssessment.sql)
- [`sql/migration/Get-DatabaseInventory.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/migration/Get-DatabaseInventory.sql)

---

## SEO

**Focus keyphrase:** SQL Server pre-migration risk assessment

**Meta description** (156 chars):  
Run a pre-migration risk scan before any SQL Server upgrade or platform move. Surfaces compatibility gaps, AG dependencies, orphaned owners, and sizing issues.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `migration-risk-output.png` | SQL Server pre-migration risk assessment results showing HIGH and MEDIUM findings for compatibility level and AUTO_SHRINK settings | Pre-migration risk assessment output |
