<#
Script Name : MultiServer-GetFirewallRules
Category    : multi-server-queries/powershell
Purpose     : List Windows Firewall rules across multiple remote hosts.
              Useful for auditing port 1433 (SQL Server), port 80/443 (IIS), or any
              custom rule across an estate. Runs the firewall cmdlets on the remote
              host via Invoke-Command (WinRM required).
              Self-contained — copy this file and run it from any PowerShell session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : WinRM enabled on target hosts (Enable-PSRemoting -Force on each target).
              The NetSecurity module must be present (standard on Windows Server 2012+).

Parameters:
  -Servers         Required. Comma-separated hostnames or IPs: "SVR01,SVR02,SVR03"
  -DisplayNameLike Optional wildcard filter on rule display name: "*SQL*", "*Remote*"
                   Default: no filter (returns all non-trivial rules).
  -Enabled         Filter by enabled state: True | False | All. Default: All.
  -Direction       Filter by direction: Inbound | Outbound | All. Default: Inbound.
  -Credential      Optional. PSCredential for alternate auth.
  -Parallel        Run against all servers simultaneously (PS7+). Default: sequential.

Usage examples:
  # All inbound firewall rules on three servers
  .\MultiServer-GetFirewallRules.ps1 -Servers "SVR01,SVR02,SVR03"

  # Rules matching SQL, both directions
  .\MultiServer-GetFirewallRules.ps1 -Servers "SVR01,SVR02" -DisplayNameLike "*SQL*" -Direction All

  # Only enabled rules
  .\MultiServer-GetFirewallRules.ps1 -Servers "SVR01,SVR02,SVR03" -Enabled True
#>

[CmdletBinding()]
param (
    # Comma-separated list of target hostnames or IPs
    [Parameter(Mandatory)]
    [string]$Servers,

    # Wildcard filter on rule display name — e.g. "*SQL*", "*Remote Desktop*"
    [string]$DisplayNameLike = '*',

    # Filter by enabled state: True, False, or All
    [ValidateSet('True','False','All')]
    [string]$Enabled = 'All',

    # Filter by traffic direction: Inbound, Outbound, or All
    [ValidateSet('Inbound','Outbound','All')]
    [string]$Direction = 'Inbound',

    # Alternate credentials — omit to use current Windows identity
    [PSCredential]$Credential,

    # Run against all servers simultaneously (PS7+). Sequential is default.
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'
$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

$scriptBlock = {
    param($nameLike, $enabledFilter, $dirFilter)
    try {
        $params = @{ DisplayName = $nameLike }
        if ($enabledFilter -ne 'All') { $params.Enabled  = [bool]::Parse($enabledFilter) }
        if ($dirFilter     -ne 'All') { $params.Direction = $dirFilter }

        $rules = Get-NetFirewallRule @params -ErrorAction Stop |
            Where-Object { $_.DisplayName -ne '' }

        foreach ($r in $rules) {
            # Get port filter details where available
            $portInfo = try { $r | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue } catch { $null }
            [PSCustomObject]@{
                Server      = $env:COMPUTERNAME
                DisplayName = $r.DisplayName
                Direction   = $r.Direction
                Enabled     = $r.Enabled
                Action      = $r.Action
                Protocol    = if ($portInfo) { $portInfo.Protocol } else { '' }
                LocalPort   = if ($portInfo) { $portInfo.LocalPort -join ',' } else { '' }
                Profile     = $r.Profile
                Error       = ''
            }
        }
    } catch {
        [PSCustomObject]@{
            Server = $env:COMPUTERNAME; DisplayName = ''; Direction = ''; Enabled = '';
            Action = ''; Protocol = ''; LocalPort = ''; Profile = ''; Error = $_.Exception.Message
        }
    }
}

$invokeParams = @{ ScriptBlock = $scriptBlock; ArgumentList = $DisplayNameLike, $Enabled, $Direction }
if ($Credential) { $invokeParams.Credential = $Credential }

$results = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        $srv = $_
        $ip  = @{ ScriptBlock = $using:scriptBlock; ArgumentList = $using:DisplayNameLike, $using:Enabled, $using:Direction; ComputerName = $srv }
        if ($using:Credential) { $ip.Credential = $using:Credential }
        try   { Invoke-Command @ip }
        catch { [PSCustomObject]@{ Server = $srv; DisplayName = ''; Direction = ''; Enabled = ''; Action = ''; Protocol = ''; LocalPort = ''; Profile = ''; Error = $_.Message } }
    } -ThrottleLimit 10 | ForEach-Object { $results.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n→ $server" -ForegroundColor Cyan
        try {
            $rows = Invoke-Command -ComputerName $server @invokeParams -ErrorAction Stop
            foreach ($r in $rows) { $results.Add($r) }
            Write-Host "  $($rows.Count) rule(s) matched" -ForegroundColor DarkGray
        } catch {
            Write-Warning "$server : $_"
        }
    }
}

Write-Host "`n── All rules ────────────────────────────────────────────" -ForegroundColor DarkGray
$results | Sort-Object Server, Direction, DisplayName |
    Format-Table Server, Direction, Enabled, Action, Protocol, LocalPort, DisplayName -AutoSize
