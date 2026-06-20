#Requires -Modules Pester

<#
Pester tests for tools/scaffolding/New-MultiServerScript.ps1

Tests cover the PS remoting path entirely (no SQL Server dependency) and the
input validation / here-string guard for SQL files. SQL generation tests that
require the SqlServer module are tagged 'RequiresSqlServer' and skipped in CI
unless the module is available.

Run from repo root:
    Invoke-Pester tests/New-MultiServerScript.Tests.ps1
#>

$generator  = (Resolve-Path "$PSScriptRoot\..\tools\scaffolding\New-MultiServerScript.ps1").Path
$hasSqlMod  = $null -ne (Get-Module -Name SqlServer -ListAvailable -ErrorAction SilentlyContinue)

# Use a real temp path — $TestDrive is only available inside Describe in Pester v3
$testTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-dba-$([System.Diagnostics.Process]::GetCurrentProcess().Id)"
$null = New-Item -ItemType Directory -Force -Path $testTempDir
$psSource = Join-Path $testTempDir 'sample.ps1'
Set-Content -Path $psSource -Value 'Write-Host "hello from $env:COMPUTERNAME"' -Encoding UTF8

function Invoke-Generator {
    param([hashtable]$Params)
    $out = Join-Path $testTempDir ([System.IO.Path]::GetRandomFileName() + '.ps1')
    & $generator @Params -OutputFile $out
    Get-Content $out -Raw
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

Describe 'Input validation' {

    It 'errors on a missing ScriptPath' {
        $threw = $false
        try { & $generator -ScriptPath 'C:\does\not\exist.ps1' -Servers 'SVR01' } catch { $threw = $true }
        $threw | Should -Be $true
    }

    It 'errors on an unsupported file extension' {
        $f = New-Item (Join-Path $TestDrive 'test.txt') -ItemType File -Value 'hello'
        $threw = $false
        try { & $generator -ScriptPath $f.FullName -Servers 'SVR01' } catch { $threw = $true }
        $threw | Should -Be $true
    }

    It 'errors on an empty Servers string' {
        $threw = $false
        try { & $generator -ScriptPath $psSource -Servers '  ,  ,  ' } catch { $threw = $true }
        $threw | Should -Be $true
    }

    It 'does not throw when valid inputs are provided' {
        { Invoke-Generator @{ ScriptPath = $psSource; Servers = 'SVR01' } } | Should -Not -Throw
    }
}

# ---------------------------------------------------------------------------
# SQL here-string guard
# ---------------------------------------------------------------------------

Describe 'SQL here-string guard' {

    It "throws when SQL contains a line starting with '@ (would terminate the here-string)" {
        $bad = Join-Path $TestDrive 'bad.sql'
        # Newline followed by '@ at column 0 — the here-string terminator
        Set-Content -Path $bad -Value "SELECT 1`r`n'@`r`nSELECT 2" -Encoding UTF8 -NoNewline:$false
        # Guard fires before the SqlServer module check so this works without the module
        { & $generator -ScriptPath $bad -Servers 'SVR01' } | Should -Throw "here-string"
    }

    It 'does not throw for SQL without the terminator pattern' -Skip:(-not $hasSqlMod) {
        $ok = Join-Path $TestDrive 'ok.sql'
        Set-Content -Path $ok -Value "SELECT 1 AS n" -Encoding UTF8
        { Invoke-Generator @{ ScriptPath = $ok; Servers = 'SVR01' } } | Should -Not -Throw
    }
}

# ---------------------------------------------------------------------------
# PS remoting — sequential generation
# ---------------------------------------------------------------------------

Describe 'PS remoting — sequential (default)' {

    BeforeAll {
        $script:content = Invoke-Generator @{ ScriptPath = $psSource; Servers = 'SVR01,SVR02' }
    }

    It 'embeds both server names in the $servers array' {
        $content | Should -Match "'SVR01'"
        $content | Should -Match "'SVR02'"
    }

    It 'embeds the source script in a $scriptBlock variable' {
        $content | Should -Match ([regex]::Escape('$scriptBlock = {'))
    }

    It 'uses a sequential foreach loop, not parallel' {
        $content | Should -Match 'foreach \(\$server in \$servers\)'
        $content | Should -Not -Match 'ForEach-Object -Parallel'
    }

    It 'includes the optional credential template' {
        $content | Should -Match '\$credential = \$null'
        $content | Should -Match 'Get-Credential'
    }

    It 'splats Invoke-Command with a credential guard' {
        $content | Should -Match 'if \(\$credential\)'
        $content | Should -Match 'Invoke-Command @ic'
    }

    It 'outputs the generated script to the OutputFile' {
        $out = Join-Path $TestDrive 'explicit-out.ps1'
        & $generator -ScriptPath $psSource -Servers 'SVR01' -OutputFile $out
        Test-Path $out | Should -Be $true
        (Get-Content $out -Raw).Length | Should -BeGreaterThan 100
    }
}

# ---------------------------------------------------------------------------
# PS remoting — parallel generation
# ---------------------------------------------------------------------------

Describe 'PS remoting — parallel' {

    BeforeAll {
        $script:content = Invoke-Generator @{
            ScriptPath    = $psSource
            Servers       = 'SVR01,SVR02,SVR03'
            Parallel      = $true
            ThrottleLimit = 7
        }
    }

    It 'uses ForEach-Object -Parallel' {
        $content | Should -Match 'ForEach-Object -Parallel'
        $content | Should -Not -Match 'foreach \(\$server in \$servers\)'
    }

    It 'captures $scriptBlock via $using:scriptBlock' {
        $content | Should -Match '\$using:scriptBlock'
    }

    It 'captures $credential via $using:credential' {
        $content | Should -Match '\$using:credential'
    }

    It 'applies the specified ThrottleLimit' {
        $content | Should -Match 'ThrottleLimit 7'
    }

    It 'embeds all three server names' {
        $content | Should -Match "'SVR01'"
        $content | Should -Match "'SVR02'"
        $content | Should -Match "'SVR03'"
    }
}

# ---------------------------------------------------------------------------
# PS remoting — SSH transport
# ---------------------------------------------------------------------------

Describe 'PS remoting — SSH transport' {

    BeforeAll {
        $script:content = Invoke-Generator @{
            ScriptPath = $psSource
            Servers    = 'LNX01,LNX02'
            Ssh        = $true
        }
    }

    It 'uses -HostName instead of -ComputerName' {
        $content | Should -Match 'Invoke-Command -HostName'
        $content | Should -Not -Match 'Invoke-Command -ComputerName'
    }

    It 'does not include a credential template (SSH uses key auth)' {
        $content | Should -Not -Match '\$credential'
    }
}

# ---------------------------------------------------------------------------
# Cross-validation warnings
# ---------------------------------------------------------------------------

Describe 'Cross-validation flag warnings' {

    It 'emits a warning but does not throw when -SqlAuth is used with a .ps1 file' {
        $w = & $generator -ScriptPath $psSource -Servers 'SVR01' -SqlAuth -OutputFile (Join-Path $TestDrive 'warn.ps1') 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        $w | Should -Not -BeNullOrEmpty
    }

    It 'warns when the source PS script references $PSScriptRoot' {
        $repoDependent = Join-Path $TestDrive 'repo-dep.ps1'
        Set-Content -Path $repoDependent -Value 'Import-Module $PSScriptRoot\..\..\tools\helper.psm1'
        $w = & $generator -ScriptPath $repoDependent -Servers 'SVR01' -OutputFile (Join-Path $TestDrive 'repo-warn.ps1') 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        $w | Should -Not -BeNullOrEmpty
    }
}
