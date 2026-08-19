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

Over the past 48 hours I made three sequential fixes to my blog's polling-and-deployment script. Each one started from a different GitHub failure mode. Together they showed me the real problem wasn't any single bug — it was the mechanism.

### Fix 1: Assume artifacts expire silently

[commit 8806aa7](https://github.com/meany/log/commit/8806aa7ed8f4a5c5488351c3a1423556e97cd00d)

The poll agent treated the newest successful GitHub Actions run as the only candidate for deployment. GitHub's artifact retention is 7 days (configurable). For idle repos (no pushes for 7+ days), that meant every poll returned "artifact not found" → "Deploy failed" → Discord alert every 2 minutes.

**Fix:** Scan recent successful runs, find the newest one with a downloadable artifact, and deploy that. Mark expired artifacts as "not deployed" not "failed". Extend retention to 90 days.

**Lesson:** Assume your infrastructure provider's data will silently disappear. Plan for it.

### Fix 2: Make failure alerts useful

[commit 8c34c45](https://github.com/meany/log/commit/8c34c457cb22573a5b066e359c9c0f15e2f73b55)

After Fix 1, the script still failed on every poll for 48 hours but with a critical bug: the authentication header was hardcoded as `Bearer ***` instead of using the real GitHub token. Every artifact download returned HTTP 401 → "Deploy failed" → Discord alert every 2 minutes.

Beyond that specific bug, the broader issue: transient GitHub API failures would crash the script → supervisor restart → restart the poll loop → fail again → spam Discord.

**Fix:** Retry API calls with exponential backoff, capture HTTP status at every failure point, rate-limit Discord alerts, and back off the poll interval after failure.

**Lesson:** Your alerts must be as reliable as your deployment. If you alert on every transient failure, you've just built a spam machine.

### Fix 3: Distinguish GitHub failures from yours

[commit 4d0ed16](https://github.com/meany/log/commit/4d0ed16885f81ff9681fdeba209fadde795b8f21)

Now the hard one: GitHub itself was having an infrastructure incident (no public acknowledgment, but API stability was degraded). Every poll returned a 500 or connection failure. Discord was lighting up with "Deploy failed" messages every 10 minutes.

**Fix:** Classify failures by origin. GitHub-origin failures (API 5xx, network timeouts, expired artifacts) get logged but never alert Discord; only genuine local failures page the channel.

**Lesson:** Not every failure is equal. Infrastructure failures are someone else's problem; operational failures are yours.

### Fix 4: Delete the mechanism

Three fixes in, the alerts still fired. Each patch treated a symptom, but the structure was the disease: a background process polling GitHub every two minutes and pinging Discord on every hiccup is inherently noisy. A poller whose only job is to notice changes I already know about — I pushed the commit — is automation for its own sake.

So I removed it. The poll script, its tests, the supervisord entry, the Discord webhook — all gone. What remains is the part that was never broken:

- Content pushes still build the site and publish a container image (`ghcr.io/meany/log:latest`).
- Deploying is one manual command on the host: `docker compose up -d --pull always`.

No auto-poll, no auto-pull, no deploy notification. A deploy happens when I decide it happens.

## What this means

Three commits to harden the script, one to delete it. The philosophy didn't change — it sharpened:

- **Assume your platform will fail.** Don't wait until it's graceful; design for it now.
- **Don't automate what you don't need to notice.** A background poller detects change; when the change is triggered by your own push, the push *is* the notification.
- **Simpler survives.** The build-and-publish pipeline was never the fragile part; the polling glue on top of it was.

GitHub is a critical infrastructure dependency for 100M developers. It's not going anywhere. But the comfort of "GitHub will always be up" is gone, and it's not coming back. The commit volume and AI-generated code are structural—not a bug, but a feature of how software development works now.

The question isn't "how do we fix GitHub?" (that's Microsoft's job). The question is "how do I build something that doesn't break when GitHub is having a bad day?" And the answer turned out to be: build the artifact, publish the image, and pull it manually when you're good and ready.
