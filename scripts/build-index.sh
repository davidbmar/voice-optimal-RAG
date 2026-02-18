#!/bin/bash
# Build Project Memory index from session files
# Pure bash + jq implementation — no other dependencies
#
# Output:
#   metadata.json    - array of per-session metadata (sessionId, title, date, author, goal, keywords)
#   keywords.json    - inverted keyword → session IDs index (for search)
#   sessions.txt     - plain text concatenation (for grep)
#   last-updated.txt - build timestamp

set -e

INDEX_DIR="docs/project-memory/.index"
SESSIONS_DIR="docs/project-memory/sessions"

# Common stop words to exclude from keyword index
STOP_WORDS="the is at which on a an and or but in with to for of as by this that from was were been have has had do does did will would could should may might must can be are am it its we they you he she what when where who why how not no yes all any each every some none also just only very much more most"

mkdir -p "$INDEX_DIR"

echo "Building Project Memory index..."

# Collect session files into an array (avoids subshell issues with find|while)
SESSION_FILES=()
while IFS= read -r f; do
    SESSION_FILES+=("$f")
done < <(find "$SESSIONS_DIR" -name "S-*.md" 2>/dev/null | sort)

SESSION_COUNT=${#SESSION_FILES[@]}
echo "Found $SESSION_COUNT session files"

# --- Phase 1: Build per-session metadata objects ---
rm -f "$INDEX_DIR/metadata.json.tmp"

for file in "${SESSION_FILES[@]}"; do
    SESSION_ID=$(basename "$file" .md)

    # Read file content
    CONTENT=$(cat "$file")

    # Extract fields from session markdown
    TITLE=$(echo "$CONTENT" | grep -m1 "^Title:" | sed 's/^Title:[[:space:]]*//' || echo "")
    DATE=$(echo "$CONTENT" | grep -m1 "^Date:" | sed 's/^Date:[[:space:]]*//' || echo "")
    AUTHOR=$(echo "$CONTENT" | grep -m1 "^Author:" | sed 's/^Author:[[:space:]]*//' || echo "")

    # Extract Goal section (text between ## Goal and next ##)
    GOAL=$(echo "$CONTENT" | sed -n '/^## Goal/,/^## /{/^## Goal/d;/^## /d;p;}' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 500)

    # Extract searchable sections for keywords (Goal through Decisions, before Links)
    SECTIONS=$(echo "$CONTENT" | sed -n '/^## Goal/,/^## Links/{/^## Links/d;p;}' | tr '\n' ' ')

    # Build keyword list: lowercase, remove punctuation, filter stop words and short words
    KEYWORDS=$(echo "$SECTIONS" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9 -]/ /g' | \
        tr -s ' ' '\n' | \
        sort -u | \
        while read -r word; do
            # Skip words shorter than 3 chars, pure numbers, and stop words
            [ ${#word} -lt 3 ] && continue
            echo "$word" | grep -qE '^[0-9]+$' && continue
            echo " $STOP_WORDS " | grep -q " $word " && continue
            echo "$word"
        done | \
        head -50)

    # Format keywords as JSON array
    KEYWORDS_JSON=$(echo "$KEYWORDS" | jq -R . | jq -s .)

    # Build session JSON object and append to temp file
    jq -n \
        --arg sid "$SESSION_ID" \
        --arg title "$TITLE" \
        --arg file "$file" \
        --arg date "$DATE" \
        --arg author "$AUTHOR" \
        --arg goal "$GOAL" \
        --argjson keywords "$KEYWORDS_JSON" \
        '{sessionId: $sid, title: $title, file: $file, date: $date, author: $author, goal: $goal, keywords: $keywords}' \
        >> "$INDEX_DIR/metadata.json.tmp"
done

# --- Phase 2: Combine into metadata.json array ---
if [ -f "$INDEX_DIR/metadata.json.tmp" ]; then
    jq -s '.' "$INDEX_DIR/metadata.json.tmp" > "$INDEX_DIR/metadata.json"
    rm "$INDEX_DIR/metadata.json.tmp"
else
    echo "[]" > "$INDEX_DIR/metadata.json"
fi

# --- Phase 3: Build inverted keyword index ---
jq '
  reduce .[] as $s ({};
    reduce $s.keywords[] as $kw (.;
      .[$kw] = ((.[$kw] // []) + [$s.sessionId] | unique)
    )
  )
' "$INDEX_DIR/metadata.json" > "$INDEX_DIR/keywords.json"

# --- Phase 4: Build sessions.txt (plain text for grep) ---
> "$INDEX_DIR/sessions.txt"
for file in "${SESSION_FILES[@]}"; do
    SESSION_ID=$(basename "$file" .md)
    echo "=== $SESSION_ID ===" >> "$INDEX_DIR/sessions.txt"
    cat "$file" >> "$INDEX_DIR/sessions.txt"
    echo "" >> "$INDEX_DIR/sessions.txt"
done

# --- Phase 5: Build timestamp ---
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$INDEX_DIR/last-updated.txt"

echo "✓ Index built successfully!"
echo "  - metadata.json: $SESSION_COUNT session(s) with extracted fields"
echo "  - keywords.json: Inverted keyword → session ID index"
echo "  - sessions.txt: Plaintext search index"
echo "  - last-updated.txt: Build timestamp"
