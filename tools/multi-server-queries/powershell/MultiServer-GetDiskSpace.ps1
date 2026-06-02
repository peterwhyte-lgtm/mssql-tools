<#
Script Name : MultiServer-GetDiskSpace
Category    : multi-server-queries/powershell
Purpose     : Check disk space on multiple remote hosts using WMI/CIM.
              Flags volumes below a configurable free percentage threshold.
              Does not require WinRM — uses CIM over DCOM (port 135 + dynamic ports).
              Self-contained — copy this file and run it from any PowerShell session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : WMI/CIM access on target hosts (no WinRM required — uses DCOM).
              Port 135 and dynamic high ports (RPC) must be accessible on targets.

Parameters:
  -Servers            Required. Comma-separated hostnames or IPs: "SVR01,SVR02,SVR03"
  -WarnBelowPctFree   Highlight volumes below this percentage free. Default: 20.
  -CritBelowPctFree   Mark volumes as CRITICAL below this percentage free. Default: 10.
  -Credential         Optional. PSCredential for alternate auth.
  -Parallel           Run against all servers simultaneously (PS7+). Default: sequential.

Usage examples:
  # Disk space across five servers
  .\MultiServer-GetDiskSpace.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05"

  # Custom thresholds
  .\MultiServer-GetDiskSpace.ps1 -Servers "SVR01,SVR02" -WarnBelowPctFree 30 -CritBelowPctFree 15
#>

[CmdletBinding()]
param (
    # Comma-separated list of target hostnames or IPs
    [Parameter(Mandatory)]
    [string]$Servers,

    # Warn if free percentage is below this value
    [int]$WarnBelowPctFree = 20,

    # Critical if free percentage is below this value
    [int]$CritBelowPctFree = 10,

    # Alternate credentials for CIM connection — omit to use current Windows identity
    [PSCredential]$Credential,

    # Run against all servers simultaneously (PS7+). Sequential is default.
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'
$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

function Get-DiskFromHost([string]$server) {
    try {
        $cimParams = @{ ClassName = 'Win32_LogicalDisk'; Filter = "DriveType=3"; ErrorAction = 'Stop' }
        if ($server -ne '.' -and $server -ne 'localhost') { $cimParams.ComputerName = $server }
        if ($Credential) { $cimParams.Credential = $Credential }

        $disks = Get-CimInstance @cimParams
        foreach ($d in $disks) {
            $totalGb = [Math]::Round($d.Size          / 1GB, 2)
            $freeGb  = [Math]::Round($d.FreeSpace      / 1GB, 2)
            $usedGb  = [Math]::Round(($d.Size - $d.FreeSpace) / 1GB, 2)
            $pctFree = if ($d.Size -gt 0) { [Math]::Round(100.0 * $d.FreeSpace / $d.Size, 1) } else { 0 }
            $status  = if ($pctFree -lt $CritBelowPctFree) { 'CRITICAL' } `
                       elseif ($pctFree -lt $WarnBelowPctFree) { 'WARNING' } `
                       else { 'OK' }
            [PSCustomObject]@{
                Server     = $server
                Drive      = $d.DeviceID
                Label      = $d.VolumeName
                TotalGB    = $totalGb
                UsedGB     = $usedGb
                FreeGB     = $freeGb
                FreePct    = $pctFree
                Status     = $status
                Error      = ''
            }
        }
    } catch {
        [PSCustomObject]@{
            Server = $server; Drive = ''; Label = ''; TotalGB = 0; UsedGB = 0;
            FreeGB = 0; FreePct = 0; Status = 'ERROR'; Error = $_.Exception.Message
        }
    }
}

$results = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        $srv   = $_
        $wPct  = $using:WarnBelowPctFree
        $cPct  = $using:CritBelowPctFree
        $cr    = $using:Credential
        try {
            $p = @{ ClassName = 'Win32_LogicalDisk'; Filter = 'DriveType=3'; ErrorAction = 'Stop' }
            if ($srv -ne '.' -and $srv -ne 'localhost') { $p.ComputerName = $srv }
            if ($cr) { $p.Credential = $cr }
            foreach ($d in (Get-CimInstance @p)) {
                $tg = [Math]::Round($d.Size / 1GB, 2)
                $fg = [Math]::Round($d.FreeSpace / 1GB, 2)
                $ug = [Math]::Round(($d.Size - $d.FreeSpace) / 1GB, 2)
                $pf = if ($d.Size -gt 0) { [Math]::Round(100.0 * $d.FreeSpace / $d.Size, 1) } else { 0 }
                $st = if ($pf -lt $cPct) { 'CRITICAL' } elseif ($pf -lt $wPct) { 'WARNING' } else { 'OK' }
                [PSCustomObject]@{ Server = $srv; Drive = $d.DeviceID; Label = $d.VolumeName; TotalGB = $tg; UsedGB = $ug; FreeGB = $fg; FreePct = $pf; Status = $st; Error = '' }
            }
        } catch {
            [PSCustomObject]@{ Server = $srv; Drive = ''; Label = ''; TotalGB = 0; UsedGB = 0; FreeGB = 0; FreePct = 0; Status = 'ERROR'; Error = $_.Message }
        }
    } -ThrottleLimit 10 | ForEach-Object { $results.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n→ $server" -ForegroundColor Cyan
        $rows = @(Get-DiskFromHost $server)
        foreach ($r in $rows) {
            $clr = switch ($r.Status) { 'CRITICAL' { 'Red' } 'WARNING' { 'Yellow' } 'ERROR' { 'Red' } default { 'Green' } }
            Write-Host ("  [{0,-8}] {1}  {2} GB free of {3} GB ({4}%)" -f $r.Status, $r.Drive, $r.FreeGB, $r.TotalGB, $r.FreePct) -ForegroundColor $clr
            $results.Add($r)
        }
    }
}

Write-Host "`n── All volumes ──────────────────────────────────────────" -ForegroundColor DarkGray
$results | Sort-Object Server, FreePct | Format-Table Server, Drive, Label, TotalGB, UsedGB, FreeGB, FreePct, Status, Error -AutoSize
