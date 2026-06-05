<#
Script Name : MultiServer-GetDiskSpace
Category    : multi-server-scripts/powershell
Purpose     : Check disk space on multiple remote hosts using CIM. Flags volumes below configurable thresholds.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : WinRM on target hosts (Get-CimInstance uses WinRM by default in PS7+).
Params      : -Servers "SVR01,SVR02"   Required. Comma-separated hostnames or IPs.
              -WarnBelowPctFree 20     Flag volumes below this % free. Default: 20.
              -CritBelowPctFree 10     Critical below this % free. Default: 10.
              -Credential              Alternate PSCredential.
              -Parallel                Run all servers simultaneously (PS7+).
Output      : Server, Drive, Label, TotalGB, UsedGB, FreeGB, FreePct, Status
Example     : .\MultiServer-GetDiskSpace.ps1 -Servers "SVR01,SVR02,SVR03" -WarnBelowPctFree 15
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [int]$WarnBelowPctFree = 20,
    [int]$CritBelowPctFree = 10,
    [PSCredential]$Credential,
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
