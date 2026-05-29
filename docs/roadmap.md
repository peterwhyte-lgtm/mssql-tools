# DBA Scripts Roadmap

This repo is being shaped as a practical production DBA toolkit for the blog and for day-to-day SQL Server operations.

## What the repo already covers

The current layout now includes practical coverage for:
- performance troubleshooting and wait/blocking analysis
- storage and capacity review
- backup and restore basics and readiness checks
- configuration, memory, MAXDOP, and SQL Agent reviews
- security and permission auditing
- HA/DR and lab-style database generation
- integrity/readiness checks before DBCC validation work
- category-first navigation under categories/
- top-level helpers/ and tools/ for quick repo operations and AI-assisted work

## Execution summary intake: Phase 1 scorecard

The repo has moved from a loose script dump into a category-first DBA toolkit. The current execution summary in `temp-exec-summary.txt` is now being handled in chunks, and this roadmap is the live tracker for the first chunk.

### Current score (out of 10)

| Area | Score | Notes |
| --- | ---: | --- |
| Repository structure | 9/10 | Category-first layout, SQL/PowerShell separation, and helper grouping are now in place. |
| Navigation and discoverability | 8/10 | The category and helper entry points are much easier to follow from the repo root. |
| Output collection | 8/10 | Helper runs now write full CSV reports under `output-files/reviews/` and still show preview output in the terminal. |
| Helper usability | 8/10 | The launcher and repo helpers are now clearer and easier to use for everyday DBA checks. |
| Script standards and headers | 2/10 | The repo still needs standard metadata headers, safety annotations, and naming consistency across SQL scripts. |
| CI and quality gates | 0/10 | No SQL linter, Markdown lint, or link-check automation is in place yet. |
| Script documentation depth | 4/10 | The repo has good top-level docs, but many individual scripts still need per-script notes and examples. |

### Phase 1 focus (this chunk)

1. Finish the repo skeleton and helper layout cleanup.
2. Make the helper output path predictable and reusable for DBA reviews.
3. Lock in the category and helper entry points so the repo is easy to navigate.
4. Capture the remaining standards work as the next chunk in this roadmap.

### Phase 1 completion notes

Completed in this pass:
- category-first layout and helper organization
- launcher and repo-root helper flow
- output-files review collection path
- top-level docs and quick-start navigation updates

Pending for the next chunk:
- standard SQL headers and safe/impact tags per script
- consistent lowercase-hyphenated naming for script files
- per-script markdown docs and example output guidance
- CI automation for SQL linting, Markdown validation, and link checks

1. Reworked the repo into a DBA-first category structure with SQL and PowerShell under each category.
2. Added top-level helpers for repo overview, output cleanup, quick task routing, script discovery, and script generation.
3. Added an output-files skeleton for demo reports, backup-review output, and sample backup fixtures.
4. Updated the main docs so the repo is easier to navigate from both the high-level and script-specific views.

## Priority areas for the next deep dive

The three highest-value areas to improve next are:

1. Operational template quality
   - Make sql-templates/operations more production-ready and ServiceNow-style for change orders and runbooks.
2. Category discoverability
   - Improve the front-of-repo navigation so DBAs can locate the right category and script faster.
3. Helper automation quality
   - Replace starter helpers with real operational scripts for backup age, DR, and maintenance checks.

The next wave should focus on:

1. SQL Agent health and job failure analysis
   - completed: job history and failure visibility via Get-SqlAgentJobOverview.sql and Get-SqlAgentJobFailureSummary.sql
2. TempDB and I/O diagnostics
   - completed: usage and I/O views via Get-TempdbUsage.sql and Get-DatabaseIoUsage.sql
3. Deadlock and blocking deep dives
   - completed: blocking and wait summaries via Get-BlockingSessions.sql and Get-DeadlockSummary.sql
4. Backup/restore validation and DR rehearsal
   - completed: backup coverage and restore estimates via Get-BackupCoverage.sql, Get-BackupRestoreDurationEstimate.sql, Generate-BackupScript.sql, and Generate-RestoreScript.sql
5. Migration inventory and change prep
   - completed: inventory and checklist helpers via Get-LinkedServerAndJobInventory.sql and Get-MigrationChecklist.sql
6. Corruption and integrity checks
   - added: Get-DatabaseIntegrityChecks.sql as a pre-check and DBCC guidance script

## Work completed in this update

This update finished the first chunk of the execution-summary plan:
- repository structure and helper organization
- output collection path for review runs
- improved launcher and repo navigation flow
- documentation updates that make the current repo layout easier to use

The remaining execution-summary items are intentionally deferred to the next chunk so the repo can be improved in measurable, low-risk steps.

- Added a category-first layout under categories/ for real DBA browsing.
- Added helper utilities under helpers/ for repo overview, cleanup, routing, and proactive script generation.
- Added output-files structure for demo reports and backup-review output.
- Fixed obvious repo path and navigation inconsistencies across README, quick-start, and catalog docs.
- Added starter script generation helpers so new DBA scripts can be scaffolded quickly.

## Current focus

### Phase 2 progress (standards and documentation)

This chunk started the standards pass called out in the execution summary:
- created a reusable standards note at `docs/script-standards.md`
- added structured metadata headers, `SET NOCOUNT ON;`, and safety annotations to representative scripts in the performance, backup, maintenance, and configuration categories

Next actions in this phase:
1. extend the same header and safety pattern across the rest of the SQL scripts
2. add per-script markdown notes for the highest-value operational scripts
3. add CI automation for SQL linting and Markdown validation

- Keep scripts easy to copy into SSMS and Azure Data Studio
- Preserve simple, production-friendly comments and notes
- Expand the most useful DBA workflows first, not just the most theoretical ones
- Keep category names aligned with real troubleshooting tasks and blog topics
