# docs/ops

Production SQL Server operational scripts, automation, and change management — organised by lifecycle phase.

## Structure

```text
docs/ops/
  change-orders/    — CAB-ready approval documents (complete before any change)
  checklists/       — step-by-step execution checklists (use during the change window)
  rollback/         — rollback decision criteria and procedures by migration type
  change-templates/ — SQL-level runbook templates (CDC, TDE, AG, statistics, etc.)
  installation/     — SQL Server installation automation
    templates/      — INI answer files per environment/edition
  patches/          — SQL Server CU updates and SSMS updates
```

The change lifecycle for a migration:
1. `change-orders/` — get approval before starting
2. `checklists/` — execute step by step during the window
3. `rollback/` — trigger criteria and procedure if things go wrong

## change-orders

CAB-ready change order templates. Complete all fields, attach `Invoke-PreMigrationAssessment.ps1` output as evidence, and get approval before the change window.

| Template | Use for |
|----------|---------|
| `sql-server-upgrade-change-order.md` | SQL Server version upgrade (in-place or side-by-side) |
| `server-migration-change-order.md` | Hardware or VM server replacement |
| `alwayson-planned-failover-change-order.md` | AG planned failover or replica maintenance |

## checklists

Step-by-step execution checklists — work through these during the change window. Each pairs with a change order above.

| Checklist | Use for |
|-----------|---------|
| `sql-version-upgrade.md` | SQL Server version upgrade — in-place or side-by-side |
| `alwayson-migration.md` | AG planned failover, replica addition/removal, listener changes |
| `server-replacement.md` | Physical or VM server replacement via backup/restore or log shipping |
| `dr-failover.md` | DR failover (planned test or actual disaster) and failback |

## rollback

| Document | Purpose |
|----------|---------|
| `migration-rollback-playbook.md` | Binary trigger criteria, decision ownership, and step-by-step rollback for each migration type |

## change-templates

SQL-level runbook templates for common DBA change operations. Copy, review, and adapt before running in production.

| Template | Purpose |
|----------|---------|
| `Configure-AlwaysOn-AvailabilityGroup-Template.sql` | AG creation and replica configuration |
| `Configure-Cdc-Template.sql` | Enable CDC on a database |
| `Configure-Mirroring-Template.sql` | Database mirroring setup |
| `Configure-Tde-Template.sql` | Transparent Data Encryption |
| `Database-Consistency-Check-Template.sql` | DBCC CHECKDB workflow |
| `Pre-OSUpgrade-Readiness.sql` | Pre-flight checks before OS upgrade |
| `Recompile-Procedure-Template.sql` | Force recompile stored procedures |
| `Restore-Database-NoRecovery-Template.sql` | Restore with NORECOVERY for log shipping/AG |
| `Update-Statistics-Template.sql` | Statistics update workflow |

## installation

```powershell
# Interactive mode — prompts for all settings
.\admin\installation\Install-SqlServer.ps1

# Unattended with params
.\admin\installation\Install-SqlServer.ps1 `
    -SetupPath D:\SQL2022\setup.exe `
    -SAPassword (ConvertTo-SecureString 'MyStr0ng!Pass' -AsPlainText -Force)

# Using an answer file (recommended for repeatable env installs)
.\admin\installation\Install-SqlServer.ps1 `
    -SetupPath D:\SQL2022\setup.exe `
    -AnswerFile .\admin\installation\templates\sql-server-install-default.ini `
    -SAPassword (ConvertTo-SecureString 'MyStr0ng!Pass' -AsPlainText -Force)
```

**What the installer does:**
- Validates elevation, directories, and SA password complexity
- Calculates recommended MaxMemory and MaxDOP from hardware
- Runs `setup.exe` with TCP enabled, named pipes off, SQL Agent set to Automatic
- Applies MaxMemory, MaxDOP, and cost threshold for parallelism post-install
- Logs everything to `output-files\installation\`

## patches

```powershell
# Apply a CU to all instances (patch file downloaded separately)
.\admin\patching\Update-SqlServer.ps1 `
    -PatchPath C:\Patches\SQLServer2022-KB5046059-x64.exe

# Apply to a specific instance only
.\admin\patching\Update-SqlServer.ps1 `
    -PatchPath C:\Patches\SQLServer2022-KB5046059-x64.exe `
    -InstanceName SQL2022

# Update SSMS via winget (default)
.\admin\patching\Update-Ssms.ps1

# Update SSMS via direct download
.\admin\patching\Update-Ssms.ps1 -Method download
```

Download SQL Server CU patches from:
<https://support.microsoft.com/en-us/help/321185>
