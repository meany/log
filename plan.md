# plan.md

## Project
- Domain: `log.meany.xyz`
- Purpose: personal field log (chronological, append-only style)
- Source of truth: Git history + Markdown content
- Output artifact: static HTML + CSS (+ Atom feed)
- Runtime model: no server-side app logic, no client-side API calls

## Locked Decisions
- Generator: 11ty (Eleventy)
- Content layout: flat entries directory
- URL style: directory-style entry URLs (each entry as `.../index.html`)
- Styling: single CSS file (readability-first)
- Feed: Atom enabled
- Listing: single reverse-chron index for now; revisit pagination after ~25 entries
- Deploy model: GitHub Actions build -> deploy artifacts -> server-side pull via timer

## Quality Standards
- HTML output: WCAG 2.2 Level AA conformance
- Entry content: see [.github/instructions/markdown-accessibility.instructions.md](.github/instructions/markdown-accessibility.instructions.md)
- CSS: terminal/CLI aesthetic (monospace-friendly, technical minimalism)

## Content Contract
- Entry format: Markdown with YAML frontmatter
- Required frontmatter:
  - `date` (`YYYY-MM-DD`) — canonical sort key
  - `title` (string)
  - `tags` (string array)
  - `author` (string)
  - `slug` (string) — URL-friendly identifier
  - `summary` (string) — brief description
  - `featured_image` (string) — URL or path
  - `ai_note` (boolean) — indicates AI assistance in creation
- Optional frontmatter:
  - `draft` (boolean, default false)
- File naming convention: `YYYY-MM-DD-slug.md`
- Image assets: stored alongside entry's index.html in the same directory
  - Example: `/entries/2026-03-06-slug/diagram.png`
  - Referenced in Markdown as relative paths: `![alt text](diagram.png)`
- Featured image convention: `/entries/<slug>/featured.webp` (or `.png` when needed)

## Planned Project Structure

```text
log.meany.xyz/
├── content/
│   └── entries/
├── _includes/
├── pages/
├── css/
├── static/
├── instructions/
├── .github/
│   └── copilot-instructions.md
├── .eleventy.js
├── package.json
└── plan.md
```

## Local Workflow
1. Edit/create Markdown entries in `content/entries/` 
2. Preview via `npm run dev`  
3. Commit to Git

## Deployment Workflow
See [docs/DOCKER.md](docs/DOCKER.md) and [docs/DEPLOY.md](docs/DEPLOY.md) for complete CI/CD model.

## Open TODOs
- Syntax highlighting and change visualization (see [docs/DOCKER.md](docs/DOCKER.md#open-todos))

## Non-Goals
- No CMS
- No database
- No runtime rendering
- No dynamic client data fetch
