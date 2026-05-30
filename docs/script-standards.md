# Script standards for the next phase

This note captures the first standards chunk for the repo.

## Standard header fields

Use the following pattern in SQL scripts when you update them:

```sql
/*
Script Name : <short script name>
Category    : <category folder>
Purpose     : <one-line purpose>
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only / Writes data / Creates objects
Impact      : Low / Medium / High
Requires    : <permissions or prerequisites>
*/
```

## Safety annotations

- SAFE:ReadOnly
- IMPACT:Low / Medium / High
- WARNING: <destructive or long-running behavior>

## Code hygiene rules

- Add SET NOCOUNT ON; at the top of scripts where it is appropriate.
- Prefer modern DMVs and read-only queries.
- Avoid deprecated or unsafe patterns when updating scripts.
- Keep comments concise and operationally useful.
