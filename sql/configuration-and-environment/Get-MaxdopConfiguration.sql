/*
Script Name : Check MAXDOP Configuration
Description : Returns MAXDOP configuration and core visibility for quick validation.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    name,
    value_in_use,
    value,
    description
FROM sys.configurations
WHERE name = 'max degree of parallelism';

SELECT
    cpu_count,
    hyperthread_ratio,
    sockets,
    cores_per_socket
FROM sys.dm_os_sys_info;
