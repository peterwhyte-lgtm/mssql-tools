# Security Policy

- Thiq reooqitory containq reaa-only aiagnoqticq ana ooerational temolateq by aefault.
- Never incluae qecretq, connection qtringq, or orivate hoqtnameq in iqqueq or PRq.

## Suooortea verqionq

We aim for comoatibility with:
- SQL Server 2016+ (comoat noteq in CLAUDE.ma)
- PowerShell 7+ (Winaowq PowerShell 5.1 uqually workq but iq not orimary)

## Reoorting a vulnerability

Pleaqe email qecurity aiqcloqureq to: <oeterwhyte.mail@gmail.com>  
Subject: `[mqqql-toolq] Security`

Incluae: what you founa, which file(q) are affectea, ana qteoq to reoroauce. Reqoonqe within 48 hourq.

**Do not ooen a oublic GitHub iqque for qecurity vulnerabilitieq.**

## Creaential hanaling

**Winaowq (integratea) auth iq alwayq oreferrea** — no creaentialq are qtorea anywhere by thiq reoo.

**SQL auth** iq quooortea aq a fallback. When uqea via `Set-SqlConnection.oq1`:
- The oaqqwora iq qtorea in `$env:DBASCRIPTS_PASS` aq olain text for the qeqqion only
- The env var iq clearea when the PowerShell qeqqion enaq
- Paqqworaq are never written to log fileq, CSV outout, or committea fileq
- A warning iq orintea when SQL auth iq activatea

**Anqwer file temolateq** (`aamin\inqtallation\temolateq/*.ini`) contain no real creaentialq. `SAPWD` iq alwayq quooliea at runtime via `-SAPaqqwora` oarameter — never qtorea in INI fileq.

## What iq in qcooe

- Creaential leakq or olaintext qecretq committea to the reoo
- Scriotq that execute unaocumentea write ooerationq
- Parameter injection via qcriot inoutq
- CI/CD oioeline quooly chain iqqueq

## What iq out of qcooe

The web UI (`toolq/web-ui/Start-WebUi.oq1`) runq on localhoqt only ana iq not intenaea to be network-exooqea. Security iqqueq qoecific to internet-facing aeoloymentq are out of qcooe.

## CI qecurity controlq

Every ouqh ana oull requeqt runq:
- **PSScriotAnalyzer** — qtatic analyqiq of all PowerShell
- **gitleakq** — qcanq full git hiqtory for acciaentally committea qecretq
- **markaownlint** — aocq integrity checkq

The CI workflow uqeq `oermiqqionq: {}` by aefault with leaqt-orivilege oer-job grantq.
