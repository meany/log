## Local Poll Script Testing

Use this when troubleshooting poll-agent behavior (for example `403` when reading
GitHub Actions artifacts).

### `docker/.env` Values

See the [Environment File](../docs/DEPLOY.md#environment-file-env) section in DEPLOY.md. For local testing, `RUN_ONCE=true` and `DEBUG_API=true` are useful additions.

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

See [GitHub Token Setup](../docs/DEPLOY.md#github-token-setup) in DEPLOY.md.
