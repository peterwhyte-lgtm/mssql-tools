# DBA Scripts

A curated collection of practical SQL Server scripts used in real production environments.
Focused on performance, backups, configuration, security, and operational visibility.
Built for DBAs who need answers quickly.

This repository is designed to support the DBA Scripts section of the site and to give production SQL Server DBAs a fast, copy/paste-friendly toolkit for daily troubleshooting and operational checks.

## What is included

- Production-safe diagnostics and monitoring scripts for day-to-day DBA work
- Simple SSMS-first queries with inline comments and practical output
- PowerShell helpers for local ops, cleanup, and quick triage
- Lab/test scripts for environment setup and database generation

## What we are optimizing for

- Fast copy/paste into SSMS or Azure Data Studio
- Clear category grouping by real DBA task
- Easy handoff to other production DBAs
- A solid foundation for future blog posts and runbooks

## Production DBA categories

- powershell/performance-troubleshooting/ — long-running queries, waits, fragmentation, and session analysis
- powershell/storage-capacity-management/ — disk and folder usage diagnostics
- powershell/backups-and-recovery/ — backup and restore helpers
- powershell/maintenance-and-reliability/ — health checks and reliability scripts
- powershell/configuration-and-environment/ — instance and environment snapshots
- powershell/security-and-permissions/ — security and access checks
- powershell/high-availability-and-disaster-recovery/ — AG and DR operational helpers
- powershell/dba-lab-scripts/ — local/test database generation and cleanup helpers

- sql/performance-troubleshooting/ — SSMS-ready tuning and wait analysis queries
- sql/storage-capacity-management/ — database and storage usage queries
- sql/backups-and-recovery/ — backup coverage and recovery checks
- sql/maintenance-and-reliability/ — index and health maintenance queries
- sql/configuration-and-environment/ — instance config and environment review queries
- sql/security-and-permissions/ — permission and role audit queries
- sql/high-availability-and-disaster-recovery/ — AG and DR health checks
- sql/dba-lab-scripts/ — test database creation and lab utility scripts

## How to use this repo

1. Open the category folder that matches the problem you are troubleshooting.
2. Copy the SQL script into SSMS or Azure Data Studio.
3. Run the PowerShell helper when you need a quick automation or local environment check.
4. Treat the scripts as production-safe starting points and extend them for your environment.

## Notes

- Folder names are lowercase for consistency.
- Scripts are grouped by real production DBA use case.
- The DBA Lab Scripts area is intentionally separate for test and simulation work.
- Use docs/ for runbooks, templates, and operational notes.
