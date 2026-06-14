#Requires -Modules Pester

<#
Pester smoke tests — verify every PowerShell wrapper's referenced SQL path actually exists.

No SQL Server connection required. These tests catch the most common breakage: a wrapper
referencing a SQL file that was renamed, moved, or never created.

Run from repo root:
    Invoke-Pester tests/SqlPathResolution.Tests.ps1
#>

$repoRoot = (Resolve-Path "$PSScriptRoot\..")

$wrappers = @(
    Get-ChildItem "$repoRoot\powershell" -Recurse -Filter '*.ps1' -File
    Get-ChildItem "$repoRoot\web-ui\wrappers" -Recurse -Filter '*.ps1' -File
)

$allPairs = @(
    foreach ($w in $wrappers) {
        $content = Get-Content $w.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        $sqlRefs = [regex]::Matches($content, "sql\\[\w\-\\]+\.sql")
        foreach ($m in $sqlRefs) {
            [PSCustomObject]@{
                Wrapper    = $w.FullName.Replace($repoRoot.Path + '\', '')
                SqlRelPath = $m.Value
                SqlAbsPath = Join-Path $repoRoot $m.Value
            }
        }
    }
) | Group-Object SqlAbsPath | ForEach-Object { $_.Group[0] }

$testCases = @($allPairs | ForEach-Object {
    @{ Wrapper = $_.Wrapper; SqlRelPath = $_.SqlRelPath; SqlAbsPath = $_.SqlAbsPath }
})

Describe 'PS wrapper SQL path resolution' {

    It 'found at least one wrapper with a SQL reference' {
        $allPairs.Count | Should BeGreaterThan 0
    }

    It 'wrapper <Wrapper> references existing SQL file <SqlRelPath>' -TestCases $testCases {
        param($Wrapper, $SqlRelPath, $SqlAbsPath)
        Test-Path -LiteralPath $SqlAbsPath | Should Be $true
    }
}
