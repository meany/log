# Copilot Instructions

## Mission
Maintain a minimalist, durable static engineering log for `log.meany.xyz`.

Refer to `plan.md` for architecture decisions and open design items.

## Workflow

- Read files before editing
- Read and apply .github/instructions/* before working in the codebase
- Use Context7 MCP when I need library/API documentation, code generation, setup or configuration steps without explicitly asking
- Keep changes focused, minimal, and limited to the requested scope
- Provide status updates only for multi-step work

## Rules

- ✅ Make requested changes directly
- ✅ Run language-specific validation tools before proposing changes
- ✅ Keep explanations concise and direct
- ✅ Use variables for configuration and parameters
- ✅ Proceed with best safe assumption unless ambiguity materially changes outcome or ask 1-3 focused clarifying questions
- ✅ Prefer minimal diffs; avoid unrelated refactors
- ✅ Prefer incremental edits over broad refactors
- ✅ Avoid introducing abstractions unless a concrete need exists
- ✅ Prefer boring, proven tooling and clear file conventions
- ✅ When proposing new dependencies, state why existing tooling is insufficient
- ✅ Reuse existing project patterns/components before adding new abstractions
- ✅ For markdown changes, enforce accessibility basics (descriptive links, heading hierarchy, alt text)
- ✅ After edits, summarize only: what changed, where, and risks/open items
- ❌ Creating markdown files without being asked
- ❌ Long preambles or verbose explanations
- ❌ Over-commenting code — only for complex logic or design decisions
- ❌ Hard-coded values
- ❌ Renaming files, public APIs, or shared symbols unless explicitly requested
- ❌ Committing sensitive data — use `.gitignore` and GitHub Actions secrets
- ❌ Run the build if just making new entries