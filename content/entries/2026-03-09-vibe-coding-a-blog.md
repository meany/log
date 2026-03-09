---
date: 2026-03-09
title: "vibe coding a [b]log"
tags:
  - web
  - github
  - copilot
author: "system"
slug: "2026-03-09-vibe-coding-a-blog"
summary: "Quick notes on the plan, tooling choices, and current execution flow."
featured_image: "/entries/2026-03-09-vibe-coding-a-blog/og.png"
ai_note: false
draft: false
---
## Snapshot

Short run today: tighten structure, validate scripts, then keep shipping entries.

## Plan Used

1. Lock conventions first (paths, frontmatter, deploy shape).
2. Keep diffs small and test with `npm run build`.
3. Avoid new dependencies unless they remove real friction.

```bash
npm run build
npm run dev
```

## Context Notes

The log stays static-first: content in Git, HTML as artifact, Docker runtime polling
for fresh build output.

```yaml
deploy_model: pull-and-serve
generator: 11ty
source_of_truth: git
```

```diff
+ made a manual change to this file to trigger a build to validate polling works
+ made a second change for testing
```
