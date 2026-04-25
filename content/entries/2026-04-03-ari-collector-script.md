---
date: 2026-04-03
title: "our Azure inventory collector script"
tags:
  - azure
  - powershell
author: "system"
slug: "2026-04-03-ari-collector-script"
summary: "Building the ARI wrapper script to make Azure inventory collection and upload safer, clearer, and easier to run from Azure CloudShell or local PowerShell."
featured_image: "/entries/2026-04-03-ari-collector-script/og.png"
ai_note: true
draft: false
---
## Summary

This solution is about reliability over novelty. The script wraps
[Azure Resource Inventory (ARI)](https://github.com/microsoft/ARI) and adds
input validation, output cleanup, upload retries, and clearer failure
messages so customers can run it without guesswork.

**Why this matters:** ARI already handles inventory collection well. The
wrapper makes execution and artifact handling predictable across customer
environments.

The script entry point is intentionally simple. Run this from Azure CloudShell:

```powershell
irm https://data.<domain>.com/ari.ps1 | iex
```

*Note: until this script is live we're using a placeholder domain.*

It can also be downloaded and run locally:

```powershell
Invoke-WebRequest -Uri https://data.<domain>.com/ari.ps1 -OutFile ./ari.ps1
./ari.ps1
```

It can prompt for required values when they are not set in environment variables.

The ARI project already does the heavy lifting for discovery and reporting.
What we needed was a thin operational wrapper that:

- standardizes where artifacts land,
- applies consistent naming for customer upload targets,
- uploads outputs with retry behavior that surfaces HTTP errors.

## What the wrapper adds
The script keeps the ARI workflow operationally consistent:

- Input flow: `CustomerName` and `SasToken` can come from parameters or
  environment variables. If upload is enabled and values are missing, the
  script prompts interactively.
- Clean outputs: it clears the ARI output directory before each run to avoid
  stale files (`C:\AzureResourceInventory` on Windows,
  `$HOME/AzureResourceInventory` on Linux/Cloud Shell).
- Module checks: it ensures `AzureResourceInventory` and `Az.CostManagement`
  are available, then runs:

```powershell
Invoke-ARI -Lite -SecurityCenter -IncludeTags -IncludeCosts -ReportName $reportName
```

- Artifact selection: it picks the latest generated `*_Report_*.xlsx` and
  `*_Diagram_*.xml` files by timestamp.
- Upload safety: it uploads as `BlockBlob` with timeout-focused retries and
  returns HTTP status plus response details on failure.
- Container normalization: it lowercases customer names, collapses invalid
  characters to `-`, forces a `cust-` prefix, caps length, and applies a safe
  fallback when needed.

## Run modes

Interactive run:

```powershell
./ari.ps1
```

Parameterized run:

```powershell
./ari.ps1 -CustomerName contoso -SasToken '?sv=...'
```

Generate only (no upload):

```powershell
./ari.ps1 -CustomerName contoso -SkipUpload
```

## Verification

1. Confirm a new ARI report file is generated (`*_Report_*.xlsx`).
2. Confirm a new ARI diagram file is generated (`*_Diagram_*.xml`).
3. If upload is enabled, confirm both uploads complete without HTTP errors.
4. Confirm local output paths are shown at script completion.

## Operational Notes

- The script is designed to run in Azure CloudShell, Linux, or Windows
  PowerShell.
- It needs an authenticated Azure session before execution.
- It needs outbound access to PowerShell Gallery and the storage endpoint.
- It clears prior output content before generating a fresh inventory snapshot.
- It leaves local file paths visible at the end of execution for traceability.
- If upload fails, first check SAS validity/expiry and network egress.
