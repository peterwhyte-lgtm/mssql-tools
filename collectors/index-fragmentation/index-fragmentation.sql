/*
Script Name : index-fragmentation
Category    : collectors
Purpose     : Weekly point-in-time snapshot of index fragmentation for all user databases.
              Tracks which indexes degrade fastest over time and provides recommended
              action (REBUILD / REORGANIZE / NONE) based on current fragmentation.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low — SAMPLED mode reads a subset of pages; avoid during peak hours
Requires    : VIEW DATABASE STATE; run per database with: -Database YourDatabase
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: SAMPLED mode scans ~1% of pages — accurate for fragmentation detection
  and much faster than DETAILED. Excludes indexes smaller than 100 pages (too small
  to benefit from defrag). Excludes heaps (index_id = 0) — heaps fragment differently.
  Thresholds match the defaults in Get-IndexFragmentation.sql:
    >= 30%  → REBUILD
    10-29%  → REORGANIZE
    < 10%   → NONE
*/

SELECT
    GETDATE()                                           AS collection_time,
    @@SERVERNAME                                        AS server_name,
    DB_NAME()                                           AS database_name,
    s.name                                              AS schema_name,
    o.name                                              AS table_name,
    ix.name                                             AS index_name,
    ix.type_desc                                        AS index_type,
    ips.partition_number,
    ips.page_count,
    CAST(ips.avg_fragmentation_in_percent AS decimal(5,1))
                                                        AS avg_fragmentation_pct,
    ips.fragment_count,
    CAST(ips.avg_fragment_size_in_pages AS decimal(8,1))
                                                        AS avg_fragment_size_pages,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent >= 10 THEN 'REORGANIZE'
        ELSE 'NONE'
    END                                                 AS recommended_action
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes  ix ON ix.object_id = ips.object_id AND ix.index_id = ips.index_id
JOIN sys.objects  o  ON o.object_id  = ips.object_id
JOIN sys.schemas  s  ON s.schema_id  = o.schema_id
WHERE ips.page_count >= 100
  AND ips.index_id   > 0       -- exclude heaps
  AND o.is_ms_shipped = 0
ORDER BY ips.avg_fragmentation_in_percent DESC, ips.page_count DESC;
