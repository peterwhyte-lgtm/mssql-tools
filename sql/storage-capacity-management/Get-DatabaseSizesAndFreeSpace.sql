-- Show database size, log size, and free space for production review.
-- Useful for storage capacity planning and backup planning.

SELECT
    d.name AS database_name,
    CAST(SUM(CASE WHEN f.type_desc = 'ROWS' THEN f.size END) * 8. / 1024 AS DECIMAL(12,2)) AS data_size_gb,
    CAST(SUM(CASE WHEN f.type_desc = 'LOG' THEN f.size END) * 8. / 1024 AS DECIMAL(12,2)) AS log_size_gb,
    CAST(SUM(CASE WHEN f.type_desc = 'ROWS' THEN f.size END) * 8. / 1024 -
         (SELECT SUM(CASE WHEN p.type = 'D' THEN p.used_pages END) * 8. / 1024
          FROM sys.allocation_units p
          WHERE p.container_id = f.file_id) AS DECIMAL(12,2)) AS estimated_free_space_gb
FROM sys.master_files f
JOIN sys.databases d ON f.database_id = d.database_id
GROUP BY d.name
ORDER BY data_size_gb DESC;
