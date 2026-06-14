/*
Script Name : ag-health
Category    : collectors
Purpose     : Snapshot Availability Group replica state, synchronisation health,
              redo/send queue depths, and estimated failover time. Guards against
              non-AG instances and returns a status row instead of throwing.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

/*
  DESIGN: Returns a single 'NO_AG' row on instances with no AG configured so the
  collector always succeeds. Analyse for rows where ag_name IS NOT NULL.
  Queue depth columns (redo_queue_kb, log_send_queue_kb) are the primary leading
  indicators of synchronisation lag. Failover readiness is reflected by
  synchronization_health_desc.
*/

IF NOT EXISTS (SELECT 1 FROM sys.availability_groups)
BEGIN
    SELECT
        GETDATE()       AS collection_time,
        @@SERVERNAME    AS server_name,
        'NO_AG'         AS ag_name,
        NULL AS replica_server_name, NULL AS role_desc,
        NULL AS operational_state_desc, NULL AS connected_state_desc,
        NULL AS synchronization_health_desc, NULL AS last_connect_error_description,
        NULL AS database_name, NULL AS db_synchronization_state_desc,
        NULL AS db_synchronization_health_desc,
        NULL AS log_send_queue_kb, NULL AS log_send_rate_kb_s,
        NULL AS redo_queue_kb,     NULL AS redo_rate_kb_s,
        NULL AS last_sent_time,    NULL AS last_received_time,
        NULL AS last_hardened_time, NULL AS last_redone_time,
        NULL AS last_commit_time,
        NULL AS estimated_redo_completion_time_s,
        NULL AS estimated_data_loss_s;
    RETURN;
END

SELECT
    GETDATE()                                                       AS collection_time,
    @@SERVERNAME                                                    AS server_name,
    ag.name                                                         AS ag_name,
    ar.replica_server_name,
    ars.role_desc,
    ars.operational_state_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    ars.last_connect_error_description,
    adb.database_name,
    drs.synchronization_state_desc                                  AS db_synchronization_state_desc,
    drs.synchronization_health_desc                                 AS db_synchronization_health_desc,
    drs.log_send_queue_size                                         AS log_send_queue_kb,
    drs.log_send_rate                                               AS log_send_rate_kb_s,
    drs.redo_queue_size                                             AS redo_queue_kb,
    drs.redo_rate                                                   AS redo_rate_kb_s,
    drs.last_sent_time,
    drs.last_received_time,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.last_commit_time,
    drs.estimated_redo_completion_time                              AS estimated_redo_completion_time_s,
    drs.estimated_data_loss_seconds                                 AS estimated_data_loss_s
FROM sys.availability_groups             ag
JOIN sys.availability_replicas           ar  ON ar.group_id   = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ars.replica_id = ar.replica_id
LEFT JOIN sys.dm_hadr_database_replica_states drs ON drs.replica_id = ars.replica_id
LEFT JOIN sys.availability_databases_cluster adb ON adb.group_id    = ag.group_id
                                                  AND adb.group_database_id = drs.group_database_id
ORDER BY ag.name, ar.replica_server_name, adb.database_name;
