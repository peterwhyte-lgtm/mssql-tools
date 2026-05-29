# performance-troubleshooting

Use this folder for SQL Server performance investigations and long-running session analysis.

Typical scripts:
- blocking and wait analysis
- top wait statistics review
- long-running query review
- fragmentation checks
- session and query diagnostics

Quick entry points:
- Get-WaitStatistics.ps1 — runs the repo wait-statistics query against the local SQL instance for quick review.
- Get-LongRunningQueries.ps1 — runs the repo long-running query review for current activity and elapsed-time analysis.
