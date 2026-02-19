# F-001: Multi-Instance RAG for Different Domains

**Priority:** Low
**Status:** Idea

## Description

Run multiple independent RAG service instances, each serving a different domain/use case with its own document corpus and vector database.

## Example Instances

| Instance | Port | Content | Voice Assistant Use Case |
|----------|------|---------|--------------------------|
| GitHub repos | 8100 | Code docs, READMEs | Dev helper — "which project uses WebRTC?" |
| Airbnb properties | 8101 | House rules, FAQs, local guides | Guest concierge — answer incoming calls |
| TBD | 8102 | Other domain docs | TBD |

## Approach

- Each instance is a separate Docker container with its own port and volume
- `docker-compose.yml` defines all services, each with isolated `rag-*-data` volumes
- Voice assistant tools would point `RAG_URL` at the appropriate instance
- Same image, same model — just different indexed content

## Trade-offs

- **Simple & isolated**: No cross-contamination between domains, easy to reason about
- **RAM cost**: Each instance loads the embedding model (~1.5GB RAM per instance)
- **Future optimization**: If running many instances, refactor to single service with multiple LanceDB tables/collections instead of separate containers

## Notes

- Current architecture supports this with zero code changes — just docker-compose config
- Each instance gets its own nightly cron or manual indexing pipeline
