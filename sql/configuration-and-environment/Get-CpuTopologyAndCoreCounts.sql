/*
Script Name : Get CPU Topology and Core Counts
Description : Returns CPU, NUMA, and scheduler information as seen by SQL Server.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    node_id,
    node_state_desc,
    memory_node_id,
    cpu_id,
    status
FROM sys.dm_os_nodes
WHERE node_state_desc IS NOT NULL;

SELECT
    cpu_count,
    hyperthread_ratio,
    sockets,
    cores_per_socket,
    numa_node_count
FROM sys.dm_os_sys_info;
