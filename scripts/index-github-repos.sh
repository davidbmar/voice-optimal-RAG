#!/bin/bash
# Index all .md files from davidbmar's GitHub repos into the RAG service.
# Designed to run as a nightly cron job.
#
# Usage:
#   bash scripts/index-github-repos.sh              # interactive
#   bash scripts/index-github-repos.sh 2>&1 | tee /tmp/rag-index.log  # logged
#
# Requires: gh (GitHub CLI, authenticated), curl, python3

set -e

RAG_URL="${RAG_URL:-http://localhost:8100}"
GH_USER="${GH_USER:-davidbmar}"
WORKDIR="${WORKDIR:-/tmp/gh-index/repos}"
REPO_LIMIT="${REPO_LIMIT:-100}"

mkdir -p "$WORKDIR"

# Check RAG service is reachable
if ! curl -sf "$RAG_URL/health" > /dev/null 2>&1; then
  echo "ERROR: RAG service not reachable at $RAG_URL" >&2
  exit 1
fi

# Check gh CLI
if ! command -v gh &> /dev/null; then
  echo "ERROR: gh CLI not found. Install with: brew install gh" >&2
  exit 1
fi

echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') — Starting GitHub repo indexing"
echo "RAG service: $RAG_URL"
echo "GitHub user: $GH_USER"

# Clear existing index
echo ""
echo "Clearing existing index..."
doc_ids=$(curl -s "$RAG_URL/documents" | python3 -c "import sys,json; [print(d['id']) for d in json.load(sys.stdin)['documents']]" 2>/dev/null || true)
deleted=0
for id in $doc_ids; do
  curl -s -X DELETE "$RAG_URL/documents/$id" > /dev/null
  deleted=$((deleted + 1))
done
echo "Deleted $deleted existing documents"

# Get all repos
echo ""
echo "Fetching repo list..."
repos=$(gh repo list "$GH_USER" --limit "$REPO_LIMIT" --json name --jq '.[].name')
repo_count=$(echo "$repos" | wc -l | tr -d ' ')
echo "Found $repo_count repos"

total_files=0
total_chunks=0

for repo in $repos; do
  echo ""
  echo "=== $repo ==="

  # Shallow clone (or pull if exists)
  repo_dir="$WORKDIR/$repo"
  if [ -d "$repo_dir" ]; then
    git -C "$repo_dir" pull --quiet 2>/dev/null || true
  else
    gh repo clone "$GH_USER/$repo" "$repo_dir" -- --depth 1 --quiet 2>/dev/null || { echo "  (clone failed, skipping)"; continue; }
  fi

  # Find .md files (skip node_modules, .git, vendor)
  md_files=$(find "$repo_dir" -name "*.md" \
    -not -path "*node_modules*" \
    -not -path "*.git*" \
    -not -path "*vendor*" \
    2>/dev/null || true)

  if [ -z "$md_files" ]; then
    echo "  (no .md files)"
    continue
  fi

  file_count=$(echo "$md_files" | wc -l | tr -d ' ')
  echo "  Found $file_count .md files"

  echo "$md_files" | while read f; do
    relpath="${f#$repo_dir/}"
    # Create temp copy with safe filename
    tmpfile="/tmp/gh-index/${repo}___${relpath//\//__}.md"
    cp "$f" "$tmpfile"

    result=$(curl -s -X POST "$RAG_URL/upload" \
      -F "files=@$tmpfile;filename=${repo}/${relpath}" 2>/dev/null)
    chunks=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['documents'][0]['chunks'])" 2>/dev/null || echo "err")
    echo "  $relpath ($chunks chunks)"
    rm -f "$tmpfile"
  done

done

echo ""
echo "=== Indexing Complete ==="
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
curl -s "$RAG_URL/health" | python3 -c "
import sys, json
h = json.load(sys.stdin)
print(f\"Documents: {h['documents']}, Chunks: {h['total_chunks']}, Model: {h['embedding_model']}\")
"
