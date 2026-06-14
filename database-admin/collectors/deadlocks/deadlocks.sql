/*
Script Name : deadlocks
Category    : collectors
Purpose     : Extract deadlock events from the system_health XEvent ring buffer.
              Parses deadlock XML into readable columns. Returns new events only
              (filtered by timestamp in the wrapper).
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: Reads the system_health XEvent ring buffer — no XEvent session setup required.
  The ring buffer holds the most recent ~250 events. The wrapper filters to new events
  only (newer than the last captured timestamp) to avoid duplicate rows.
  The full deadlock XML is preserved in deadlock_xml for detailed investigation.
*/

WITH ring_buffer AS (
    SELECT
        CAST(xdr.value('@timestamp','datetime2') AT TIME ZONE 'UTC' AT TIME ZONE 'AUS Eastern Standard Time' AS datetime2) AS event_time,
        xdr.query('.')                                              AS deadlock_xml
    FROM (
        SELECT CAST(target_data AS XML) AS target_xml
        FROM sys.dm_xe_session_targets   t
        JOIN sys.dm_xe_sessions          s ON s.address = t.event_session_address
        WHERE s.name = 'system_health'
          AND t.target_name = 'ring_buffer'
    ) AS rb
    CROSS APPLY target_xml.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS xn(xdr)
)
SELECT
    GETDATE()                                                       AS collection_time,
    @@SERVERNAME                                                    AS server_name,
    rb.event_time                                                   AS deadlock_time,
    -- Victim process ID
    rb.deadlock_xml.value('(//deadlock/victim-list/victimProcess/@id)[1]', 'nvarchar(50)')
                                                                    AS victim_process_id,
    -- Victim SPID
    rb.deadlock_xml.value('(//deadlock/process-list/process[@id = (//deadlock/victim-list/victimProcess/@id)[1]]/@spid)[1]', 'int')
                                                                    AS victim_spid,
    -- Victim login
    rb.deadlock_xml.value('(//deadlock/process-list/process[@id = (//deadlock/victim-list/victimProcess/@id)[1]]/@loginname)[1]', 'nvarchar(128)')
                                                                    AS victim_login,
    -- Victim last statement
    REPLACE(REPLACE(
        rb.deadlock_xml.value('(//deadlock/process-list/process[@id = (//deadlock/victim-list/victimProcess/@id)[1]]/inputbuf)[1]', 'nvarchar(1000)'),
        CHAR(13),' '), CHAR(10),' ')                                AS victim_statement,
    -- Number of processes in the deadlock
    rb.deadlock_xml.value('count(//deadlock/process-list/process)', 'int')
                                                                    AS process_count,
    -- Full XML for detailed investigation
    CAST(rb.deadlock_xml AS nvarchar(max))                         AS deadlock_xml
FROM ring_buffer rb
ORDER BY rb.event_time DESC;
