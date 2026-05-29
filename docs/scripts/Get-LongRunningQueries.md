# Get-LongRunningQueries

Category: performance-troubleshooting

Purpose:
Show currently executing sessions with the longest elapsed time so you can identify slow or stuck work.

How to run:
- .\run.ps1 Get-LongRunningQueries

What to look for:
- Long `elapsed_time_seconds` values.
- Sessions with blocked or waiting state that are not making progress.

Requirements:
- Read-only query.
- VIEW SERVER STATE and access to the current database context are typically sufficient.
