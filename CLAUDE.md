# Claude Instructions

## Project Overview

RAG Service — a self-contained Docker service providing document ingestion and real-time vector retrieval for a voice assistant. FastAPI + LanceDB + sentence-transformers, all in one container on port 8100.

Design doc: `docs/plans/2026-02-17-rag-service-design.md`

## Project Memory System

This repo uses a **Traceable Project Memory** system. Every coding session, commit, and decision must be documented and searchable.

### You MUST Follow These Rules

#### 1. Session ID Format

Every coding session gets a unique Session ID:
```
S-YYYY-MM-DD-HHMM-<slug>
```

**HHMM is UTC** — always use `date -u +%Y-%m-%d-%H%M` to generate the timestamp.

Example: `S-2026-02-17-0300-initial-build`

#### 2. Commit Message Format

Write a **human-readable subject line**. Put the Session ID in the commit body:
```
Subject line describing the change

Session: S-YYYY-MM-DD-HHMM-slug
```

#### 3. Session Documentation

When starting work:

1. **Check if a session exists** for this work:
   ```bash
   ls docs/project-memory/sessions/
   ```

2. **If no session exists, create one:**
   - Copy `docs/project-memory/sessions/_template.md`
   - Name it with the Session ID: `S-YYYY-MM-DD-HHMM-slug.md`
   - Fill in Title, Goal, Context, Plan

3. **After making changes, update the session doc:**
   - Add what changed to "Changes Made"
   - Document decisions in "Decisions Made"
   - Link commits after you create them

#### 4. When to Create an ADR

Create an ADR in `docs/project-memory/adr/` when:
- Making significant architectural decisions
- Choosing between technical approaches
- Establishing patterns that will be followed
- Making decisions with long-term consequences

Use the ADR template: `docs/project-memory/adr/_template.md`

#### 5. Backlog (Bugs & Features)

Track work items in `docs/project-memory/backlog/`:
- **Bugs** use a `B-NNN` prefix (e.g., `B-001-login-crash.md`)
- **Features** use an `F-NNN` prefix (e.g., `F-001-dark-mode.md`)
- Each item gets its own markdown file
- Update `docs/project-memory/backlog/README.md` table when adding/changing items

#### 6. Searching Project Memory

**Search commits by Session ID:**
```bash
git log --all --grep="S-2026-02-17-0300-initial-build"
```

**Search session docs:**
```bash
grep -r "keyword" docs/project-memory/sessions/
```

**Search ADRs:**
```bash
grep -r "decision topic" docs/project-memory/adr/
```

#### 7. Semantic Search (AI-Powered)

When users ask questions using **concepts** rather than exact keywords, do semantic search:

1. Read ALL session docs and ADRs
2. Analyze content using your understanding to find matches
3. Match related concepts (e.g., "mobile" → iPhone, responsive, viewport)
4. Return results with explanation of why they match

### Your Workflow

1. **Start of work:** Create or identify Session ID (HHMM is UTC)
2. **Create session doc:** Use template, fill in Title/Goal/Context/Plan
3. **Make changes:** Write code
4. **Commit:** Human-readable subject, `Session: S-...` in body
5. **Update session doc:** Add Changes Made, Decisions, Links
6. **Create ADR if needed:** For significant decisions

### Quick Reference

- **Session template:** `docs/project-memory/sessions/_template.md`
- **ADR template:** `docs/project-memory/adr/_template.md`
- **PR template:** `.github/PULL_REQUEST_TEMPLATE.md`
- **Overview:** `docs/project-memory/index.md`
- **Design doc:** `docs/plans/2026-02-17-rag-service-design.md`

## Always Enforce

- Session ID times are UTC (`date -u`)
- Every commit has `Session: S-...` in the body
- Every session has a markdown doc with a Title field
- Significant decisions get ADRs
- PRs reference Session IDs
- Session docs link to commits, PRs, ADRs
