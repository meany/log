## Local Poll Script Testing

Use this when troubleshooting poll-agent behavior (for example `403` when reading
GitHub Actions artifacts).

### Required `docker/.env` Values

```dotenv
GITHUB_OWNER=meany
GITHUB_REPO=log
GITHUB_TOKEN=<fine-grained-pat>
POLL_INTERVAL_SECONDS=120
```

The following values are fixed in `docker/poll-and-deploy.sh` and are not
configured via `.env`:

- `WORKFLOW_FILE=build.yml`
- `BRANCH=main`
- `ARTIFACT_NAME=site`

### Run Poll Script Once (Local)

```bash
docker compose -f docker/docker-compose.prod.yml run --rm \
  -e RUN_ONCE=true \
  -e DEBUG_API=true \
  log-site /app/poll-and-deploy.sh
```

### View Poll-Agent Logs

`poll-agent` output is now wired to container stdout/stderr via supervisord, so
you can inspect script `echo` output with:

```bash
docker compose -f docker/docker-compose.prod.yml logs -f log-site
```

### Required Token Permission

For `GITHUB_TOKEN` (fine-grained PAT), grant repository access to `meany/log`
and set:

- `Actions: Read`
