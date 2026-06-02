<#
Script Name : MultiServer-GetFirewallRules
Category    : multi-server-scripts/powershell
Purpose     : List Windows Firewall rules across multiple remote hosts via WinRM.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : WinRM on target hosts (Enable-PSRemoting -Force on each target).
              NetSecurity module (standard on Windows Server 2012+).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [string]$DisplayNameLike = '*',

    [ValidateSet('True','False','All')]
    [string]$Enabled = 'All',

    [ValidateSet('Inbound','Outbound','All')]
    [string]$Direction = 'Inbound',

    [PSCredential]$Credential,
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
