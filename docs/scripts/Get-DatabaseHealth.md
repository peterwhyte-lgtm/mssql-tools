# Get-DatabaseHealth

Category: maintenance-and-reliability

Purpose:
Capture a compact health summary for user databases and identify immediate maintenance or recovery concerns.

How to run:
- .\run.ps1 Get-DatabaseHealth

What to look for:
- Databases in unusual states or with long log reuse waits.
- Large data or log file sizes that may need maintenance review.

Requirements:
- Read-only query.
- VIEW ANY DATABASE is typically sufficient.
