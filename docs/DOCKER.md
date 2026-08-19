## Local Docker Build

Build the image locally to verify the container serves the static site:

```bash
docker compose -f docker/docker-compose.local.yml build
```

Run it:

```bash
docker compose -f docker/docker-compose.local.yml up -d
```

Check it is serving:

```bash
curl http://localhost:8069/
curl http://localhost:8069/feed.xml
```

View logs:

```bash
docker compose -f docker/docker-compose.local.yml logs -f log-site
```

Stop it:

```bash
docker compose -f docker/docker-compose.local.yml down
```

## Notes

The image runs nginx directly (`nginx -g "daemon off;"`) — there is no
supervisord and no background poll process. nginx serves the `_site` build that
was copied into the image at build time.
