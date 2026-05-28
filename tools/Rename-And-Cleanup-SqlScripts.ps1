Set-Location $PSScriptRoot\.. 

$renames = @(
  @{ Old='sql/storage-capacity-management/database-sizes-and-free-space.sql'; New='sql/storage-capacity-management/Get-DatabaseSizesAndFreeSpace.sql' },
  @{ Old='sql/performance-troubleshooting/top-wait-statistics.sql'; New='sql/performance-troubleshooting/Get-WaitStatistics.sql' },
  @{ Old='sql/performance-troubleshooting/identify-long-running-queries.sql'; New='sql/performance-troubleshooting/Get-LongRunningQueries.sql' },
  @{ Old='sql/performance-troubleshooting/identify-missing-indexes.sql'; New='sql/performance-troubleshooting/Get-MissingIndexes.sql' },
  @{ Old='sql/performance-troubleshooting/deadlock-summary.sql'; New='sql/performance-troubleshooting/Get-DeadlockSummary.sql' },
  @{ Old='sql/performance-troubleshooting/blocking-summary.sql'; New='sql/performance-troubleshooting/Get-BlockingSessions.sql' },
  @{ Old='sql/configuration-and-environment/instance-config-snapshot.sql'; New='sql/configuration-and-environment/Get-InstanceConfigurationSnapshot.sql' },
  @{ Old='sql/configuration-and-environment/get-memory-configuration.sql'; New='sql/configuration-and-environment/Get-MemoryConfiguration.sql' },
  @{ Old='sql/configuration-and-environment/check-maxdop.sql'; New='sql/configuration-and-environment/Get-MaxdopConfiguration.sql' },
  @{ Old='sql/configuration-and-environment/sql-agent-job-overview.sql'; New='sql/configuration-and-environment/Get-SqlAgentJobOverview.sql' },
  @{ Old='sql/configuration-and-environment/sql-agent-job-failure-summary.sql'; New='sql/configuration-and-environment/Get-SqlAgentJobFailureSummary.sql' },
  @{ Old='sql/security-and-permissions/list-sysadmin-members.sql'; New='sql/security-and-permissions/Get-SysadminMembers.sql' },
  @{ Old='sql/security-and-permissions/check-database-mail-xp_cmdshell.sql'; New='sql/security-and-permissions/Get-DatabaseMailAndXpCmdShell.sql' },
  @{ Old='sql/high-availability-and-disaster-recovery/availability-group-replica-state.sql'; New='sql/high-availability-and-disaster-recovery/Get-AvailabilityGroupReplicaState.sql' },
  @{ Old='sql/high-availability-and-disaster-recovery/check-ag-latency.sql'; New='sql/high-availability-and-disaster-recovery/Get-AvailabilityGroupLatency.sql' },
  @{ Old='sql/backups-and-recovery/backup-coverage.sql'; New='sql/backups-and-recovery/Get-BackupCoverage.sql' },
  @{ Old='sql/backups-and-recovery/generate-backup-script.sql'; New='sql/backups-and-recovery/Generate-BackupScript.sql' },
  @{ Old='sql/backups-and-recovery/generate-restore-script.sql'; New='sql/backups-and-recovery/Generate-RestoreScript.sql' },
  @{ Old='sql/backups-and-recovery/estimate-backup-restore-time.sql'; New='sql/backups-and-recovery/Get-BackupAndRestoreDurationEstimate.sql' },
  @{ Old='sql/maintenance-and-reliability/HealthCheck-Database.sql'; New='sql/maintenance-and-reliability/Get-DatabaseHealth.sql' },
  @{ Old='sql/maintenance-and-reliability/index-fragmentation.sql'; New='sql/maintenance-and-reliability/Get-IndexFragmentation.sql' },
  @{ Old='sql/maintenance-and-reliability/tempdb-usage.sql'; New='sql/maintenance-and-reliability/Get-TempdbUsage.sql' },
  @{ Old='sql/maintenance-and-reliability/sqlserver-show-database-growth-events.sql'; New='sql/maintenance-and-reliability/Get-DatabaseGrowthEvents.sql' },
  @{ Old='sql/dba-lab-scripts/create-test-databases.sql'; New='sql/dba-lab-scripts/New-TestDatabases.sql' }
)

foreach ($item in $renames) {
  if (Test-Path $item.Old) {
    $dest = Join-Path (Get-Location) $item.New
    Move-Item -LiteralPath $item.Old -Destination $dest -Force
    Write-Host "RENAMED: $($item.Old) -> $($item.New)"
  }
}

$remove = @(
  'sql/storage-capacity-management/sqlserver-database-sizes-and-free-space.sql',
  'sql/performance-troubleshooting/sqlserver-top-wait-statistics.sql',
  'sql/performance-troubleshooting/sqlserver-identify-long-running-queries.sql',
  'sql/performance-troubleshooting/sqlserver-identify-missing-indexes.sql',
  'sql/configuration-and-environment/sqlserver-instance-configuration-snapshot.sql',
  'sql/configuration-and-environment/sqlserver-agent-job-overview.sql',
  'sql/security-and-permissions/sqlserver-list-sysadmin-role-members.sql',
  'sql/security-and-permissions/sqlserver-check-xpcmdshell-clr-databasemail.sql',
  'sql/high-availability-and-disaster-recovery/sqlserver-check-aag-latency.sql',
  'sql/high-availability-and-disaster-recovery/sqlserver-check-ag-replica-role-and-sync-state.sql',
  'powershell/diagnostics/Get-BlockingSessions.ps1',
  'powershell/diagnostics/Get-IndexFragmentation.ps1',
  'powershell/diagnostics/Get-DiskSpaceSummary.ps1',
  'powershell/diagnostics/Get-LargestFolders.ps1',
  'powershell/maintenance/Backup-SqlDatabases.ps1',
  'powershell/maintenance/Remove-DatabasesByPrefix.ps1',
  'powershell/maintenance/Run-CreateTestDatabases.ps1'
)

foreach ($path in $remove) {
  if (Test-Path $path) {
    Remove-Item -LiteralPath $path -Force
    Write-Host "REMOVED: $path"
  }
}
