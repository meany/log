# Local Development

Test the built site in Docker before deploying to production.

## With local build (test during development)

```bash
# Build the deployment image locally from current code.
# This runs `npm run build` inside Docker and bundles `_site` into the image.
docker compose -f docker/docker-compose.local.yml up -d

# View logs
docker compose -f docker/docker-compose.local.yml logs -f log-site

# Access site
curl http://localhost:8069/
```

## With pre-built image from ghcr.io

First, ensure you have valid `.env` file in `docker/` with GitHub credentials.

```bash
# Pull the latest published image and run
docker compose -f docker/docker-compose.prod.yml up -d

docker compose -f docker/docker-compose.prod.yml logs -f log-site
```

## Testing the site

```bash
# Index page
curl http://localhost:8069/

# Atom feed
curl http://localhost:8069/feed.xml

# Specific entry (example)
curl http://localhost:8069/entries/2026-03-08-first-log/

# Tags
curl http://localhost:8069/tags/
```

## Stopping the container

```bash
docker compose -f docker/docker-compose.local.yml down
# or
docker compose -f docker/docker-compose.prod.yml down
```

## Container Architecture

The single container runs:
- **nginx**: serves static files on port 8069
- **poll-agent**: checks GitHub Actions for new builds (production mode only)

Both processes are managed by supervisord and log output is available via
`docker compose logs`.

## Deployment Workflow

**Two independent CI pipelines:**

1. **Content builds** (`build.yml`): Triggers on any push to `main`
   - Runs `npm run build` to generate static HTML
   - Uploads build artifact to GitHub Actions
   - Poll-agent downloads and deploys immediately

2. **Container publishes** (`publish.yml`): Triggers only on Dockerfile or docker/ changes
   - Rebuilds image with new bundled site + latest code
   - Publishes to `ghcr.io/meany/log:latest`
   - **Does not** republish on content-only commits

**Result:** Content updates deploy immediately via polling. The bundled Docker image may contain older posts until the next Docker-level change, but the poll-agent keeps the site current.

**Versioning:** Images use git commit history as the version source of truth (no manual semantic versions). Both tags point to the latest build.

## Poll Agent Local Troubleshooting

Use these checks when the container logs show `403` or artifact download failures.

1. Validate `docker/.env` values:
    - `GITHUB_OWNER=meany`
    - `GITHUB_REPO=log`
    - `WORKFLOW_FILE=build.yml`
    - `BRANCH=main`
    - `ARTIFACT_NAME=site`

2. Verify token scope for this repo:
    - Fine-grained PAT must include repository access to `meany/log`
    - Permission required: `Actions: Read`

3. Run poll-agent once with API debug output:

```bash
docker compose -f docker/docker-compose.prod.yml run --rm \
   -e RUN_ONCE=true \
   -e DEBUG_API=true \
   log-site /app/poll-and-deploy.sh
```

4. If you still see `403`, confirm with direct API call from the host:

```bash
curl -i \
   -H "Accept: application/vnd.github+json" \
   -H "Authorization: Bearer $GITHUB_TOKEN" \
   "https://api.github.com/repos/meany/log/actions/workflows/build.yml/runs?branch=main&status=success&per_page=1"
```

If response headers include `x-accepted-github-permissions: actions=read`, the token is missing required `Actions: Read` access or is not authorized for the repository.
