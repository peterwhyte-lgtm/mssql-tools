---
title: "Script: Finding SQL Server Orphaned Database Users"
slug: sql-server-orphaned-users
published: 
published_url: 
status: draft
category: security
tags: [security, orphaned-users, logins, migration, permissions]
scripts:
  - sql/security/Get-OrphanedUsers.sql
  - powershell/security/Get-OrphanedUsers.ps1
seo_keyphrase: SQL Server orphaned users
seo_title: "SQL Server Orphaned Database Users — Find and Fix Them"
seo_description: Find SQL Server database users with no matching server login. Orphaned users cause login failures after migrations and are a common post-migration cleanup item. (157 chars)
screenshots_needed:
  - Get-OrphanedUsers output showing database_name, user_name, user_type, and create_date across multiple databases
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: Finding SQL Server Orphaned Database Users

An orphaned user is a database principal that has no matching server login. The user exists inside the database — they have permissions, role memberships, maybe even object ownership — but their server-level login either no longer exists or has a different SID. Any attempt to connect as that user results in an error, even though the database shows them as a valid user.

Orphaned users are almost always created by migrations. A database is backed up from Server A and restored to Server B. The database users come with it, but their corresponding logins don't (unless explicitly migrated). The database has users pointing to SIDs that don't exist on the new server.

They also appear after login consolidation, after someone drops a login without first removing database users, and after Active Directory account changes.

## The problem

Orphaned users are silent until they matter. The database opens fine, queries run, everything looks normal. Then someone tries to connect with a specific account that used to work — a monitoring tool, a legacy reporting query, a monthly batch job — and gets an error. Investigating takes time because the user *does* appear in the database when you look.

After a migration, the right time to find orphaned users is before go-live, not after the first support call.

## The script

```sql
-- Runs in the context of each online user database via dynamic SQL
SELECT
    database_name,
    user_name,
    user_type,
    create_date
FROM #orphaned
ORDER BY database_name, user_name;
```

The script uses dynamic SQL to execute in each database's context, checking `sys.database_principals` against `sys.server_principals` by SID. Users whose SIDs have no matching server-level login are returned.

## How to run it from the repo

```powershell
# Find all orphaned users across all databases
.\run.ps1 Get-OrphanedUsers

# Against a remote server
.\run.ps1 Get-OrphanedUsers -ServerInstance MYSERVER\INST01

# Save results for post-migration cleanup
.\run.ps1 Get-OrphanedUsers -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `database_name` | Which database contains the orphaned user. |
| `user_name` | The database principal name. This is what appears in `sys.database_principals`. |
| `user_type` | `SQL_USER` (SQL auth user) or `WINDOWS_USER` (Windows auth user mapped to a SID that no longer exists). |
| `create_date` | When the database user was created. Old dates alongside a recent migration confirm the user came with the database backup. |

## What to do with orphaned users

You have three options for each orphaned user:

**Option 1: Remap to an existing login** — if the corresponding login exists on the new server with a different SID (common when logins were re-created rather than scripted):

```sql
USE [YourDatabase];
ALTER USER [orphaned_user_name] WITH LOGIN = [matching_login_name];
```

This repairs the SID link. The user retains all their existing permissions and role memberships.

**Option 2: Create the missing login and remap** — if the login genuinely needs to exist:

```sql
-- Create the login (choose the right auth type)
CREATE LOGIN [domain\username] FROM WINDOWS;
-- or
CREATE LOGIN [sql_user] WITH PASSWORD = 'ChangeMe123!';

USE [YourDatabase];
ALTER USER [orphaned_user_name] WITH LOGIN = [matching_login_name];
```

**Option 3: Drop the orphaned user** — if the account is no longer needed:

```sql
USE [YourDatabase];
-- First, check for object ownership
SELECT name, type_desc FROM sys.objects WHERE principal_id = USER_ID('orphaned_user_name');

-- Transfer ownership if needed
ALTER AUTHORIZATION ON SCHEMA::[schema_name] TO [dbo];

-- Then drop
DROP USER [orphaned_user_name];
```

Check for object ownership before dropping — if the orphaned user owns a schema or objects, those need to be reassigned first. The `ALTER AUTHORIZATION` command transfers schema ownership to dbo.

## Scripted migration approach

For planned migrations, generate login scripts from the source server before the migration, restore them on the target, and run `Get-OrphanedUsers` after restore to verify no gaps:

```powershell
# On the source server — generate login scripts
.\run.ps1 Generate-LoginScript -OutputFormat Csv

# On the target server after restore — check for orphans
.\run.ps1 Get-OrphanedUsers -ServerInstance TARGETSERVER
```

`Generate-LoginScript` creates `CREATE LOGIN` statements with the correct SIDs for SQL logins, so they map correctly to existing database users after restore.

## Normal expected output

On a stable, non-migrated instance: no rows. A zero-row result is the correct answer.

On a freshly migrated instance: any number of rows, all of which need attention before go-live.

After running `Get-OrphanedUsers` on a new client's instance: a non-zero count is common. SQL Server environments accumulate orphaned users over years of migrations, server rebuilds, and login drops.

## Related scripts

- [`Get-SysadminMembers`](../sysadmin-audit/index.md) — check who has elevated server permissions while you're doing security cleanup
- [`Generate-LoginScript`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/migration/Generate-LoginScript.ps1) — script logins from the source server before migration
- [`Get-UserPermissionsAudit`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/security/Get-UserPermissionsAudit.ps1) — see what permissions each database user holds
- [`Get-MigrationRiskAssessment`](../migration-risk-assessment/index.md) — pre-migration scan that includes orphaned owner checks

## Get the scripts

The full script is in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/security/Get-OrphanedUsers.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/security/Get-OrphanedUsers.sql)
- [`powershell/security/Get-OrphanedUsers.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/security/Get-OrphanedUsers.ps1)

---

## SEO

**Focus keyphrase:** SQL Server orphaned users

**Meta description** (157 chars — target 150–160):  
Find SQL Server database users with no matching server login. Orphaned users cause login failures after migrations and are a common post-migration cleanup item.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `orphaned-users-output.png` | Get-OrphanedUsers output showing multiple orphaned SQL_USER and WINDOWS_USER entries across several databases | Orphaned users across databases |
