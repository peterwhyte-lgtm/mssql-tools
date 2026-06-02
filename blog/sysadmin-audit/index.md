---
title: "Script: SQL Server sysadmin and Login Security Audit"
slug: sql-server-sysadmin-login-audit
published: 
published_url: 
status: draft
category: security
tags: [security, sysadmin, logins, permissions, audit]
scripts:
  - sql/security/Get-SysadminMembers.sql
  - sql/security/Get-WeakLoginSettings.sql
  - sql/security/Get-ServerRoleMembers.sql
  - powershell/security/Get-SysadminMembers.ps1
  - powershell/security/Get-WeakLoginSettings.ps1
  - powershell/security/Get-ServerRoleMembers.ps1
seo_keyphrase: SQL Server sysadmin audit
seo_title: "SQL Server sysadmin Membership and Login Security Audit"
seo_description: Find who has sysadmin rights in SQL Server and identify logins with weak security settings — password policy off, no expiration, or the sa account still enabled. (158 chars)
screenshots_needed:
  - Get-SysadminMembers output showing login_name, type_desc, is_disabled, and create_date columns
  - Get-WeakLoginSettings output showing logins with risk_flag of SA_ENABLED or PASSWORD_POLICY_OFF
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Script: SQL Server sysadmin and Login Security Audit

`sysadmin` is SQL Server's most powerful server role. Members can do anything: read any data, drop any database, run OS commands via `xp_cmdshell`, modify any configuration, create any login. On most production systems, the number of accounts with `sysadmin` should be small and known — service accounts that genuinely need it, the DBA team, and nothing else.

In practice, sysadmin membership tends to accumulate quietly. A developer gets sysadmin during a project and it never gets revoked. A service account from a decommissioned application still has it. The default `sa` login is enabled and hasn't changed its password in years. A vendor account was granted sysadmin "temporarily" during a support case.

These two scripts surface all of that in one pass.

## The problem

SQL logins with weak settings — password policy off, expiration not enforced, or the `sa` account active — are a significant attack surface. SQL authentication is targeted by automated scanning tools that test common credentials against exposed SQL Server ports. A SQL login without password policy or expiration can accumulate indefinitely, and if it has a weak password, a brute-force attack will eventually succeed.

Periodic sysadmin membership reviews and login security audits are a basic security control that many organisations skip because there's no built-in alerting — nothing tells you when someone joins the `sysadmin` role.

## The scripts

### Get-SysadminMembers.sql — who has sysadmin

```sql
SELECT
    sp.name         AS login_name,
    sp.type_desc,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date
FROM sys.server_principals sp
JOIN sys.server_role_members srm ON sp.principal_id = srm.member_principal_id
JOIN sys.server_principals sr    ON srm.role_principal_id = sr.principal_id
WHERE sr.name = 'sysadmin'
ORDER BY sp.name;
```

### Get-WeakLoginSettings.sql — login security flags

```sql
SELECT
    sl.name                                                          AS login_name,
    sl.is_disabled,
    sl.is_policy_checked,
    sl.is_expiration_checked,
    CAST(LOGINPROPERTY(sl.name, 'PasswordLastSetTime') AS DATETIME) AS password_last_set,
    CAST(LOGINPROPERTY(sl.name, 'IsLocked')           AS BIT)      AS is_locked,
    CAST(LOGINPROPERTY(sl.name, 'IsMustChange')       AS BIT)      AS must_change_password,
    sl.default_database_name,
    sl.create_date,
    sl.modify_date,
    CASE
        WHEN sl.name = 'sa' AND sl.is_disabled = 0 THEN 'SA_ENABLED'
        WHEN sl.is_policy_checked    = 0           THEN 'PASSWORD_POLICY_OFF'
        WHEN sl.is_expiration_checked = 0          THEN 'EXPIRATION_OFF'
        ELSE 'OK'
    END                                                              AS risk_flag
FROM sys.sql_logins AS sl
WHERE sl.name NOT LIKE '##%'
ORDER BY
    CASE
        WHEN sl.name = 'sa' AND sl.is_disabled = 0 THEN 0
        WHEN sl.is_policy_checked    = 0           THEN 1
        WHEN sl.is_expiration_checked = 0          THEN 2
        ELSE 3
    END,
    sl.name;
```

## How to run it from the repo

```powershell
# Who has sysadmin
.\run.ps1 Get-SysadminMembers

# Login security flags — sorted by risk
.\run.ps1 Get-WeakLoginSettings

# All server role memberships (not just sysadmin)
.\run.ps1 Get-ServerRoleMembers

# Save to CSV for audit records
.\run.ps1 Get-SysadminMembers -OutputFormat Csv
.\run.ps1 Get-WeakLoginSettings -OutputFormat Csv
```

## Reading the output — Get-SysadminMembers

| Column | What it means |
|--------|---------------|
| `login_name` | The login name. |
| `type_desc` | `SQL_LOGIN` (SQL auth), `WINDOWS_LOGIN` (Windows auth), `WINDOWS_GROUP` (AD group), `SERVICE_MASTER_KEY` or `CERTIFICATE_MAPPED_LOGIN` (internal). Windows group members are not individually listed — use `Get-ServerRoleMembers` to expand groups. |
| `is_disabled` | 1 if the login is disabled. A disabled sysadmin login is still a finding — it can be re-enabled by anyone who currently has sysadmin. |
| `create_date` | When the login was created. Long-standing accounts with no recent `modify_date` may be legacy access that was never cleaned up. |
| `modify_date` | When the login was last modified (password change, property change). A login that hasn't been modified in years is worth reviewing. |

## Reading the output — Get-WeakLoginSettings

| Column | What it means |
|--------|---------------|
| `login_name` | SQL login name. Windows logins are not returned (they inherit Windows password policy). |
| `is_disabled` | Whether the login is currently disabled. |
| `is_policy_checked` | Whether Windows Password Policy enforcement is applied. OFF means no minimum length, complexity, or lockout enforcement. |
| `is_expiration_checked` | Whether Windows Password Expiration is applied. OFF means the password never expires regardless of Windows policy. |
| `password_last_set` | When the password was last changed. `NULL` means it was never changed since creation. |
| `is_locked` | 1 if the login is currently locked due to failed attempts. |
| `must_change_password` | 1 if the user must change password at next login. |
| `risk_flag` | `SA_ENABLED` (most critical), `PASSWORD_POLICY_OFF`, `EXPIRATION_OFF`, or `OK`. |

## What to look for

**`risk_flag = SA_ENABLED`** — the `sa` account is enabled with no restrictions. It's a well-known target, its name can't be changed by attackers (making credential attacks simpler), and it's sysadmin by definition. On every production instance it should be disabled or at minimum have an extremely strong password:

```sql
-- Disable sa (recommended)
ALTER LOGIN [sa] DISABLE;

-- Or rename it (belt and suspenders alongside disabling)
ALTER LOGIN [sa] WITH NAME = [sql_sa_renamed];
```

**`risk_flag = PASSWORD_POLICY_OFF`** — the SQL login doesn't enforce Windows password complexity rules. This means it can have a password of "password", "123456", or even a blank password. For any login that connects from an application, the password should be treated as a service credential — complex, stored securely, and rotated on a defined schedule.

**`risk_flag = EXPIRATION_OFF`** — the password never expires. Combined with a weak password, this allows indefinite access until manually rotated.

**Many `WINDOWS_GROUP` members in sysadmin** — groups can contain many users. A Windows group in the `sysadmin` role means every member of that group is a SQL Server sysadmin, including future additions to the group. Use `Get-ServerRoleMembers` to understand what's in those groups, and consider whether direct login grants are more auditable.

**Disabled sysadmin logins** — a disabled login in `sysadmin` is still a risk. If it gets re-enabled (easy to do with `ALTER LOGIN [name] ENABLE`), it immediately has sysadmin access. Remove sysadmin membership from disabled logins or drop the login entirely if it's no longer needed:

```sql
-- Remove from sysadmin
ALTER SERVER ROLE [sysadmin] DROP MEMBER [old_login];

-- Or drop the login entirely
DROP LOGIN [old_login];
```

**Unexpected service accounts** — a service account that runs an application has sysadmin, when it probably only needs `db_datareader` and `db_datawriter` on specific databases. Least-privilege principles apply to SQL Server too.

## Normal findings to expect

- `NT AUTHORITY\SYSTEM` — Windows system account. Expected.
- `NT SERVICE\MSSQLSERVER` (or the instance equivalent) — SQL Server service account. Expected.
- `NT SERVICE\SQLAgent$INSTANCENAME` — SQL Agent service account. Expected.
- The DBA team Windows logins or group. Expected — verify the list is current.
- `sa` with `is_disabled = 1` — `risk_flag = OK`. Good.

Anything else warrants a review.

## Related scripts

- [`Get-ServerRoleMembers`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/security/Get-ServerRoleMembers.ps1) — all server role memberships, not just sysadmin
- [`Get-UserPermissionsAudit`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/security/Get-UserPermissionsAudit.ps1) — database-level permissions and role memberships
- [`Get-OrphanedUsers`](../orphaned-users/index.md) — database users with no matching server login
- [`Get-InstanceConfigurationScore`](../instance-configuration-audit/index.md) — includes sa and xp_cmdshell checks as part of a broader audit

## Get the scripts

The full scripts are in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/security/Get-SysadminMembers.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/security/Get-SysadminMembers.sql)
- [`sql/security/Get-WeakLoginSettings.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/security/Get-WeakLoginSettings.sql)
- [`sql/security/Get-ServerRoleMembers.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/security/Get-ServerRoleMembers.sql)

---

## SEO

**Focus keyphrase:** SQL Server sysadmin audit

**Meta description** (158 chars — target 150–160):  
Find who has sysadmin rights in SQL Server and identify logins with weak security settings — password policy off, no expiration, or the sa account still enabled.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `sysadmin-members-output.png` | Get-SysadminMembers output showing login_name, type_desc, is_disabled columns with several unexpected accounts visible | sysadmin membership output |
| `weak-login-settings-output.png` | Get-WeakLoginSettings output showing SA_ENABLED and PASSWORD_POLICY_OFF risk_flag rows sorted to top | Weak login settings output |
