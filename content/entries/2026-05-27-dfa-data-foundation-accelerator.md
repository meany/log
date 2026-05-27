---
date: 2026-05-27
title: "introducing the Data Foundation Accelerator (DFA)"
tags:
  - azure
  - marketplace
  - github
author: "system"
slug: "2026-05-27-dfa-data-foundation-accelerator"
summary: "The Data Foundation Accelerator deploys a minimum viable modern data platform on Azure — Fabric capacity, ADLS Gen2, SQL, Key Vault, and optional API ingestion — via a single Marketplace offer."
featured_image: "/entries/2026-05-27-dfa-data-foundation-accelerator/og.png"
ai_note: true
draft: false
---
## Summary

The [Data Foundation Accelerator (DFA)](https://github.com/eGroupEnabling/DFA) is a governed Azure data platform deployed from a single Azure Marketplace offer. It provisions the core services needed for analytics and AI workloads — storage, networking, secrets, relational data, and optionally Fabric capacity — in one pass. Standing up a repeatable data foundation across customer tenants is slow when done manually, so, DFA compresses that into a portal flow with opinionated defaults.

## What it deploys

Core resources (always provisioned):

- Azure Virtual Network with a default subnet and an optional private endpoints subnet
- Azure Data Lake Storage Gen2 with `raw`, `ingestion`, `archive`, `function-host`, and `function-data` containers
- Azure Key Vault for secrets and deployment configuration
- Azure SQL Server and Azure SQL Database for governed relational storage

Optional resources (selected at deploy time):

- **Microsoft Fabric capacity** — `none` (attach existing/trial), `initial` (F2), or `production` (F4 by default, SKU override up to F2048)
- **Defender for Cloud** configuration applied at subscription scope
- **API ingestion Function App** for external API collection
- **API Management** for governed downstream consumption

## Deploy flow

The entry point is the Azure Marketplace offer:

1. Select subscription, resource group, and region.
2. Choose a Fabric capacity option: `none`, `initial`, or `production`.
3. Provide customer contact details (used by eGroup for installation tracking).
4. Configure private endpoints, Defender for Cloud, API ingestion, and SQL credentials as needed.
5. Start the deployment and monitor in the target resource group.

For automation and validation scenarios, the ARM template at `src/mainTemplate.json` can be deployed directly.

## Sample labs

The `samples/labs/` directory includes five optional walkthroughs that build on the deployed foundation:

- **DFA01** — SQL inventory walkthrough
- **DFA02** — CSV ingestion walkthrough
- **DFA03** — Public API JSON walkthrough
- **DFA04** — Power BI report walkthrough
- **DFA05** — Cost monitoring walkthrough

## Notes

- The `none` Fabric capacity option skips capacity creation entirely; attach an existing capacity or activate a trial separately in the Fabric portal.
- Docs cover deployment prerequisites, architecture topology, cost estimation, and troubleshooting.
