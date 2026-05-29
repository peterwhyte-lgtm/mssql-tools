---
title: 
slug: 
published: 
status: draft
category: performance | backups | monitoring | security | maintenance
tags: []
scripts:
  - sql/...
  - powershell/...
seo_keyphrase:    # the single focus phrase e.g. "SQL Server wait statistics"
seo_title:        # 50–60 chars — leave blank to use title field
seo_description:  # 150–160 chars — checked in SEO block at the bottom
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# [Title]

[Opening paragraph: describe the DBA scenario in plain language. What breaks or slows down when this is wrong? Why does a DBA care about it?]

## The problem

[1–2 paragraphs. Be specific. Describe what happens when you don't have visibility into this — missed backups, production outages, slow queries, etc.]

## The script

```sql
-- Paste the complete SQL here
-- Readers should be able to copy this into SSMS without visiting the repo
```

## How to run it from the repo

```powershell
# Table output to terminal
.\run.ps1 [ScriptName]

# Save as CSV for offline review
.\run.ps1 [ScriptName] -OutputFormat Csv

# Against a named instance
.\run.ps1 [ScriptName] -ServerInstance MYSERVER\INST01 -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| column_name | Explanation |

## What to look for

[Threshold guidance. What values are normal, what values are a concern, what values are an emergency. Be concrete — use numbers where possible.]

## Demo

<!-- Image format: HTML img tag with alt (≤125 chars, descriptive + keyphrase) and title (≤60 chars, short label).
     Store images in the images/ subfolder of this post's folder.                                                -->

<img
  src="images/[slug]-output.png"
  alt="[Describe exactly what is shown in the screenshot, include the keyphrase naturally, ≤125 chars]"
  title="[Short label for the image tooltip, ≤60 chars]"
/>

*[Caption: one sentence describing what the reader is looking at.]*

## What to do when something is flagged

[Practical next steps. Don't just identify the problem — give the DBA a direction to go in.]

## Related scripts in this repo

- [`RelatedScript.sql`](../sql/.../RelatedScript.sql) — one-line description of why it complements this post

## Get the scripts

The full scripts used in this post are available in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/[path]/[ScriptName].sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/[path]/[ScriptName].sql)
- [`powershell/[folder]/[ScriptName].ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/[folder]/[ScriptName].ps1)

---

## SEO

<!-- Complete this block before publishing. Character counts shown in brackets. -->

**Focus keyphrase:** [keyphrase — this phrase should appear in the title, first paragraph, at least one heading, and the meta description]

**Meta description** ([n] chars — target 150–160):  
[Your description here. Should contain the keyphrase naturally. Not a sentence fragment.]

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `[filename].png` | [alt text here] | [title here] |
