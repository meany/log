# Static Site Deployment

## Quick Start

The site ships as a container image (`ghcr.io/meany/log:latest`) that bundles a
pre-built static `_site` and serves it with nginx. Deploying an update is a
single manual command on the host.

1. On the meany.xyz host, pull the latest image and recreate the container:

   ```bash
   docker compose -f docker/docker-compose.prod.yml up -d --pull always
   ```

2. Confirm the container is healthy:

   ```bash
   docker compose -f docker/docker-compose.prod.yml ps
   ```

3. Verify the site:

   ```bash
   curl http://localhost:8069/
   curl http://localhost:8069/feed.xml
   ```

The site is available on port 8069 (HTTP only).

## How updates reach production

- Content commits to `main` trigger `.github/workflows/build.yml`, which builds
  the site and uploads the `_site` artifact.
- Commits to `Dockerfile` or `docker/**` trigger `.github/workflows/publish.yml`,
  which rebuilds the image and pushes it to `ghcr.io/meany/log:latest`.
- The image bundles a full static build, so every published image serves the
  current content out of the box.
- **Publishing an image does not change the running container.** The operator
  redeploys manually with `docker compose up -d --pull always` to pull the new
  image and restart the container.

There is no auto-poll, no auto-pull, and no deploy notification. Deploying is
always a deliberate manual action.

## Architecture

A single container (`log-site`) runs nginx in the foreground and serves the
bundled `/site` directory on port 8069. The static build is baked into the image
at build time, so a cold start serves the latest published content immediately.

## Compose Project Name

Compose files set `name: log-meany-xyz`, so Docker resources are prefixed with
that project name instead of the folder name.

## Network Setup

The container exposes port 8069. Configure your external network routing (TLS
termination, reverse proxy, etc.) as needed for your infrastructure.
