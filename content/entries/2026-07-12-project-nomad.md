---
date: 2026-07-12
title: "project n.o.m.a.d.: ollama, embedding speeds, best practices, and management"
tags:
  - nomad
  - ollama
  - docker
  - tooling
  - ops
  - ai
author: "stang"
slug: "2026-07-12-project-nomad"
summary: "Field notes from tuning a Project N.O.M.A.D. deployment on an AMD 780M iGPU, moving embeddings from CPU to ROCm, and safely handling advanced container/database edits."
featured_image: "/entries/2026-07-12-project-nomad/nomad-ollama-edit-app.png"
ai_note: true
draft: false
---

## Snapshot

[Project N.O.M.A.D.](https://www.projectnomad.us/) is an offline-first AI and
knowledge system designed for local, resilient workflows. This write-up covers
what happened when I pushed my deployment past the default setup, mostly around
getting Ollama to use the AMD 780M iGPU via ROCm and making advanced edits that
the current UI does not expose.

Short version: I moved embedding throughput from a rough CPU estimate of about
2.4 chunks/sec to around 12 chunks/sec (about 6x), while staying inside the
Nomad ecosystem so built-in context links and local docs workflows still work.

## Hardware and model setup

I used a prebuilt
[MINISFORUM UM790 Pro (32GB RAM + 1TB SSD)](https://store.minisforum.com/products/minisforum-um790-pro-mini-pc).
For my use case, I could not build an equivalent box cheaper, and this one
arrived quickly.

- Chat model: `llama3.1:8b-instruct-q4_K_M`
- Embedding model: `nomic-embed-text:v1.5`

## Immediate pain

Out of the box, the deployment detected capable hardware, but the running
Ollama setup did not actually use the AMD 780M through the ROCm image path I
expected.

I also noticed the embedding model is currently hardcoded. I would like to see
an option in the interface to override `nomic-embed-text:v1.5` directly. I'll
submit a feature request or PR once I get around to it.

Separately, I wanted access to advanced Docker settings in the app editor,
especially full control of host devices and low-level container config. I tested
standalone Ollama with Open WebUI and LM Studio, but neither had reliable remote
ollama connectivity that I needed. I switched to Jan.ai, which has solid chat
features and cleaner remote model integration via HTTP endpoint config.

The main goal was to stay inside the project's ecosystem so native features like
context links into offline documentation continue to work cleanly. For my setup,
the out-of-box flow plus Jan.ai support ended up being the better path.

## Docker screenshots

The two screenshots below show what I was working with while testing app-level
settings and quick Docker edits. Specifically, I needed to deploy phpMyAdmin to edit the database. More on that in the sections below.

![Screenshot of Nomad Edit App for Ollama ROCm container showing custom env vars, volume mount, and port mapping.](/entries/2026-07-12-project-nomad/nomad-ollama-edit-app.png)

![Screenshot of Nomad Edit App for phpMyAdmin showing database utility setup and environment variable.](/entries/2026-07-12-project-nomad/nomad-phpmyadmin-edit-app.png)

## Container config

This is the exact `container_config` payload I used for the Ollama container
(listed as "AI Assistant" in the app). It had to be manually set in the database
since the UI doesn't expose those fields:

```json
{
  "Env": [
    "OLLAMA_HOST=0.0.0.0:11434",
    "HSA_OVERRIDE_GFX_VERSION=11.0.2",
    "OLLAMA_IGPU_ENABLE=1"
  ],
  "HostConfig": {
    "Binds": [
      "/opt/project-nomad/storage/ollama:/root/.ollama"
    ],
    "Devices": [
      {
        "PathOnHost": "/dev/kfd",
        "PathInContainer": "/dev/kfd",
        "CgroupPermissions": "rwm"
      },
      {
        "PathOnHost": "/dev/dri",
        "PathInContainer": "/dev/dri",
        "CgroupPermissions": "rwm"
      }
    ],
    "PortBindings": {
      "11434/tcp": [
        {
          "HostPort": "11434"
        }
      ]
    },
    "RestartPolicy": {
      "Name": "unless-stopped"
    }
  },
  "ExposedPorts": {
    "11434/tcp": {}
  }
}
```

## Throughput notes

My CPU-only baseline processed about 414,256 chunks in roughly 48 hours (around
2.4 chunks/sec, conservative estimate). After moving to the AMD GPU path, I
measured roughly 12 chunks/sec.

## Direct DB editing with phpMyAdmin (advanced users only)

> Warning
> Editing database rows or container settings outside the normal UI can break
> deployments, cause data loss, and leave services in unsupported states. Only
> do this if you understand SQL, Docker, and rollback/recovery steps.

Because the only way to edit docker configurations was directly in the database, phpMyAdmin makes this faster:

- Server: `nomad_mysql`
- User: `nomad_user`
- Password: pull from `/opt/project-nomad/compose.yml`

From there, you can update records in the `services` table, including removing
the `modified` tag or editing the `container_config` column directly.

## Feature requests I would like to see

1. Add an **Advanced** section in Edit App that allows full manual Docker
   configuration editing (raw JSON or equivalent).
2. Allow users to override the embedding model in the UI instead of hardcoding
   `nomic-embed-text:v1.5`.

Both changes would reduce friction for power users while keeping standard users
on a safe default path.

## System prompt

I currently use this full prompt in Jan.ai to shape my conversations with
offline data:

```text
You are Nomad Assistant, a concise survival and logistics AI inside Project N.O.M.A.D.

Primary goal:
Give fast, accurate, actionable answers for survival, preparedness, off-grid living, navigation, logistics, gear selection, basic medical guidance, and field decision-making.

Operating rules:
- Answer directly first. Do not preface with filler.
- Be concise. Prefer short, concrete answers over broad explanation.
- Be deterministic. State uncertainty clearly instead of guessing.
- Be practical. Optimize for limited power, limited connectivity, and limited supplies.
- Be safe. Do not encourage reckless, illegal, or harmful actions.
- Do not roleplay or use persona language.
- Ask at most one clarifying question only if it is required to avoid a bad answer. Otherwise provide the best supported answer.

Source priority:
1. Nomad Knowledge Base and local tools
2. User-provided context
3. Reliable external sources if available
4. Clearly stated best judgment when sources are unavailable

Research behavior:
- Use Nomad KB, Tools, and Skills when available.
- If external data is needed and internet is available, use it and cite the source.
- If internet is unavailable, say so and continue with local knowledge or best-supported guidance.
- Never invent citations, links, or KB entries.

Response format:
- Summary: 2–3 sentences max
- Action Steps: 3–7 bullets or numbered steps
- Reasoning: only include if it adds value, keep it short
- References: KB entries, tools, or external links only when available

Style:
- Direct, technical, calm, and efficient.
- Use short sections and short bullets.
- Every recommendation should include a brief reason.
- Prefer the shortest answer that fully solves the request.

Survival priorities:
Immediate threats, medical stability, water, shelter, fire, navigation, signaling, food, long-term sustainability.
```

## Closing note

I was definitely stress-testing this harder than most normal deployments. I got
frustrated and sideways during troubleshooting, but came out the other side with
a setup that performs meaningfully better while staying inside the project
ecosystem.

Huge thanks to [Crosstalk Solutions](https://www.crosstalksolutions.com/) and
the team for building this project.