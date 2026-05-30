# DBA Scripts
A production‑ready SQL Server DBA toolkit for diagnostics, automation, and operational review.

![banner](banner.png)

This repository provides a structured, enterprise‑grade library of SQL and PowerShell tools designed for real‑world DBA work. It focuses on fast troubleshooting, safe investigation, repeatable workflows, and operational consistency across SQL Server environments.

## 🚀 Start Here

If you're new to the repo, begin with this quick path:

Get a full repo overview:

```powershell
.\helpers\triage\Show-RepoOverview.ps1
```

Pick the script that matches your task:

- Use `sql/` for SSMS‑ready diagnostics and investigations
- Use `powershell/` for automation, orchestration, and local execution

Validate SQL connectivity (recommended):

```powershell
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance . -Database master
```

Use `sql-templates/operations/` for production‑style runbooks and change‑order templates.

Save outputs you want to reuse under `output-files/`.

## ⭐ Most Useful Scripts

These are the core scripts most DBAs start with:

- **Get-WaitStatistics** — performance bottleneck analysis
- **Get-LongRunningQueries** — top resource consumers
- **Permission Audit** — login, role, and access review
- **Server Inventory Pack** — instance‑level metadata and configuration
- **Test-SqlConnectivity** — quick connectivity validation

## 📦 Repository Structure

The repo is organized into three practical layers that mirror real DBA workflows:

### SQL Layer

For DMVs, diagnostics, and read‑only investigations.

- `sql/performance` — waits, blocking, long‑running queries, missing indexes, I/O
- `sql/backups` — backup coverage, restore prep, DR readiness
- `sql/monitoring` — health, memory, MAXDOP, jobs, AG, snapshots
- `sql/security` — permissions and access reviews
- `sql/migration` — logins, jobs, linked servers, inventory
- `sql-templates/operations` — production runbook templates

### PowerShell Layer

For automation, orchestration, and local execution.

- `powershell/inventory` — storage, growth, instance inventory
- `powershell/backup-automation` — backup/restore helpers
- `powershell/reporting` — waits, blocking, index reporting
- `powershell/health-checks` — DB health and TempDB checks

### Hybrid Layer

Lightweight helpers that glue the repo together.

- `helpers/triage` — repo inventory and script discovery
- `helpers/local-sql` — connectivity tests and SQL execution
- `helpers/maintenance` — cleanup and repo hygiene
- `tools` — repo maintenance utilities
- `examples` — sample workflows

## 🧪 Example Commands

```powershell
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-LongRunningQueries
.\helpers\Run-Helper.ps1 -ScriptName Get-WaitStatistics
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance . -Database master
```

## 🎯 What This Repo Optimizes For

- Fast copy/paste into SSMS or Azure Data Studio
- Clear category grouping by real DBA tasks
- Easy handoff to other production DBAs
- Repeatable workflows and operational consistency
- A solid foundation for blog posts, runbooks, and automation

## 🗺 Category Map (At a Glance)

- `sql/performance` — waits, blocking, long‑running queries, missing indexes, I/O
- `sql/backups` — backup coverage, restore prep, DR readiness
- `sql/monitoring` — health, memory, MAXDOP, jobs, AG
- `sql/security` — permissions and access reviews
- `powershell/inventory` — storage, growth, instance inventory
- `powershell/backup-automation` — backup/restore helpers
- `powershell/reporting` — waits, blocking, index reporting
- `powershell/health-checks` — DB health and TempDB

## 🛠 How to Use This Repo

- Start in `sql/` for SSMS‑ready analysis scripts
- Use `powershell/` for automation and local troubleshooting
- Use `sql-templates/operations/` for production runbooks
- Use `helpers/triage/` for repo discovery
- Use `helpers/local-sql/` for SQL connectivity and execution
- Use `tools/` for repo maintenance
- Read `docs/structure.md` for the full repo map
- Treat all scripts as production‑safe starting points and extend them for your environment

## 📝 Notes

- Folder names are lowercase for consistency
- Scripts are grouped by real production DBA use cases
- Lab/test scripts are intentionally separate
- `docs/` contains runbooks, templates, and operational notes

## 📥 Clone the Repository

```bash
git clone https://github.com/peterwhyte-lgtm/dba-scripts
```
