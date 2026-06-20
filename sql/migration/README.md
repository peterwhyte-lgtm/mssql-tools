# Migration SQL area

This folder is the canonical SQL home for migration-focused inventory and readiness checks.

Use these scripts before database moves, upgrades, or estate refreshes.

**Assessment and risk:**
- `Get-MigrationRiskAssessment.sql` — comprehensive pre-migration risk scan; returns HIGH/MEDIUM/INFO findings for compat levels, database settings, linked servers, AG membership, and sizing
- `Get-DeprecatedFeaturesInUse.sql` — deprecated features with active usage since last restart (cntr_value > 0 only)
- `Get-CompatibilityLevelAudit.sql` — all databases with compat level, mapped SQL version name, and instance native compat
- `Get-MigrationLoginAudit.sql` — server principals with per-type migration risk and action guidance

**Inventory:**
- `Get-DatabaseInventory.sql` — database inventory and compatibility details
- `Get-LoginInventory.sql` — server login inventory and disabled-state review
- `Get-JobInventory.sql` — SQL Agent job inventory for dependency checks
- `Get-LinkedServerInventory.sql` — linked server inventory for connection review

**DDL generators** (do not run through Invoke-RepoSql.ps1 — use Generate-*.ps1 wrappers directly):
- `Generate-LoginScript.sql` — scripts logins with SID preservation
- `Generate-AgentJobScript.sql` — scripts all SQL Agent jobs
- `Generate-UserMappingScript.sql` — scripts database user-to-login mappings

**Orchestration:**
- `powershell/migration/Invoke-PreMigrationAssessment.ps1` — runs all assessment scripts, saves to output-files/migration/assessment/
- `powershell/migration/Export-MigrationBaseline.ps1` — captures pre/post baseline for comparison
