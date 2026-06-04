/*
Script Name : errorlog
Category    : collectors
Purpose     : Extracts recent Error and Warning entries from the SQL Server error log.
              Returns only new entries (filtered by timestamp in the wrapper). Use to
              build a searchable history of recurring errors across time.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE; EXECUTE on sys.xp_readerrorlog
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: xp_readerrorlog is the supported way to read the SQL Server error log.
  Parameters: (0 = current log, 1 = SQL errorlog type, search1, search2, start_time, end_time, sort)
  We read the last 24 hours. The wrapper applies de-duplication by tracking the
  most recent LogDate already in the CSV and filtering to newer entries only.

  Severity mapping (LogDate prefix): "Error:" and "Warning:" prefixes in the Text column.
  Rows without a severity prefix are informational and are excluded here.
  The collection_time column records when this run executed (for auditing).
*/

CREATE TABLE #errorlog (
    LogDate     DATETIME,
    ProcessInfo NVARCHAR(100),
    Text        NVARCHAR(4000)
);

DECLARE @since DATETIME = DATEADD(HOUR, -24, GETDATE());

INSERT INTO #errorlog (LogDate, ProcessInfo, Text)
EXEC sys.xp_readerrorlog 0, 1, NULL, NULL, @since, NULL, N'asc';

SELECT
    GETDATE()           AS collection_time,
    @@SERVERNAME        AS server_name,
    LogDate             AS log_date,
    ProcessInfo         AS process_info,
    -- Classify severity from the log text prefix
    CASE
        WHEN Text LIKE 'Error%'       THEN 'Error'
        WHEN Text LIKE 'Warning%'     THEN 'Warning'
        WHEN Text LIKE '%severity%1[5-9]%' OR Text LIKE '%severity%2[0-4]%' THEN 'Error'
        ELSE 'Info'
    END                 AS severity,
    LEFT(Text, 2000)    AS message_text
FROM #errorlog
WHERE Text NOT LIKE '%Login succeeded%'  -- suppress successful logins (noisy)
  AND Text NOT LIKE '%Log was backed up%'
  AND Text NOT LIKE 'BACKUP DATABASE%'
  AND Text NOT LIKE 'BACKUP LOG%'
  AND LEN(LTRIM(Text)) > 0
ORDER BY LogDate;

DROP TABLE #errorlog;
