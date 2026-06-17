# Tools

Repo support utilities for local execution, triage, scaffolding, and maintenance.

## Layout

- **local-sql/** — core runner (`Invoke-RepoSql.ps1`), connection helper (`Set-SqlConnection.ps1`), connectivity check (`Test-SqlConnectivity.ps1`)
- **triage/** — repo inventory and standards validation (`Show-RepoOverview.ps1`, `Find-UsefulScript.ps1`, `Get-StandardsAudit.ps1`)
- **scaffolding/** — new script and wrapper generation (`New-Wrapper.ps1`, `New-MultiServerScript.ps1`)
- **maintenance/** — output cleanup (`Clear-OutputFiles.ps1`)

## Common commands

```powershell
# Run any script by fuzzy name — searches powershell/, sql/, tools/
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01 -OutputFormat Csv

# Verify SQL connectivity before running scripts
.\tools\local-sql\Test-SqlConnectivity.ps1 -ServerInstance .

# Set a session-level target server (avoids repeating -ServerInstance)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

# Discover scripts by keyword
.\tools\triage\Find-UsefulScript.ps1 -Keyword blocking

# Inventory the repo — script counts by category
.\tools\triage\Show-RepoOverview.ps1

# Validate SQL headers and PS .NOTES blocks across the repo
.\tools\triage\Get-StandardsAudit.ps1

# Generate a wrapper for a new SQL script
.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\performance\Get-Something.sql

# Clear generated output before a fresh run
.\tools\maintenance\Clear-OutputFiles.ps1
```
