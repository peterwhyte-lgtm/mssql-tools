<#
Script Name : MultiServer-RestartService
Category    : multi-server-queries/powershell
Purpose     : Restart a named Windows service on multiple remote hosts via WinRM.
              Reports previous state, new state, and any error per server.
              Self-contained — copy this file and run it from any PowerShell session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : WRITE — restarts the named service on each target host
Impact      : High (causes a service interruption on each target)
Requires    : WinRM enabled on target hosts (run Enable-PSRemoting -Force as admin on each target)
              Admin rights on target hosts

Parameters:
  -Servers       Required. Comma-separated hostnames or IPs: "SVR01,SVR02,SVR03"
  -ServiceName   Required. Windows service name to restart.
                 Use the short service name, not the display name.
                 Examples: MSSQLSERVER, SQLSERVERAGENT, SQLBROWSER, W3SVC
  -Credential    Optional. PSCredential for alternate or non-domain auth.
                 If omitted, uses the current Windows identity (pass-through auth).
  -WhatIf        Show what would happen without restarting anything.
  -Parallel      Run against all servers simultaneously instead of one at a time.
                 Requires PowerShell 7+. Output may be interleaved.
                 Default: sequential (safer, cleaner output).

Usage examples:
  # Restart SQL Server Agent on three hosts
  .\MultiServer-RestartService.ps1 -Servers "SVR01,SVR02,SVR03" -ServiceName SQLSERVERAGENT

  # Preview what would happen without doing it
  .\MultiServer-RestartService.ps1 -Servers "SVR01,SVR02" -ServiceName MSSQLSERVER -WhatIf

  # Use alternate credentials
  $cred = Get-Credential
  .\MultiServer-RestartService.ps1 -Servers "SVR01,SVR02" -ServiceName MSSQLSERVER -Credential $cred

  # Run in parallel against many servers
  .\MultiServer-RestartService.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05" -ServiceName W3SVC -Parallel
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    # Comma-separated list of target hostnames or IP addresses
    [Parameter(Mandatory)]
    [string]$Servers,

    # Windows service name (short name, not display name): MSSQLSERVER, SQLSERVERAGENT, W3SVC, etc.
    [Parameter(Mandatory)]
    [string]$ServiceName,

    # Alternate credentials for WinRM auth — omit to use current Windows identity
    [PSCredential]$Credential,

    # Run against all servers simultaneously (PS7+). Sequential is default.
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'
$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

if ($serverList.Count -eq 0) {
    Write-Error "-Servers contained no valid hostnames."
    exit 1
}

$scriptBlock = {
    param($svcName)
    try {
        $svc      = Get-Service -Name $svcName -ErrorAction Stop
        $prevState = $svc.Status
        Restart-Service -Name $svcName -Force -ErrorAction Stop
        $newState  = (Get-Service -Name $svcName).Status
        [PSCustomObject]@{
            Server    = $env:COMPUTERNAME
            Service   = $svcName
            WasState  = $prevState
            NowState  = $newState
            Result    = 'Restarted'
            Error     = ''
        }
    } catch {
        [PSCustomObject]@{
            Server    = $env:COMPUTERNAME
            Service   = $svcName
            WasState  = 'Unknown'
            NowState  = 'Unknown'
            Result    = 'Failed'
            Error     = $_.Exception.Message
        }
    }
}

$baseInvoke = @{ ScriptBlock = $scriptBlock; ArgumentList = $ServiceName }
if ($Credential) { $baseInvoke.Credential = $Credential }

$results = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Running in parallel against $($serverList.Count) server(s)..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        $srv  = $_
        $ip   = @{ ScriptBlock = $using:scriptBlock; ArgumentList = $using:ServiceName; ComputerName = $srv; ErrorAction = 'Stop' }
        if ($using:Credential) { $ip.Credential = $using:Credential }
        try   { Invoke-Command @ip }
        catch { [PSCustomObject]@{ Server = $srv; Service = $using:ServiceName; WasState = ''; NowState = ''; Result = 'Failed'; Error = $_.Message } }
    } -ThrottleLimit 10 | ForEach-Object { $results.Add($_) }
} else {
    foreach ($server in $serverList) {
        if (-not $PSCmdlet.ShouldProcess($server, "Restart service '$ServiceName'")) { continue }
        Write-Host "`n→ $server" -ForegroundColor Cyan
        try {
            $r = Invoke-Command -ComputerName $server @baseInvoke -ErrorAction Stop
            $results.Add($r)
            $clr = if ($r.Result -eq 'Restarted') { 'Green' } else { 'Red' }
            Write-Host ("  [{0}]  {1}  {2} → {3}" -f $r.Result, $ServiceName, $r.WasState, $r.NowState) -ForegroundColor $clr
        } catch {
            Write-Warning "$server : $_"
            $results.Add([PSCustomObject]@{ Server = $server; Service = $ServiceName; WasState = ''; NowState = ''; Result = 'Failed'; Error = $_.Message })
        }
    }
}

Write-Host "`n── Summary ──────────────────────────────────────────────" -ForegroundColor DarkGray
$results | Format-Table Server, Service, WasState, NowState, Result, Error -AutoSize
