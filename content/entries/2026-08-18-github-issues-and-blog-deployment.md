---
date: 2026-08-18
title: "GitHub under load: building resilient deployments when your platform struggles"
tags:
  - github
  - ops
  - deployment
  - infrastructure
author: "meany"
slug: "2026-08-18-github-issues-and-blog-deployment"
summary: "How AI-generated code and exploding commit volume are stress-testing GitHub's infrastructure, and why deployment resilience means assuming GitHub will have infrastructure failures."
featured_image: "/entries/2026-08-18-github-issues-and-blog-deployment/og.png"
ai_note: true
draft: false
---

## The problem

GitHub is struggling. [An Ask HN thread](https://news.ycombinator.com/item?id=49332495) asking GitHub employees what's actually going on reveals the gap between corporate messaging and operational reality. GitHub's COO reported that commit volume hit 14x in the past year—1 billion commits in 2025 alone, with the pace accelerating. Most of that is AI-generated: code from Cursor, Claude, ChatGPT, and similar tools that generate dozens or hundreds of commits where a human might write one.

The infrastructure response has been predictably messy:
- Outages lasting hours, with no meaningful status updates
- API endpoints returning 5xx errors on otherwise valid requests
- Artifact storage expiring silently without clear signaling
- GitHub Actions workflows failing intermittently
- The gap between "everything is green" on status pages and "everything is broken for me right now"

The root causes are unclear (and GitHub isn't saying). Theories range from:
- Azure infrastructure capacity exhaustion and poor resource isolation
- Architectural decisions that don't scale to 14x commit volume
- GitHub Rails codebase hitting fundamental limits
- Lack of rate-limiting on AI-generated spam repos
- Simple mismanagement: "they have the money, they just didn't plan for this"

None of this is news if you've used GitHub recently. The question is: what do you do about it?

## The deployment response

Over the past 48 hours, I made three sequential fixes to my blog's polling-and-deployment script. Each one started from a different GitHub failure mode, and together they show how to build something that actually works when your infrastructure vendor is struggling.

### Fix 1: Assume artifacts expire silently

[commit 8806aa7](https://github.com/meany/log/commit/8806aa7ed8f4a5c5488351c3a1423556e97cd00d)

The poll agent treated the newest successful GitHub Actions run as the only candidate for deployment. GitHub's artifact retention is 7 days (configurable). For idle repos (no pushes for 7+ days), that meant every poll returned "artifact not found" → "Deploy failed" → Discord alert every 2 minutes.

**Fix:** Scan recent successful runs, find the newest one with a downloadable artifact, and deploy that. Mark expired artifacts as "not deployed" not "failed". Extend retention to 90 days.

**Lesson:** Assume your infrastructure provider's data will silently disappear. Plan for it.

### Fix 2: Make failure alerts useful

[commit 8c34c45](https://github.com/meany/log/commit/8c34c457cb22573a5b066e359c9c0f15e2f73b55)

After Fix 1, the script still failed on every poll for 48 hours but with a critical bug: the authentication header was hardcoded as `Bearer ***` instead of using the real GitHub token. Every artifact download returned HTTP 401 → "Deploy failed" → Discord alert every 2 minutes.

Beyond that specific bug, the broader issue: transient GitHub API failures would crash the script → supervisor restart → restart the poll loop → fail again → spam Discord.

**Fix:**
- Retry API calls with exponential backoff (3 attempts)
- Capture HTTP status at every failure point (API status, artifact download, unzip validation, rsync)
- Rate-limit Discord alerts: only the first failure per hour gets a message
- Back off the poll interval after failure (poll every 2min when healthy, every 10min after failure)
- Guard curl calls so network failures don't trigger set -e into a supervisor restart

**Lesson:** Your alerts must be as reliable as your deployment. If you alert on every transient failure, you've just built a spam machine.

### Fix 3: Distinguish GitHub failures from yours

[commit 4d0ed16](https://github.com/meany/log/commit/4d0ed16885f81ff9681fdeba209fadde795b8f21)

Now the hard one: GitHub itself was having an infrastructure incident (no public acknowledgment, but API stability was degraded). Every poll returned a 500 or connection failure. Discord was lighting up with "Deploy failed" messages every 10 minutes.

But here's the thing: it's not a failure I can fix. GitHub is down, artifacts are inaccessible, there's nothing to do. Alerting the channel every 10 minutes doesn't speed up GitHub's recovery—it just adds noise.

**Fix:** Classify failures by origin:
- **GitHub-origin failures** (API 5xx, network timeouts, artifact download 403/410, etc.) → log to stderr, do not alert Discord
- **Local failures** (unzip corruption, validation failure, rsync error) → alert to Discord with the reason
- **Auth failures** (401 on artifact download) → treat as local (our token, our responsibility)

The logic: a multi-hour GitHub incident must not page the ops channel. But a deployment validation failure should.

**Lesson:** Not every failure is equal. Infrastructure failures are someone else's problem; operational failures are yours.

## What this means

Three small commits, but they represent a philosophy:
- **Assume your platform will fail.** Don't wait until it's graceful; design for it now.
- **Make failures legible.** You need to know what kind of failure you're looking at and who owns it.
- **Don't amplify transient noise.** Rate-limit alerts, back off, and be precise about signal vs. noise.
- **Own your resilience.** If GitHub goes down and my blog goes down too, that's acceptable. But my ops channel shouldn't melt down.

GitHub is a critical infrastructure dependency for 100M developers. It's not going anywhere. But the comfort of "GitHub will always be up" is gone, and it's not coming back. The commit volume and AI-generated code are structural—not a bug, but a feature of how software development works now.

The question isn't "how do we fix GitHub?" (that's Microsoft's job). The question is "how do I build something that doesn't break when GitHub is having a bad day?" And the answer is three commits old.
