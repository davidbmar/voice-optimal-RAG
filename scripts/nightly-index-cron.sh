#!/bin/bash
# Nightly cron wrapper: ensures RAG container is running, indexes repos, logs output.
#
# Cron entry (runs at 2 AM daily):
#   0 2 * * * /Users/davidmar/src/2026-feb-voice-optimal-RAG/scripts/nightly-index-cron.sh
#
# Logs to: /tmp/rag-nightly-index.log (overwritten each run)

set -e

PROJECT_DIR="/Users/davidmar/src/2026-feb-voice-optimal-RAG"
LOG_FILE="/tmp/rag-nightly-index.log"
CONTAINER_NAME="rag-service"
RAG_URL="http://localhost:8100"

exec > "$LOG_FILE" 2>&1

echo "=== RAG Nightly Index — $(date -u '+%Y-%m-%d %H:%M:%S UTC') ==="

# Ensure Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "Docker not running. Attempting to start..."
  open -a Docker
  # Wait up to 60 seconds for Docker to start
  for i in $(seq 1 30); do
    if docker info > /dev/null 2>&1; then
      echo "Docker started after ${i}x2 seconds"
      break
    fi
    sleep 2
  done
  if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker failed to start" >&2
    exit 1
  fi
fi

# Ensure RAG container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Starting RAG container..."
  docker run -d --name "$CONTAINER_NAME" \
    -p 8100:8100 \
    -v rag-data:/data \
    rag-service 2>/dev/null \
  || docker start "$CONTAINER_NAME" 2>/dev/null \
  || true

  # Wait for service to be healthy
  for i in $(seq 1 15); do
    if curl -sf "$RAG_URL/health" > /dev/null 2>&1; then
      echo "RAG service healthy after ${i}x2 seconds"
      break
    fi
    sleep 2
  done
fi

if ! curl -sf "$RAG_URL/health" > /dev/null 2>&1; then
  echo "ERROR: RAG service not healthy at $RAG_URL" >&2
  exit 1
fi

# Run the indexing script
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
bash "$PROJECT_DIR/scripts/index-github-repos.sh"

echo ""
echo "=== Completed — $(date -u '+%Y-%m-%d %H:%M:%S UTC') ==="
