# PowerShell layer

Automation, orchestration, and thin wrappers for the repo's SQL scripts. See `docs/standards.md` for header and classification rules.

## Layout

```text
powershell/
  wrappers/
    monitoring/       — thin wrappers for sql/monitoring/ scripts
    performance/      — thin wrappers for sql/performance/ scripts
    backups/          — backup health queries + DDL generators (full, diff, tlog, restore scripts)
    security/         — thin wrappers for sql/security/ scripts
    high-availability/ — thin wrappers for sql/high-availability/ scripts
    maintenance/      — wrappers for sql/maintenance/ DDL generators (backup/index/maintenance jobs)
    migration/        — thin wrappers for sql/migration/ scripts

  reporting/          — Invoke-HealthCheckCollection, Review-HealthCheckOutput, Invoke-AssessmentReport
  reporting/multi-server/ — MultiServer-Get*.ps1 fleet scripts (disk, wait stats, patch level, etc.)

  disk-space/         — Get-DiskSpaceSummary, Get-LargestFolders, Get-OldestBackupFolderFiles, Get-BackupAge

  migration/          — DDL generators (Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript,
                        Generate-LinkedServerScript, Generate-RestoreWithMoveScript)
                        Orchestrators (Invoke-MigrationExport, Invoke-PreMigrationAssessment, Export-MigrationBaseline)
                        Inventory (Get-DatabaseInventory, Get-LoginInventory, Get-JobInventory, Get-MigrationRiskAssessment)

  installation/       — install-sql.ps1, configure-sql.ps1, pre-install-check.ps1, post-install-validation.ps1,
                        uninstall-sql.ps1, generate-install-report.ps1

  patching/           — patch-summary.ps1
    sql/              — Invoke-SqlPatch.ps1, patch-config.psd1
    ssms/             — install-ssms.ps1, uninstall-ssms.ps1

  collectors/         — collector .sql queries for ad-hoc use; Collect-*.ps1 being migrated to SQL Agent jobs
                        (see sql/collectors/ for the job DDL generators)
```

## Key rules

- **Wrappers** (`powershell/wrappers/<category>/`) are 3 levels from repo root → `$PSScriptRoot '..\..\..'`
- **Orchestrators** (`powershell/<subfolder>/`) are 2 levels from repo root → `$PSScriptRoot '..\..'`
- Every wrapper delegates to `tools\local-sql\Invoke-RepoSql.ps1` — no direct `Invoke-Sqlcmd` calls
- Every `.ps1` needs a `.NOTES` block with `ScriptType`, `TargetScope`, `RiskLevel`, `Purpose`
- Web UI shows a SQL script only if it has a matching wrapper in `powershell/wrappers/<same-category>/`

## Adding a new wrapper

```powershell
.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\<category>\Get-Something.sql
```

Or copy an existing wrapper from the matching category folder and update the three path variables.
