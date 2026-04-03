---
date: 2026-04-03
title: "our Azure inventory collector script"
tags:
  - azure
  - powershell
  - ops
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

The script entry point is intentionally simple:

```powershell
irm https://data.<domain>.com/ari.ps1 | iex
```

*Note: until this script is live we're using a placeholder domain.*

It can also be downloaded and run locally:

```powershell
Invoke-WebRequest -Uri https://data.<domain>.com/ari.ps1 -OutFile ./ari.ps1
pwsh ./ari.ps1
```

It can prompt for required values when they are not set in environment variables.

The ARI project already does the heavy lifting for discovery and reporting.
What we needed was a thin operational wrapper that:

- standardizes where artifacts land,
- applies consistent naming for customer upload targets,
- uploads outputs with retry behavior that surfaces HTTP errors.

## What the wrapper adds

### Input and prompt flow

The script supports both parameterized and prompt-driven usage:

- `CustomerName` and `SasToken` can come from parameters or environment
  variables. We usually provide these values during customer onboarding.
- `-SkipUpload` keeps generation local and bypasses upload requirements. If
  upload is not skipped, missing values are prompted interactively.

### Clean output lifecycle

Before each run, it resets any existing reports in the ARI output folder:

- Windows: `C:\AzureResourceInventory`
- Linux/Cloud Shell: `$HOME/AzureResourceInventory`

That keeps each run deterministic and avoids stale file confusion.

### Module bootstrapping

The wrapper ensures required modules exist before execution:

- `AzureResourceInventory`
- `Az.CostManagement`

Then it imports ARI and invokes:

```powershell
Invoke-ARI -Lite -SecurityCenter -IncludeTags -IncludeCosts -ReportName $reportName
```

### Artifact selection

After generation, it selects the latest matching files by timestamp:

- `*_Report_*.xlsx`
- `*_Diagram_*.xml`

This avoids hardcoding file names while still producing predictable upload units.

### Safer upload behavior

Upload is done with explicit blob semantics and retry-on-timeout:

- Uses `PUT` with `x-ms-blob-type: BlockBlob`
- Retries up to 3 attempts on timeout-like failures
- Includes a configurable timeout (default 300 seconds)

The retry logic only runs on timeout signals, not on all HTTP failures.
When an upload fails, the script extracts the HTTP status code, service
response body, and exception text. It then returns a support-friendly
single-line message to simplify troubleshooting.

### Customer container normalization

The wrapper normalizes customer names into valid container segments:

- lowercase,
- non-alphanumeric characters collapsed to `-`,
- forced `cust-` prefix,
- capped length,
- safe fallback if input reduces to empty.

This prevents malformed paths and keeps naming stable across runs.

## Prerequisites

- An authenticated Azure session before script execution.
- Outbound access to PowerShell Gallery for module installation.
- Outbound access to the target storage account endpoint for uploads.

## Run Modes

### Interactive run

```powershell
pwsh ./ari.ps1
```

### Parameterized run

```powershell
pwsh ./ari.ps1 -CustomerName contoso -SasToken '?sv=...'
```

### Generate only (no upload)

```powershell
pwsh ./ari.ps1 -CustomerName contoso -SkipUpload
```

## Verification

1. Confirm a new ARI report file is generated (`*_Report_*.xlsx`).
2. Confirm a new ARI diagram file is generated (`*_Diagram_*.xml`).
3. If upload is enabled, confirm both uploads complete without HTTP errors.
4. Confirm local output paths are shown at script completion.

## Troubleshooting

- If upload fails with authorization errors, verify the SAS token is valid and
  not expired.
- If module installation fails, check network egress rules and PowerShell
  Gallery reachability.
- If no report files are generated, verify ARI module import succeeded and the
  Azure session context is correct.

## Operational Notes

- The script is designed to run in Azure CloudShell, Linux, or Windows
  PowerShell.
- It expects an authenticated Azure session before invocation.
- It clears prior output content before generating a fresh inventory snapshot.
- It leaves local file paths visible at the end of execution for traceability.
