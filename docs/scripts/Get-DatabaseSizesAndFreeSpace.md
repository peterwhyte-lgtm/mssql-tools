# Get-DatabaseSizesAndFreeSpace

Category: storage-capacity-management

Purpose:
Review current database sizes, transaction log size, and free-space posture for capacity planning.

How to run:
- .\run.ps1 Get-DatabaseSizesAndFreeSpace

What to look for:
- Databases with unexpectedly large log files.
- Growth risk signs such as very small free space or rapidly growing data files.

Requirements:
- Read-only query.
- VIEW ANY DATABASE is typically sufficient.
