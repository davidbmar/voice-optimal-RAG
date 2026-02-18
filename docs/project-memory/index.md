# Project Memory

## What is This?

Project Memory is a system for making every coding session, decision, and commit searchable and explainable with citations. Every coding session is traceable.

## Session ID Format

Every coding session gets a unique ID:

```
S-YYYY-MM-DD-HHMM-<slug>
```

**HHMM is UTC** — always use `date -u +%Y-%m-%d-%H%M` to generate the timestamp.

Example: `S-2026-02-17-0300-initial-build`

Rules:
- One Session ID per coding session
- Every commit has a human-readable subject with `Session: S-...` in the body
- Every session doc includes a `Title:` field
- Session IDs link commits, PRs, and ADRs together

## How It Links Together

```
Session → Commits → PRs → ADRs
```

1. Start a session, create a session doc with a Title
2. Make commits with human-readable subjects, `Session: S-...` in body
3. Create PR, reference Session ID
4. If you made a significant decision, write an ADR
5. Link them all together in the docs

## Searching Project Memory

### Keyword Search

```bash
grep -r "authentication" docs/project-memory/sessions/
git log --all --grep="S-2026-02-17-0300"
ls docs/project-memory/sessions/S-2026-02-17*
```

### Semantic Search (AI-Powered)

Ask Claude conceptual questions, not just keywords.

## Backlog

Track bugs and features in `backlog/`:
- **Bugs** use `B-NNN` prefix (e.g., `B-001-login-crash.md`)
- **Features** use `F-NNN` prefix (e.g., `F-001-dark-mode.md`)
- `backlog/README.md` has the summary table

## Directory Structure

- `sessions/` - Individual coding session logs
- `adr/` - Architecture Decision Records
- `backlog/` - Bug and feature backlog
- `runbooks/` - Operational procedures
- `architecture/` - System design docs and diagrams
