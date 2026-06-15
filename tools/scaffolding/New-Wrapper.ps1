<#
.SYNOPSIS
Generates a thin PS wrapper for a SQL script in powershell/<category>/.

.DESCRIPTION
Given a path to a .sql file in sql/ or sql/migration/,
generates the matching wrapper PS1 in powershell/<category>/ and opens it for review.

The wrapper follows the repo standard: resolves repoRoot two levels up, builds the SQL
path, validates both files exist, then delegates to Invoke-RepoSql.ps1.

.PARAMETER SqlPath
Relative or absolute path to the .sql file. Category is inferred from the path.

.PARAMETER Force
Overwrite an existing wrapper without prompting.

.EXAMPLE
.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\monitoring\Get-Something.sql

.EXAMPLE
.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\migration\Get-MigrationThing.sql

.NOTES
Type      : runner
Scope     : local
RiskLevel : SAFE
#>
param(
    [Parameter(Mandatory)]
    [string]$SqlPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

# ── Resolve the SQL file ──────────────────────────────────────────────────────
$absPath = if ([System.IO.Path]::IsPathRooted($SqlPath)) {
    $SqlPath
} else {
    Join-Path $repoRoot $SqlPath
}

if (-not (Test-Path -LiteralPath $absPath)) {
    throw "SQL script not found: $absPath"
}

$sqlFile = Get-Item -LiteralPath $absPath
$relPath = $sqlFile.FullName.Replace($repoRoot.Path + '\', '').Replace('\', '/')

# ── Determine category and sql-path string for the wrapper body ───────────────
$isMigration = $relPath -match '^sql/migration/'
$category    = if ($isMigration) {
    'migration'
} elseif ($relPath -match '^sql/([^/]+)/') {
    $Matches[1]
} else {
    throw "Cannot determine category from path: $relPath`nExpected: sql/<cat>/ or sql/migration/"
}

$sqlRelForBody = $relPath.Replace('/', '\')   # backslash for Join-Path in the wrapper

# ── Derive names ──────────────────────────────────────────────────────────────
$name    = $sqlFile.BaseName
$outDir  = Join-Path $repoRoot "powershell\wrappers\$category"
$outFile = Join-Path $outDir "$name.ps1"

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if ((Test-Path -LiteralPath $outFile) -and -not $Force) {
    throw "Wrapper already exists: $outFile`nUse -Force to overwrite."
}

# ── Read Purpose from SQL header ──────────────────────────────────────────────
$purpose = Get-Content $absPath -ErrorAction SilentlyContinue |
    Where-Object { $_ -match '^\s*Purpose\s*:' } |
    Select-Object -First 1 |
    ForEach-Object { ($_ -replace '^\s*Purpose\s*:\s*', '').Trim() }
if (-not $purpose) { $purpose = "Run $name against a SQL Server instance." }

# ── Emit wrapper ──────────────────────────────────────────────────────────────
$needsDb = $sqlFile.Name -notmatch '^(Get-Disk|Get-Os|Get-Patch|Get-Server|Get-Version|MultiServer)'
$dbParam = if ($needsDb) { "`n    [string]`$Database       = 'master'," } else { '' }
$dbArg   = if ($needsDb) { " -Database `$Database" } else { '' }

$content = @"
<#
.SYNOPSIS
$purpose

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : $purpose

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or `$env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\run.ps1 $name

.EXAMPLE
.\powershell\wrappers\$category\$name.ps1 -ServerInstance PROD01\SQL2019 -OutputFormat Csv
#>

param(
    [string]`$ServerInstance = '.',$dbParam
    [ValidateSet('Table', 'Csv')]
    [string]`$OutputFormat   = 'Table',
    [string]`$OutputPath
)

`$ErrorActionPreference = 'Stop'

`$repoRoot  = Resolve-Path (Join-Path `$PSScriptRoot '..\..\..')
`$sqlScript = Join-Path `$repoRoot '$sqlRelForBody'
`$runner    = Join-Path `$repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (`$ServerInstance -eq '.' -and `$env:DBASCRIPTS_SERVER) { `$ServerInstance = `$env:DBASCRIPTS_SERVER }

if (-not (Test-Path -LiteralPath `$sqlScript)) { throw "SQL script not found: `$sqlScript" }
if (-not (Test-Path -LiteralPath `$runner))    { throw "Runner not found: `$runner" }

Write-Host 'Running $name...' -ForegroundColor Cyan
& `$runner -ScriptPath `$sqlScript -ServerInstance `$ServerInstance$dbArg ``
          -OutputFormat `$OutputFormat -OutputPath `$OutputPath
"@

Set-Content -Path $outFile -Value $content -Encoding UTF8
Write-Host "Created: powershell\wrappers\$category\$name.ps1" -ForegroundColor Green
Write-Host "Review and adjust the -Database default if needed." -ForegroundColor DarkGray
