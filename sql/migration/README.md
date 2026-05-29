# Migration SQL area

This folder is the canonical SQL home for migration-focused inventory and readiness checks.

Use these scripts before database moves, upgrades, or estate refreshes:
- Get-DatabaseInventory.sql — database inventory and compatibility details
- Get-LoginInventory.sql — server login inventory and disabled-state review
- Get-JobInventory.sql — SQL Agent job inventory for dependency checks
- Get-LinkedServerInventory.sql — linked server inventory for connection review
