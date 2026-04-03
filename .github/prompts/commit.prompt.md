---
name: commit
description: Review unstaged changes, craft a Conventional Commits message, commit, and push to remote.
model: model-router (azure)
---

Run this workflow in the current repository using non-interactive git commands.

Goal:
- Review all unstaged changes.
- Write a high-quality commit message based on those changes.
- Commit the changed files.
- Push to the current branch's remote.

Execution steps:
1. Inspect git state:
	- `git rev-parse --abbrev-ref HEAD`
	- `git status --short`
	- `git diff --stat`
	- `git diff`
2. If there are no unstaged changes, stop and report that nothing needs committing.
3. Infer a commit message from the actual diff using Conventional Commits 1.0.0:
	- Required header format: `<type>[optional scope][optional !]: <description>`
	- The description MUST immediately follow `: ` and summarize the change.
	- Use `feat` for new features and `fix` for bug fixes.
	- Other allowed types include: `build`, `chore`, `ci`, `docs`, `perf`, `refactor`, `style`, `test`, `revert`.
	- Optional scope must be a noun in parentheses, for example: `fix(css): ...`.
	- Mark breaking changes with `!` before the colon, for example: `feat(api)!: ...`, and/or include footer `BREAKING CHANGE: <description>`.
	- If adding a body, place exactly one blank line after the header.
	- If adding footer(s), place exactly one blank line after the body (or header if no body).
	- Footer tokens follow git trailer style, for example: `Refs: #123`, `Reviewed-by: Name`.
	- Keep subject concise (prefer <= 72 chars) and in imperative mood.
	- Choose one primary change type; if changes are mixed, prefer the dominant user-facing change.
4. Stage only modified/untracked files reflected in the current unstaged set:
	- `git add -A`
5. Commit using the generated message.
6. Push to the branch's upstream remote:
	- `git push`

Output requirements:
- Show a short "Plan" line before running commands.
- After completion, return:
  - Branch name.
  - Commit message used.
  - Commit SHA.
  - Files included in the commit.
  - Push result summary.
	- Conventional Commits validation summary (type, optional scope, breaking-change indicator/footer if present).

Safety and behavior:
- Do not use interactive git flows.
- Do not rewrite history.
- Do not amend existing commits unless explicitly asked.
- If push fails due to auth, remote, or protection rules, report the exact failure and next command to run.

SemVer guidance for type selection:
- `fix` corresponds to PATCH-level change intent.
- `feat` corresponds to MINOR-level change intent.
- Any commit with `!` or `BREAKING CHANGE:` corresponds to MAJOR-level change intent.