---
date: 2026-04-25
title: hermes and the ADA multi-agent setup
tags: [hermes, ada, ai-agents, architecture, tooling]
author: stang
slug: hermes-and-ada-setup
summary: 'A field note on the current Hermes agent framework and the ADA orchestration layer — what it is, how it works, and where the tradeoffs sit after a few weeks of daily use.'
featured_image: null
ai_note: true
---

## Snapshot

Dug into the internal agent setup today to write it up for the log. Building a multi-profile Hermes framework with a thin coordination layer called ADA on top. What follows is a straight description of how it all fits together, what works, and what still needs attention.

## What Hermes is

Hermes is the agent runtime. It runs as a persistent background process with full tool access — file reads/writes, terminal, web search, browser, code execution, image generation, and more. It maintains long-term context across sessions via Honcho (a persistent memory layer) and connects to messaging platforms (Telegram, Discord, etc.) via a gateway service.

The key property is that Hermes is **profile-based**. Each profile is an independent agent context with its own SOUL.md (behavior definition), memory, environment variables, and API server port. Profiles share nothing by default — no shared state, no shared tools beyond the base set. Communication between profiles goes through explicit API calls.

Current profiles:

- `default` — orchestrator / entry point for human requests
- `pm` — product owner and task coordinator
- `architect` — solution design and technical review
- `engineer` — implementation (delegated, not direct)
- `designer` — UI/UX and visual design (delegated)
- `security` — threat modeling and security review
- `devops` — CI/CD, deployment, and release

## What ADA is

ADA (Agentic Dev Agency) is the orchestration layer on top of the raw Hermes profiles. The goal is to turn a human request into structured work with clear ownership:

1. The orchestrator receives the request.
2. If the work is ambiguous or multi-step, it creates or updates a `planning/prd-<feature>.md` — a lightweight spec with goals, scope, acceptance criteria, and open questions.
3. Work is dispatched to the appropriate profile via the API registry. The orchestrator never writes implementation code directly — it routes to the engineer or designer profiles instead.
4. Profiles return artifacts (files, decisions, test results) and the orchestrator tracks whether the work is complete or needs escalation.

The coordination rules live in `ADA_REGISTRY.md`. Key conventions:

- All profile-to-profile calls use OpenAI-compatible endpoints on loopback (`127.0.0.1:8xx0-8xx6`).
- Auth is bearer token per profile — unique per profile, never shared.
- Conversation IDs follow a naming scheme: `<feature>-<task>-<caller>-to-<callee>`.
- Specialist profiles are treated as long-lived agents with their own memory — do not delegate by changing directories or running shell commands against another profile's context.

## What works well

**Clear routing.** The profile system means a web app request goes to `designer` for visuals and `engineer` for implementation. Neither has to know the other's internals — they communicate through the orchestrator.

**Persistent memory.** Honcho gives every profile a durable view of past sessions, user preferences, and project context. The orchestrator doesn't have to ask for the same context every turn.

**Parallel dispatch.** Independent tasks can be dispatched to different profiles simultaneously via batch delegation.

**Gateway integration.** The Telegram gateway makes the orchestrator feel immediately responsive — it can run in the same chat as the human rather than behind a web UI.

## What needs attention

**Delegate friction.** The orchestrator has a tendency to do simple coding tasks directly rather than routing them, especially when speed matters. The current fix is a triage prompt on ambiguous/simple requests — ask the user if it should route to profiles. Not ideal but functional.

**Context isolation.** Profiles don't share working state. If the architect makes a decision that the engineer needs to know, it has to be surfaced through the orchestrator or written to a shared file. For now, the orchestrator writes decisions into the PRD and the engineer reads it — works but verbose.

**Entrypoint bottleneck.** Everything still flows through `default`. If the orchestrator is saturated, no work queues — it just backs up. No work distribution between orchestrators yet.

## Entry notes

- This entry written as output from a direct request to the orchestrator — not a PRD-driven task, not routed to a specialist.
- The `.md` file was generated on the local filesystem and delivered via Telegram.
- Will revisit this structure once the triage mechanism has been exercised more and the delegate-on-default pattern is more settled.
