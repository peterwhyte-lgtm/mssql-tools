# DBA Toolkit Standards

This repository is treated as an operational SQL Server toolkit, not as a loose script dump.

## Standard SQL header
Use this header format in SQL scripts:

```sql
/*
ScriptName   : <Name>
Purpose      : <Operational reason for the query>
Author       : <Owner>
SQLVersion   : SQL Server <Min version>
Requires     : <Permissions or prerequisites>
RiskLevel    : SAFE | MEDIUM | HIGH IMPACT
Scope        : Single server | Multi-server | Instance-wide
Notes        : <Safety notes, output guidance, and when not to use it>
*/
SET NOCOUNT ON;
```

## PowerShell classification
For PowerShell helpers, record the following in the header:

- ScriptType: runner / automation / hybrid
- TargetScope: single server / multi-server
- RiskLevel: SAFE / MEDIUM / HIGH IMPACT
- Purpose: what the script is intended to do operationally

## Production guidance
- Keep SQL read-only unless the name clearly implies change.
- Prefer modern DMVs and supported catalog views over deprecated objects.
- Avoid unsafe patterns such as NOLOCK unless the script explicitly documents the trade-off.
- Keep output deterministic and easy to review in SSMS or terminal output.
- Store SQL logic in external .sql files where possible and keep PowerShell focused on orchestration.
