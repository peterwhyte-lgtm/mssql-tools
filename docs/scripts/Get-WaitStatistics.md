# Get-WaitStatistics

Category: performance-troubleshooting

Purpose:
Review instance wait statistics to spot the main sources of wait time during performance triage.

How to run:
- .\run.ps1 Get-WaitStatistics

What to look for:
- Large wait_time_ms values usually indicate the main bottleneck area.
- `SOS_WORK_DISPATCHER`, `SLEEP_TASK`, and `BROKER_TASK_STOP` are often background noise on busy systems.

Requirements:
- Read-only query.
- VIEW SERVER STATE or equivalent permissions are recommended for full DMV visibility.
