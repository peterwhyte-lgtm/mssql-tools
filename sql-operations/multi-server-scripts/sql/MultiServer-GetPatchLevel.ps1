<#
Script Name : MultiServer-GetPatchLevel
Category    : multi-server-scripts/sql
Purpose     : Reports SQL Server version, CU level, and edition across multiple instances.
              Use to build a patch compliance inventory across the estate.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : SqlServer PowerShell module.
              Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force
Params      : -Servers "SVR01,SVR02"   Required. Comma-separated SQL Server instances.
              -SqlAuth                  Prompt for SQL credentials instead of Windows auth.
              -Parallel                 Run all servers simultaneously (PS7+).
              -OutCsv path.csv         Save full results to CSV.
Output      : server_name, version_friendly, product_update_level, product_version,
              edition, resource_db_updated, patch_summary
              Compare product_version against https://sqlserverupdates.com for latest CU.
Example     : .\MultiServer-GetPatchLevel.ps1 -Servers "SVR01,SVR02,SVR03" -Parallel
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [switch]$SqlAuth,
    [switch]$Parallel,
    [string]$OutCsv
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -Name SqlServer -ListAvailable)) {
    Write-Host ''
    Write-Host '  The SqlServer module is required.' -ForegroundColor Yellow
    Write-Host '  Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force' -ForegroundColor Cyan
    Write-Host ''
    exit 1
}

Import-Module SqlServer -ErrorAction Stop

$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

$credential = $null
if ($SqlAuth) {
    $credential = Get-Credential -Message "SQL Server credentials for: $($serverList -join ', ')"
}

$sql = @"
DECLARE @v varchar(20) = CAST(SERVERPROPERTY('ProductVersion') AS varchar(20));
DECLARE @m int         = CAST(PARSENAME(@v, 4) AS int);
SELECT
    @@SERVERNAME AS server_name,
    @v AS product_version,
    CASE @m
        WHEN 16 THEN 'SQL Server 2022'
        WHEN 15 THEN 'SQL Server 2019'
        WHEN 14 THEN 'SQL Server 2017'
        WHEN 13 THEN 'SQL Server 2016'
        WHEN 12 THEN 'SQL Server 2014'
        WHEN 11 THEN 'SQL Server 2012'
        ELSE 'SQL Server (ver ' + CAST(@m AS varchar(5)) + ')'
    END AS version_friendly,
    CAST(SERVERPROPERTY('ProductUpdateLevel') AS varchar(20))    AS product_update_level,
    CAST(SERVERPROPERTY('ProductLevel')       AS varchar(20))    AS product_level,
    CAST(SERVERPROPERTY('ProductUpdateReference') AS varchar(30)) AS kb_reference,
    CAST(SERVERPROPERTY('Edition')            AS varchar(128))   AS edition,
    CAST(SERVERPROPERTY('ResourceLastUpdateDateTime') AS datetime) AS resource_db_updated,
    CASE @m WHEN 16 THEN 'SQL Server 2022' WHEN 15 THEN 'SQL Server 2019'
            WHEN 14 THEN 'SQL Server 2017' WHEN 13 THEN 'SQL Server 2016'
            WHEN 12 THEN 'SQL Server 2014' WHEN 11 THEN 'SQL Server 2012'
            ELSE 'SQL Server' END
    + ' ' + ISNULL(CAST(SERVERPROPERTY('ProductUpdateLevel') AS varchar(20)),
                   CAST(SERVERPROPERTY('ProductLevel') AS varchar(20)))
    + ' (' + @v + ')' AS patch_summary;
"@

function Get-PatchInfo([string]$server) {
    try {
        $params = @{
            ServerInstance         = $server
            Database               = 'master'
            Query                  = $sql
            TrustServerCertificate = $true
            OutputAs               = 'DataTables'
            ErrorAction            = 'Stop'
        }
        if ($credential) {
            $params.Username = $credential.UserName
            $params.Password = $credential.GetNetworkCredential().Password
        }
        $result = Invoke-Sqlcmd @params
        if ($result) { $result | Select-Object *, @{n='_Server'; e={ $server }} }
    } catch {
        [PSCustomObject]@{
            _Server = $server; server_name = $server; patch_summary = "ERROR: $($_.Exception.Message)"
            product_version = ''; version_friendly = ''; product_update_level = ''
            edition = ''; resource_db_updated = $null
        }
    }
}

$allResults = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        Import-Module SqlServer -ErrorAction SilentlyContinue
        $srv = $_; $q = $using:sql; $cr = $using:credential
        try {
            $p = @{ ServerInstance = $srv; Database = 'master'; Query = $q;
                    TrustServerCertificate = $true; OutputAs = 'DataTables'; ErrorAction = 'Stop' }
            if ($cr) { $p.Username = $cr.UserName; $p.Password = $cr.GetNetworkCredential().Password }
            $r = Invoke-Sqlcmd @p
            if ($r) { $r | Select-Object *, @{n='_Server'; e={ $srv }} }
        } catch {
            [PSCustomObject]@{ _Server = $srv; server_name = $srv; patch_summary = "ERROR: $($_.Message)"
                product_version = ''; version_friendly = ''; product_update_level = ''; edition = '' }
        }
    } -ThrottleLimit 10 | ForEach-Object { $allResults.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n=== $server ===" -ForegroundColor Cyan
        $rows = @(Get-PatchInfo $server)
        foreach ($r in $rows) { $allResults.Add($r) }
        $rows | Format-Table version_friendly, product_update_level, product_version, edition -AutoSize
    }
}

if ($allResults.Count -gt 0) {
    if ($Parallel) {
        Write-Host "`n── Patch level summary (sorted by version) ──────────────" -ForegroundColor DarkGray
        $allResults | Sort-Object version_friendly, product_version |
            Format-Table _Server, version_friendly, product_update_level, product_version, edition -AutoSize
    }
    if ($OutCsv) {
        $allResults | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
        Write-Host "Saved to $OutCsv" -ForegroundColor Green
    }
}

Write-Host "`nDone. Compare product_version against https://sqlserverupdates.com for latest CU." -ForegroundColor DarkGray
