/*
Script Name : Get SQL Server Services Information
Description : Returns SQL Server and SQL Agent service details including startup type and status.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    servicename,
    process_id,
    startup_type_desc,
    status_desc,
    last_startup_time,
    service_account,
    is_clustered,
    cluster_nodename
FROM sys.dm_server_services;
