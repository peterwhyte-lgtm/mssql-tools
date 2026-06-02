<#
Script Name : MultiServer-RestartService
Category    : multi-server-scripts/powershell
Purpose     : Restart a named Windows service on multiple remote hosts via WinRM.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : WRITE — restarts the named service on each target host
Impact      : High (causes a service interruption on each target)
Requires    : WinRM on target hosts (Enable-PSRemoting -Force as admin on each target).
              Admin rights on target hosts.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [Parameter(Mandatory)]
    [string]$ServiceName,

    [PSCredential]$Credential,
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
