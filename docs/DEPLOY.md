# Static Site Deployment

## Quick Start

1. Create `.env` file in the `docker/` directory:
   ```bash
   cp docker/.env.example docker/.env
   ```

2. Edit `docker/.env` and fill in required values (see "GitHub Token Setup" below)

3. Build and run:
   ```bash
   docker compose -f docker/docker-compose.prod.yml up -d
   ```

4. Check container logs:
   ```bash
   docker compose -f docker/docker-compose.prod.yml logs -f log-site
   ```

5. The site is now available on port 8069 (HTTP only)

## GitHub Token Setup

Create a **fine-grained personal access token** at `github.com/settings/tokens?type=beta` with these permissions:

### Repository access
- **Only select repositories**: Select your private repository

### Repository permissions (minimum required)
- **Actions**: Read-only
- **Metadata**: Read-only (mandatory, auto-granted)

### Token settings
- **Expiration**: 90 days (rotate regularly)

Do **not** grant any write permissions. This token is read-only for artifact access only.

## Environment File (`.env`)

```
GITHUB_OWNER=<your-username>
GITHUB_REPO=<your-repo-name>
GITHUB_TOKEN=ghp_your_fine_grained_token_here
WORKFLOW_FILE=build.yml
ARTIFACT_NAME=site
BRANCH=main
POLL_INTERVAL_SECONDS=120
```

## Architecture

Single container (`log-site` service) running:
- **Poll agent**: Checks GitHub Actions every 2 minutes (configurable) for new build artifacts
- **Nginx server**: Serves static files on port 8069

Both processes run together managed by supervisord. Logs are available via `docker compose logs`.

**Deployment workflow:**
- Content commits trigger `build.yml` on GitHub Actions, creating a build artifact
- Poll-agent immediately downloads and deploys the new artifact
- Docker commits (Dockerfile/docker/ changes) trigger `publish.yml` to rebuild and push image to ghcr.io
- **Important**: Images are only republished on container config changes, not on content updates
- The bundled static build ensures the service works immediately on first start
- Poll-agent keeps the site current between container rebuilds

**Volumes:** Production compose mounts only `/state` (for poll tracking), not `/site`,
so the image-bundled site is visible on cold start and polling updates overlay on top.

## Verification

```bash
# Check container is running
docker compose -f docker/docker-compose.prod.yml ps

# View logs (pull agent + nginx)
docker compose -f docker/docker-compose.prod.yml logs log-site

# Test the service
curl http://localhost:8069/
curl http://localhost:8069/feed.xml
```

## Compose Project Name

Compose files set `name: log-meany-xyz`, so Docker resources are prefixed with
that project name instead of the folder name.

## Network Setup

The container exposes port 8069. Configure your external network routing (TLS termination, reverse proxy, etc) as needed for your infrastructure.

When the poll agent detects a new artifact, it downloads and extracts to `/site`, which nginx immediately serves.

- `.env` is git-ignored to prevent token leaks
- Token has read-only access to Actions artifacts only
- No write permissions granted to any repository resources
- Token is scoped to a single repository
- Rotate token regularly using GitHub's expiration feature
