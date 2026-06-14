# docs/ops/

Change management content for planned DBA work. Covers the full lifecycle from pre-change approval through execution and rollback.

## Structure

```text
docs/ops/
  *.sql              — reusable SQL templates for common DBA operations
  change-orders/     — CAB-ready approval documents (complete before any change)
  checklists/        — step-by-step execution checklists (use during the change window)
  runbooks/          — full playbooks for migrations, upgrades, and DR scenarios
  rollback/          — rollback decision criteria and procedures
```

## Change lifecycle

1. **`change-orders/`** — get approval before starting; document pre/post checks and rollback criteria
2. **`checklists/`** — execute step by step during the window
3. **`rollback/`** — trigger criteria and step-by-step rollback if things go wrong

## SQL templates

Reusable SQL for common DBA change operations. Copy, review, and adapt before running in production.

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
| `change-template-installation.sql` | SQL Server installation checklist queries |
| `change-template-patching.sql` | Pre/post-patch validation queries |

## Change orders

| Document | Use for |
|----------|---------|
| `sql-server-upgrade-change-order.md` | SQL Server version upgrade (in-place or side-by-side) |
| `server-migration-change-order.md` | Hardware or VM server replacement |
| `alwayson-planned-failover-change-order.md` | AG planned failover or replica maintenance |

## Checklists

| Checklist | Use for |
|-----------|---------|
| `sql-version-upgrade.md` | SQL Server version upgrade |
| `alwayson-migration.md` | AG failover, replica addition/removal, listener changes |
| `server-replacement.md` | Physical or VM server replacement |
| `dr-failover.md` | DR failover and failback |

## Runbooks

| Runbook | Covers |
|---------|--------|
| `RUNBOOK-Standalone.md` | Standalone server migration (backup/restore) |
| `RUNBOOK-AG-Cluster.md` | AG cluster migration and failover |
| `RUNBOOK-OsUpgrade.md` | OS upgrade in-place or side-by-side |
| `RUNBOOK-SqlEditionChange.md` | Edition downgrade or upgrade |
| `RUNBOOK-SqlVersionUpgrade.md` | SQL Server version upgrade end-to-end |

## Rollback

`rollback/migration-rollback-playbook.md` — binary trigger criteria, decision ownership, and step-by-step rollback for each migration type.