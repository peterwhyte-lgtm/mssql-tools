# Hybrid layer

This folder is reserved for multi-step operational workflows that combine SQL execution, PowerShell orchestration, and structured reporting.

Currently, the primary workflow lives at:

- `powershell\reporting\Invoke-HealthCheckCollection.ps1` — 19-script collection pass
- `powershell\reporting\Review-HealthCheckOutput.ps1` — findings review with CRITICAL/WARNING/INFO output

Subfolders in this directory will be added as specific multi-step workflows are built out (agent job monitoring, backup validation, estate reporting across server fleets).
