﻿# Multi-Server Scripts

Standalone scripts for running operations across multiple servers simultaneously. Every script in this folder is **self-contained** — copy it out and run it anywhere. No repo dependency at runtime.

All scripts accept a `-Servers` parameter (comma-separated) and a `-Parallel` switch.

---

## powershell/

Scripts that connect to remote hosts via WinRM or RPC. No SQL Server needed.

| Script | What it does | Remoting |
|--------|-------------|----------|
| `MultiServer-RestartService.ps1` | Restart a named Windows service on multiple hosts | WinRM |
| `MultiServer-GetServiceStatus.ps1` | Check service running/stopped state across hosts | RPC (no WinRM) |
| `MultiServer-GetRecentEventLogs.ps1` | Pull recent Error/Warning events from event logs | RPC (no WinRM) |
| `MultiServer-GetFirewallRules.ps1` | List local Windows Firewall rules | WinRM |
| `MultiServer-GetDiskSpace.ps1` | Disk free/used per volume across hosts | WinRM |
| `MultiServer-TestSqlPort.ps1` | Test TCP port 1433 reachability — no auth needed | None (TCP only) |

**WinRM prerequisite** (for scripts that need it):
```powershell
# Run as admin on each TARGET server:
Enable-PSRemoting -Force
```

---

## sql/

PowerShell wrappers with SQL embedded inline. Connect to SQL Server over port 1433 via `Invoke-Sqlcmd`. No remoting to the SQL Server host required — queries run from your machine.

| Script | What it does |
|--------|-------------|
| `MultiServer-GetWaitStats.ps1` | Top wait types per instance (filters background noise) |
| `MultiServer-GetBlockingSessions.ps1` | Active blocking sessions across instances |
| `MultiServer-GetBackupStatus.ps1` | Backup coverage — last full/diff/log per database |
| `MultiServer-GetDatabaseSizes.ps1` | Data and log file sizes per database per instance |

**SqlServer module prerequisite:**
```powershell
Install-Module -Name SqlServer -Scope CurrentUser -Force
```
The scripts check for this on startup and tell you how to install if it's missing.

---

## Common parameters

All scripts support:

| Parameter | Description |
|-----------|-------------|
| `-Servers "SVR01,SVR02,SVR03"` | Comma-separated server names or IPs |
| `-Parallel` | Run against all servers at once (PS7+). Sequential is default. |
| `-Credential` | PSCredential for alternate auth — GetDiskSpace, GetFirewallRules, GetRecentEventLogs, RestartService only (not GetServiceStatus or TestSqlPort) |
| `-SqlAuth` | Prompt for SQL credentials instead of Windows auth (SQL scripts) |

SQL scripts also accept:
- `-Database` — target database for the connection (default: `master`)

---

## Quick examples

```powershell
# Are all my SQL servers reachable?
.\powershell\MultiServer-TestSqlPort.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05"

# Is anything blocked right now?
.\sql\MultiServer-GetBlockingSessions.ps1 -Servers "SVR01,SVR02,SVR03"

# Disk space check across the estate
.\powershell\MultiServer-GetDiskSpace.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05" -Parallel

# Restart SQL Agent on three servers (asks for confirmation per server by default)
.\powershell\MultiServer-RestartService.ps1 -Servers "SVR01,SVR02,SVR03" -ServiceName SQLSERVERAGENT

# What's been failing in the event logs across five servers?
.\powershell\MultiServer-GetRecentEventLogs.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05" -Hours 48 -Parallel
```

---

## Want to generate a multi-server wrapper for any repo script?

See `tools/multi-server-query/` — the generator takes any `.sql` or `.ps1` from this repo and produces a ready-to-copy multi-server script.