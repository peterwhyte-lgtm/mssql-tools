﻿# PowerShell layer

This top-level PowerShell folder is the canonical home for automation, orchestration, and local execution helpers.

Suggested domains:
- inventory/ — environment and asset discovery
- disk-space/ — local disk and backup folder health checks, plus backup age reporting
- wrappers/backups/ — thin wrappers for SQL backup/restore DDL generation and backup health queries
- wrappers/maintenance/ — thin wrappers for SQL maintenance job DDL generators (backup jobs, index maintenance, housekeeping)
- reporting/ — CSV and summary generation utilities
- health-checks/ — operational readiness and maintenance checks

The canonical working path is now the top-level powershell/ layer. Use tools/ for repo execution support, and follow the production guidance in docs/standards.md for script classification, scope, and risk notes.