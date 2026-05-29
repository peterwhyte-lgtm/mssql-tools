$root = Join-Path $PSScriptRoot 'categories'
$files = Get-ChildItem -Path $root -Recurse -Filter '*.sql' | Sort-Object FullName
$updated = 0

foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if ($text -match 'SAFE:ReadOnly' -and $text -match 'SET NOCOUNT ON;') {
        continue
    }

    $lines = $text -split "`r?`n"
    $headerEnd = 0
    if ($lines.Count -gt 0 -and $lines[0].Trim().StartsWith('/*')) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim().EndsWith('*/')) {
                $headerEnd = $i + 1
                break
            }
        }
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($file.FullName)
    $category = $file.Directory.Parent.Name
    $purpose = 'Operational DBA review script.'
    if ($name -match 'Wait|LongRunning') { $purpose = 'Review current wait or session activity for performance triage.' }
    elseif ($name -match 'Backup|Restore') { $purpose = 'Review backup and restore readiness for operational checks.' }
    elseif ($name -match 'DatabaseHealth|Integrity|Tempdb') { $purpose = 'Review database health and maintenance posture.' }
    elseif ($name -match 'Disk|Sizes|Growth|Log') { $purpose = 'Review storage consumption and growth risk.' }
    elseif ($name -match 'Agent|Memory|Version|Cpu') { $purpose = 'Review instance configuration or environment state.' }

    if ($text -notmatch 'Script Name\s*:') {
        $header = @(
            '/*',
            "Script Name : $name",
            "Category    : $category",
            "Purpose     : $purpose",
            'Author      : Peter Whyte (https://sqldba.blog)',
            'Safe        : Read-only',
            'Impact      : Low',
            'Requires    : VIEW DATABASE STATE / VIEW SERVER STATE as applicable',
            '*/',
            ''
        )
        $text = ($header -join "`n") + "`n" + $text
        $headerEnd = $header.Count
    }

    if ($text -notmatch 'SAFE:ReadOnly') {
        $parts = $text -split "`r?`n"
        if ($headerEnd -gt 0) {
            $parts = @($parts[0..($headerEnd-1)] + '' + '-- SAFE:ReadOnly' + '-- IMPACT:Low' + '' + $parts[$headerEnd..($parts.Count-1)])
            $text = $parts -join "`n"
        }
        else {
            $text = "-- SAFE:ReadOnly`n-- IMPACT:Low`n" + $text
        }
    }

    if ($text -notmatch 'SET NOCOUNT ON;') {
        $parts = $text -split "`r?`n"
        if ($headerEnd -gt 0) {
            $insertAt = $headerEnd + 1
            $parts = @($parts[0..($insertAt-1)] + 'SET NOCOUNT ON;' + $parts[$insertAt..($parts.Count-1)])
            $text = $parts -join "`n"
        }
        else {
            $text = 'SET NOCOUNT ON;' + "`n`n" + $text
        }
    }

    Set-Content -LiteralPath $file.FullName -Value $text -Encoding UTF8
    $updated++
}

Write-Host "Updated $updated SQL files with metadata, safety markers, and SET NOCOUNT where needed."
