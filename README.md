# log.meany.xyz

[![Build][build-badge]][build-link]
[![Publish][publish-badge]][publish-link]

A minimalist static engineering log built with 11ty, Markdown, and Docker. Git is the source of truth; static HTML is the build artifact.

[build-badge]: https://github.com/meany/log/actions/workflows/build.yml/badge.svg
[build-link]: https://github.com/meany/log/actions/workflows/build.yml
[publish-badge]: https://github.com/meany/log/actions/workflows/publish.yml/badge.svg
[publish-link]: https://github.com/meany/log/actions/workflows/publish.yml

## Structure

- `content/entries/` — Log entries in Markdown + YAML frontmatter
- `css/` — Single stylesheet with terminal aesthetic
- `docker/` — Container runtime (nginx + poll-agent)
- `docs/` — Deployment and development documentation
- `.github/` — Build automation and instructions

## Quick Start

```bash
npm install
npm run build        # one-time build
npm run dev          # watch + local server at http://localhost:8080
npm run entry        # create a new entry interactively
```

See [docs/DOCKER.md](docs/DOCKER.md) for local Docker testing and [docs/DEPLOY.md](docs/DEPLOY.md) for production setup.

## Creating entries

```bash
npm run entry
```

This prompts for title, tags, and author (default: `meany`), then creates a dated file in `content/entries/`.

See [.github/instructions/markdown.instructions.md](.github/instructions/markdown.instructions.md) for content guidelines.

## Deployment

GitHub Actions builds on `main` push; poll-agent pulls artifacts to production. See [docs/DEPLOY.md](docs/DEPLOY.md) and [docs/DOCKER.md](docs/DOCKER.md) for details and architectural model.

## Design principles

- No database, no runtime server logic, no client-side API calls
- Static site generation with 11ty (swappable backend)
- Git + GitHub Actions + Docker = durable, reproducible deployment
- WCAG 2.2 Level AA accessibility
- Plain language documentation

## Documentation

- [plan.md](plan.md) — Architecture decisions and locked design
- [docs/DOCKER.md](docs/DOCKER.md) — Local development with Docker
- [docs/DEPLOY.md](docs/DEPLOY.md) — Production deployment setup
- [.github/instructions/](.github/instructions/) — Content guidelines and accessibility standards
