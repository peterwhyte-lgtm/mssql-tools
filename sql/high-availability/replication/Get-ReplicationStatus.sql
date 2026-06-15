/*
Script Name : Get-ReplicationStatus
Category    : high-availability
Purpose     : Show transactional replication status for local publisher and distributor.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    s.name AS publication_db,
    p.name AS publication_name,
    a.agent_name,
    r.subscriber_db,
    r.subscriber_server,
    r.status,
    CASE r.status
        WHEN 1 THEN 'Started'
        WHEN 2 THEN 'Starting'
        WHEN 3 THEN 'Stopping'
        WHEN 4 THEN 'Stopped'
        WHEN 5 THEN 'Retrying'
        WHEN 6 THEN 'Failed'
        WHEN 7 THEN 'Succeeded'
        ELSE 'Unknown'
    END AS status_desc,
    r.last_distsync_status,
    r.last_distsync_time,
    r.last_distsync_duration,
    r.last_distsync_history
FROM syspublications p
JOIN syspublication_agents a ON p.publication_id = a.publication_id
JOIN syspublication_subscriptions s ON p.publication_id = s.publication_id
JOIN syspublication_subscriptions_history r ON s.subscription_id = r.subscription_id
ORDER BY s.name, p.name, a.agent_name;
