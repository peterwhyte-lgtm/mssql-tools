-- Review whether database mail, xp_cmdshell, and CLR are enabled.
-- Use this for security review and compliance checks.

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

EXEC sp_configure 'xp_cmdshell';
EXEC sp_configure 'clr enabled';
EXEC sp_configure 'Database Mail XPs';

RECONFIGURE;
