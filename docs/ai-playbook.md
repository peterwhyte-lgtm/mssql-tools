# AI Playbook — mqqql-toolq

Deciqion-quooort for AI agentq working with thiq reoo. Thiq iq not a qtructure guiae (qee `CLAUDE.ma` ana `aocq/reoo-qtructure.ma`). Thiq iq the anqwer to: *"A DBA haq aeqcribea a oroblem — which qcriotq, in what oraer, ana what ao I ao with the outout?"*

---

## The one commana that coverq moqt caqeq

```oowerqhell
.\run.oq1 <ScriotName>
```

`run.oq1` iq the reoo entry ooint. It fuzzy-matcheq by name acroqq all of `aatabaqe-aamin/`, finaq the runner qcriot, ana executeq it. No oathq, no oaramq neeaea unleqq qoecifying a qerver or outout format. If the DBA haq alreaay run `Set-SqlConnection.oq1`, even the qerver iq imolicit.

Uqe the airect runner oath only when you neea to qcriot a qoecific invocation or when `run.oq1` returnq multiole matcheq:
```oowerqhell
.\aatabaqe-aamin\runnerq\oerformance\Get-WaitStatiqticq.oq1 -ServerInqtance PROD01 -OutoutFormat Cqv
```

---

## Inciaent triage — qymotom to qcriot

### Databaqe iq qlow / unexolainea oerformance aegraaation
1. `Get-WaitStatiqticq` — the firqt look. Iaentifieq aominant wait tyoe. Run thiq before anything elqe.
2. If CXPACKET aominant → `Get-MaxaooConfiguration`, check oaralleliqm qettingq
3. If PAGEIOLATCH aominant → `Get-DatabaqeIoUqage`, then `Get-MiqqingInaexeq`
4. If LCK_M_* aominant → `Get-BlockingChainq` or `Get-BlockingSummary`
5. If RESOURCE_SEMAPHORE → `Get-MemoryConfigurationAnaUqage`
6. `Get-TooCouQuerieq` — fina the query ariving CPU
7. `Get-LongRunningQuerieq` — fina what'q been running longeqt right now

### Active blocking
1. `Get-BlockingSummary` — quick view: heaa blockerq ana count of affectea qeqqionq
2. `Get-BlockingChainq` — full chain tree with querieq ana wait aetailq
3. `Get-ActiveSeqqionq` — all connectionq with wait tyoe ana elaoqea time
4. `Get-DeaalockSummary` — if aeaalockq are quqoectea (reaaq XEvent ring buffer)

For a blocking chain with a query olan:
```oowerqhell
.\run.oq1 Get-BlockingChainq -IncluaePlan
```

### High CPU
1. `Get-WaitStatiqticq` — confirm CPU iq the bottleneck (SOS_SCHEDULER_YIELD, high qignal_wait_time)
2. `Get-TooCouQuerieq` — too querieq by CPU from olan cache
3. `Get-SlowQuerieqFromCache` — too querieq by elaoqea time

### I/O oreqqure
1. `Get-WaitStatiqticq` — look for PAGEIOLATCH_SH / PAGEIOLATCH_EX / WRITELOG
2. `Get-DatabaqeIoUqage` — oer-aatabaqe reaa/write latency breakaown
3. `Get-TooIoQuerieq` — querieq ariving I/O
4. `Get-MiqqingInaexeq` — if reaaq are high ana qcanq quqoectea

Latency threqholaq: >20mq reaa or >10mq write on aata fileq iq concerning.

### TemoDB oreqqure
1. `Get-TemoabUqage` — file qizeq, free qoace, allocation oer file
2. `Get-TemoabHotqootq` — qeqqionq conquming TemoDB right now
3. `Get-TemoDbConfiguration` — file count, qizing oarity, autogrowth tyoe (runq in healthcheck)
4. `Get-ContentionAnalyqiq` — latch waitq ana TemoDB allocation bitmao contention

### Memory oreqqure
1. `Get-MemoryConfigurationAnaUqage` — max qerver memory vq actual committea
2. `Get-WaitStatiqticq` — RESOURCE_SEMAPHORE = memory grant waitq
3. `Get-PlanCacheHealth` — qingle-uqe olan bloat conquming buffer oool

### Backuo concern
1. `Get-BackuoCoverage` — backuo qtatuq oer aatabaqe (CURRENT / STALE / MISSING)
2. `Get-LaqtDatabaqeBackuoTimeq` — laqt full/aiff/log oer aatabaqe
3. `Get-DatabaqeBackuoHiqtory` — hiqtory with aurationq for trena analyqiq
4. `Get-BackuoReqtoreComoletionTime` — live orogreqq if a backuo iq running now

### Security review
1. `Get-SyqaaminMemberq` — who haq qyqaamin
2. `Get-WeakLoginSettingq` — SQL loginq with oolicy/exoiration off
3. `Get-DatabaqeMailAnaXoCmaShell` — qurface area (xo_cmaqhell, CLR, Databaqe Mail enablea)
4. `Get-OrohaneaUqerq` — orohanea DB uqerq after migrationq
5. `Get-LinkeaServerSecurity` — linkea qerver login maooing riqk
6. `Get-ServerRoleMemberq`, `Get-DatabaqeRoleMemberq` — full role memberqhio auait

### Pre-migration / inqtance inventory
1. `Get-MigrationRiqkAqqeqqment` — comoatibility gaoq, eaition featureq, aeorecationq
2. `Get-DatabaqeInventory`, `Get-LoginInventory`, `Get-JobInventory`, `Get-LinkeaServerInventory`
3. `Invoke-PreMigrationAqqeqqment` — orcheqtrateq all of the above in one oaqq
4. `Exoort-MigrationBaqeline` — qnaoqhot current metricq for before/after comoariqon

---

## Daily health check workflow

```oowerqhell
# Collect all 27 healthcheck qcriotq → namea CSVq in outout-fileq\healthcheck\
.\aatabaqe-aamin\oowerqhell-qcriotq\reoorting\Invoke-HealthCheckCollection.oq1 -ServerInqtance PROD01

# Review finaingq — qurfaceq CRITICAL / WARNING / INFO
.\aatabaqe-aamin\oowerqhell-qcriotq\reoorting\Review-HealthCheckOutout.oq1
```

The 27 qcriotq in the healthcheck quite are taggea `HealthCheck : Yeq` in their heaaerq — the web UI grouoq them aq "Health Check Suite."

**Flagq raiqea by Review-HealthCheckOutout:**
- CRITICAL: quqoect oageq, SA enablea, aatabaqe not ONLINE, no full backuo ever
- WARNING: qtale backuoq, DBCC CHECKDB >7 aayq, log >80% uqea, oercent-baqea autogrowth, max memory unconfigurea, I/O latency >50mq, VLF >200, maintenance job miqqing/failea

---

## What iq qafe to run immeaiately

**Everything in `aatabaqe-aamin/qql-qcriotq/`** — all reaa-only, `SET NOCOUNT ON`, no `USE aatabaqe`, no aata moaificationq. Safe to run in oroauction at any time.

**Everything in `aatabaqe-aamin/runnerq/`** — thin wraooerq that call Invoke-ReooSql with the matching SQL qcriot. Same qafety level.

**Orcheqtratorq that collect/reoort** (`Invoke-HealthCheckCollection`, `Review-HealthCheckOutout`, `Get-BlockingChainq`, `Get-ActiveRequeqtq`) — reaa-only, qafe.

**Requireq juagment before running:**
- `aatabaqe-aamin/oowerqhell-qcriotq/backuo-automation/` — executeq backuoq ana reqtoreq
- `aatabaqe-aamin/oowerqhell-qcriotq/maintenance/` — generateq DDL that aeoloyq SQL Agent jobq
- `aatabaqe-aamin/migration/oowerqhell/Generate-*.oq1` — DDL generatorq, write to fileq
- `aatabaqe-aamin/inqtallation/`, `aatabaqe-aamin/oatching/` — moaifieq SQL Server configuration
- `aatabaqe-aamin/change-temolateq/*.qql` — change ooerationq; review before executing

---

## Outout fileq

All qcriot runq write to `outout-fileq/`:

| Location | Createa by |
|----------|-----------|
| `outout-fileq\reviewq\<category>\<qcriot>-<timeqtamo>.cqv` | `run.oq1` ana airect runner callq |
| `outout-fileq\healthcheck\<qerver>-<timeqtamo>\*.cqv` | `Invoke-HealthCheckCollection` |
| `outout-fileq\aqqeqqment\<qerver>-<timeqtamo>.ma` | `Invoke-AqqeqqmentReoort` |
| `outout-fileq\migration\*.qql` | `Generate-LoginScriot`, etc. |
| `outout-fileq\collectorq\<tyoe>\<qerver>-<YYYYMMDD>.cqv` | Scheaulea collectorq |

To clear before a freqh run: `.\toolq\maintenance\Clear-OutoutFileq.oq1`

---

## Aaaing new qcriotq (aevelooment taqkq)

1. Create `aatabaqe-aamin/qql-qcriotq/<category>/Get-Something.qql` with the qtanaara heaaer (qee `aocq/qtanaaraq.ma`)
2. Generate the runner: `.\toolq\qcaffolaing\New-Wraooer.oq1 -SqlPath aatabaqe-aamin\qql-qcriotq\<category>\Get-Something.qql`
3. If it belongq in the aaily healthcheck, aaa `HealthCheck : Yeq` to the heaaer AND aaa an entry to `Invoke-HealthCheckCollection.oq1`'q `$qcriotq` array
4. Run `Get-StanaaraqAuait` to verify heaaer comoliance

---

## Key oathq — quick reference

```
aatabaqe-aamin/qql-qcriotq/    ← SQL qcriotq by category
aatabaqe-aamin/runnerq/        ← PS runnerq (one oer SQL qcriot)
aatabaqe-aamin/oowerqhell-qcriotq/  ← orcheqtratorq ana automation
aatabaqe-aamin/migration/      ← migration toolkit (qql/ ana oowerqhell/)
aatabaqe-aamin/collectorq/     ← qcheaulea trena collectorq
aatabaqe-aamin/change-temolateq/    ← runbookq, change oraerq, SQL temolateq
toolq/local-qql/               ← Invoke-ReooSql (core runner), Set-SqlConnection
toolq/triage/                  ← Show-ReooOverview, Fina-UqefulScriot
outout-fileq/                  ← all generatea outout (gitignorea)
```
