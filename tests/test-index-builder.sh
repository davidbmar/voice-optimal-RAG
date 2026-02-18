#!/bin/bash
# Test suite for Project Memory index builder (enhanced format)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "Running Project Memory Index Builder Tests..."
echo ""

# Helper functions
assert_file_exists() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} File exists: $1"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} File missing: $1"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -q "$pattern" "$file"; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $description (pattern not found: $pattern)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_json_valid() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local file="$1"

    if jq empty "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Valid JSON: $file"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Invalid JSON: $file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_equals() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local expected="$1"
    local actual="$2"
    local description="$3"

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC} $description (expected: $expected, got: $actual)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $description (expected: $expected, got: $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_true() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local actual="$1"
    local description="$2"

    if [ "$actual" = "true" ]; then
        echo -e "${GREEN}✓${NC} $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $description (got: $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Build index with sample sessions
test_build_with_sessions() {
    echo -e "\n${YELLOW}Test 1: Build index with sample sessions${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    # Create test session files with proper field format
    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-01-01-1000-test-one.md" << 'EOF'
# Session

Session-ID: S-2026-01-01-1000-test-one
Title: Test authentication system
Date: 2026-01-01
Author: alice

## Goal

Test authentication system

## Context

Adding OAuth support to the application

## Changes Made

- Implemented JWT tokens
- Added login endpoint

## Decisions Made

- Chose OAuth for simplicity

## Links

Commits:
- abc123
EOF

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-01-02-1400-test-two.md" << 'EOF'
# Session

Session-ID: S-2026-01-02-1400-test-two
Title: Improve database performance
Date: 2026-01-02
Author: bob

## Goal

Improve database performance

## Context

Users experiencing slow query times

## Changes Made

- Added indexes to user table
- Optimized JOIN queries

## Links

Commits:
- def456
EOF

    # Run build script
    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # Check all output files exist
    assert_file_exists "$TEST_DIR/docs/project-memory/.index/keywords.json"
    assert_file_exists "$TEST_DIR/docs/project-memory/.index/metadata.json"
    assert_file_exists "$TEST_DIR/docs/project-memory/.index/sessions.txt"
    assert_file_exists "$TEST_DIR/docs/project-memory/.index/last-updated.txt"

    # Validate JSON
    assert_json_valid "$TEST_DIR/docs/project-memory/.index/keywords.json"
    assert_json_valid "$TEST_DIR/docs/project-memory/.index/metadata.json"

    # metadata.json is an array with 2 entries
    local session_count=$(jq 'length' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals "2" "$session_count" "Metadata array has correct session count"

    # keywords.json is an inverted index with authentication keyword
    local has_auth=$(jq 'has("authentication")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_auth" "Keywords index contains 'authentication'"

    local has_database=$(jq 'has("database")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_database" "Keywords index contains 'database'"

    # Inverted index maps keywords to correct sessions
    local auth_sessions=$(jq -r '.authentication | join(",")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_contains <(echo "$auth_sessions") "S-2026-01-01-1000-test-one" "Authentication maps to test-one session"

    local db_sessions=$(jq -r '.database | join(",")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_contains <(echo "$db_sessions") "S-2026-01-02-1400-test-two" "Database maps to test-two session"

    # sessions.txt contains full content
    assert_contains "$TEST_DIR/docs/project-memory/.index/sessions.txt" "OAuth support" "Sessions.txt contains full session text"
    assert_contains "$TEST_DIR/docs/project-memory/.index/sessions.txt" "JWT tokens" "Sessions.txt contains implementation details"

    cd "$OLDPWD"
}

# Test 2: Build index with no sessions
test_build_empty() {
    echo -e "\n${YELLOW}Test 2: Build index with no sessions${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    # Run build script (should handle empty gracefully)
    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1 || true

    # Check metadata.json is an empty array
    assert_file_exists "$TEST_DIR/docs/project-memory/.index/metadata.json"
    local session_count=$(jq 'length' "$TEST_DIR/docs/project-memory/.index/metadata.json" 2>/dev/null || echo "0")
    assert_equals "0" "$session_count" "Empty directory shows 0 sessions"

    # keywords.json should be empty object
    assert_file_exists "$TEST_DIR/docs/project-memory/.index/keywords.json"
    local keyword_count=$(jq 'keys | length' "$TEST_DIR/docs/project-memory/.index/keywords.json" 2>/dev/null || echo "0")
    assert_equals "0" "$keyword_count" "Empty directory has 0 keywords"

    cd "$OLDPWD"
}

# Test 3: Metadata format validation
test_metadata_format() {
    echo -e "\n${YELLOW}Test 3: Verify metadata format${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-01-15-0900-metadata-test.md" << 'EOF'
# Session

Session-ID: S-2026-01-15-0900-metadata-test
Title: Test metadata extraction
Date: 2026-01-15
Author: charlie

## Goal

Test metadata extraction

## Context

Verifying field parsing works

## Changes Made

- Nothing yet
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # metadata.json is an array
    local is_array=$(jq 'type' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals '"array"' "$is_array" "Metadata is a JSON array"

    # Each entry has required fields
    local has_fields=$(jq '.[0] | (has("sessionId") and has("title") and has("file") and has("date") and has("author") and has("goal") and has("keywords"))' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_true "$has_fields" "Metadata entry has all required fields (including title)"

    # last-updated.txt exists with ISO timestamp
    assert_file_exists "$TEST_DIR/docs/project-memory/.index/last-updated.txt"
    assert_contains "$TEST_DIR/docs/project-memory/.index/last-updated.txt" "20[0-9][0-9]-" "Timestamp is ISO 8601 format"

    cd "$OLDPWD"
}

# Test 4: Handle special characters in content
test_special_characters() {
    echo -e "\n${YELLOW}Test 4: Handle special characters${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-01-20-1200-special-chars.md" << 'EOF'
# Session

Session-ID: S-2026-01-20-1200-special-chars
Title: Test special characters
Date: 2026-01-20
Author: test

## Goal

Test special characters: "quotes", 'apostrophes', & ampersands, <tags>, $variables

## Code

```javascript
const config = { "api": "https://example.com/api?key=123&token=xyz" };
```
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # Should still produce valid JSON
    assert_json_valid "$TEST_DIR/docs/project-memory/.index/keywords.json"
    assert_json_valid "$TEST_DIR/docs/project-memory/.index/metadata.json"

    # Content with special chars should be indexed
    local has_special=$(jq 'has("special")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_special" "Keyword 'special' extracted despite special chars"

    cd "$OLDPWD"
}

# Test 5: Session ID extraction
test_session_id_extraction() {
    echo -e "\n${YELLOW}Test 5: Session ID extraction${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-02-09-1530-id-test.md" << 'EOF'
# Session

Session-ID: S-2026-02-09-1530-id-test
Title: Test session ID extraction
Date: 2026-02-09
Author: dev

## Goal

Test content
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # Check that session ID appears in metadata.json
    local session_id=$(jq -r '.[0].sessionId' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals "S-2026-02-09-1530-id-test" "$session_id" "Session ID correctly extracted from filename"

    cd "$OLDPWD"
}

# Test 6: Multiple sessions sorted correctly
test_session_sorting() {
    echo -e "\n${YELLOW}Test 6: Sessions sorted by filename${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    # Create sessions in reverse order
    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-03-01-0000-charlie.md" << 'EOF'
# Session

Session-ID: S-2026-03-01-0000-charlie
Title: Session C
Date: 2026-03-01
Author: c

## Goal

Session C
EOF

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-01-01-0000-alpha.md" << 'EOF'
# Session

Session-ID: S-2026-01-01-0000-alpha
Title: Session A
Date: 2026-01-01
Author: a

## Goal

Session A
EOF

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-02-01-0000-bravo.md" << 'EOF'
# Session

Session-ID: S-2026-02-01-0000-bravo
Title: Session B
Date: 2026-02-01
Author: b

## Goal

Session B
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # Check order in metadata.json
    local first_id=$(jq -r '.[0].sessionId' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    local second_id=$(jq -r '.[1].sessionId' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    local third_id=$(jq -r '.[2].sessionId' "$TEST_DIR/docs/project-memory/.index/metadata.json")

    assert_equals "S-2026-01-01-0000-alpha" "$first_id" "First session is alpha"
    assert_equals "S-2026-02-01-0000-bravo" "$second_id" "Second session is bravo"
    assert_equals "S-2026-03-01-0000-charlie" "$third_id" "Third session is charlie"

    cd "$OLDPWD"
}

# Test 7: Real project sessions
test_real_project_sessions() {
    echo -e "\n${YELLOW}Test 7: Build index from real project sessions${NC}"

    # Use actual project directory
    bash scripts/build-index.sh > /dev/null 2>&1

    assert_file_exists "docs/project-memory/.index/keywords.json"
    assert_file_exists "docs/project-memory/.index/metadata.json"
    assert_file_exists "docs/project-memory/.index/sessions.txt"
    assert_file_exists "docs/project-memory/.index/last-updated.txt"

    assert_json_valid "docs/project-memory/.index/keywords.json"
    assert_json_valid "docs/project-memory/.index/metadata.json"

    # Verify actual sessions are indexed
    local session_count=$(jq 'length' "docs/project-memory/.index/metadata.json")
    echo "  Real project has $session_count sessions"

    if [ "$session_count" -gt 0 ]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        echo -e "${GREEN}✓${NC} Real project sessions indexed (count: $session_count)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

# Test 8: Field extraction (date, author, goal)
test_field_extraction() {
    echo -e "\n${YELLOW}Test 8: Field extraction from session markdown${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-06-15-1400-field-test.md" << 'EOF'
# Session

Session-ID: S-2026-06-15-1400-field-test
Title: Implement OAuth2 authentication
Date: 2026-06-15
Author: Jane Doe

## Goal

Implement user authentication with OAuth2

## Context

Need secure login for the web app

## Changes Made

- Added OAuth2 flow
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    local date=$(jq -r '.[0].date' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals "2026-06-15" "$date" "Date extracted correctly"

    local author=$(jq -r '.[0].author' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals "Jane Doe" "$author" "Author extracted correctly"

    local goal=$(jq -r '.[0].goal' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_contains <(echo "$goal") "OAuth2" "Goal contains expected text"

    cd "$OLDPWD"
}

# Test 9: Keyword extraction and stop word filtering
test_keyword_extraction() {
    echo -e "\n${YELLOW}Test 9: Keyword extraction with stop word filtering${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-07-01-1000-keyword-test.md" << 'EOF'
# Session

Session-ID: S-2026-07-01-1000-keyword-test
Title: Add caching layer
Date: 2026-07-01
Author: tester

## Goal

Add caching layer for the database queries

## Context

The database is slow and we need caching

## Changes Made

- Added Redis caching for user queries
- Implemented cache invalidation strategy

## Decisions Made

- Chose Redis over Memcached for persistence
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # Real keywords should be present
    local has_caching=$(jq 'has("caching")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_caching" "Keyword 'caching' extracted"

    local has_redis=$(jq 'has("redis")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_redis" "Keyword 'redis' extracted"

    local has_database=$(jq 'has("database")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_database" "Keyword 'database' extracted"

    # Stop words should NOT be present
    local has_the=$(jq 'has("the")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_equals "false" "$has_the" "Stop word 'the' excluded"

    local has_and=$(jq 'has("and")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_equals "false" "$has_and" "Stop word 'and' excluded"

    local has_for=$(jq 'has("for")' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_equals "false" "$has_for" "Stop word 'for' excluded"

    cd "$OLDPWD"
}

# Test 10: Inverted index with shared keywords across sessions
test_inverted_index() {
    echo -e "\n${YELLOW}Test 10: Inverted index maps shared keywords to multiple sessions${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    # Two sessions that both mention "authentication"
    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-08-01-1000-auth-one.md" << 'EOF'
# Session

Session-ID: S-2026-08-01-1000-auth-one
Title: Add API authentication
Date: 2026-08-01
Author: dev1

## Goal

Add authentication to the API

## Changes Made

- Added JWT authentication middleware
EOF

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-08-02-1000-auth-two.md" << 'EOF'
# Session

Session-ID: S-2026-08-02-1000-auth-two
Title: Fix authentication bug
Date: 2026-08-02
Author: dev2

## Goal

Fix authentication bug in login flow

## Changes Made

- Fixed token expiry in authentication check
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # "authentication" should map to both sessions
    local auth_count=$(jq '.authentication | length' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_equals "2" "$auth_count" "Shared keyword 'authentication' maps to 2 sessions"

    # Verify both session IDs are present
    local has_one=$(jq '.authentication | contains(["S-2026-08-01-1000-auth-one"])' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_one" "Authentication includes auth-one session"

    local has_two=$(jq '.authentication | contains(["S-2026-08-02-1000-auth-two"])' "$TEST_DIR/docs/project-memory/.index/keywords.json")
    assert_true "$has_two" "Authentication includes auth-two session"

    cd "$OLDPWD"
}

# Test 11: last-updated.txt format
test_last_updated() {
    echo -e "\n${YELLOW}Test 11: last-updated.txt timestamp${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    echo "# Empty" > "$TEST_DIR/docs/project-memory/sessions/S-2026-01-01-0000-ts-test.md"

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    assert_file_exists "$TEST_DIR/docs/project-memory/.index/last-updated.txt"
    assert_contains "$TEST_DIR/docs/project-memory/.index/last-updated.txt" "^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T" "Timestamp matches ISO 8601 pattern"

    cd "$OLDPWD"
}

# Test 12: Title extraction
test_title_extraction() {
    echo -e "\n${YELLOW}Test 12: Title extraction from session markdown${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-09-01-1000-title-test.md" << 'EOF'
# Session

Session-ID: S-2026-09-01-1000-title-test
Title: Add user dashboard with analytics
Date: 2026-09-01
Author: dev

## Goal

Build a user dashboard showing analytics data
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    local title=$(jq -r '.[0].title' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals "Add user dashboard with analytics" "$title" "Title extracted correctly"

    cd "$OLDPWD"
}

# Test 13: Missing Title (backward compatibility)
test_missing_title() {
    echo -e "\n${YELLOW}Test 13: Missing Title field (backward compatibility)${NC}"

    local TEST_DIR=$(mktemp -d)
    trap "rm -rf $TEST_DIR" RETURN

    mkdir -p "$TEST_DIR/docs/project-memory/sessions"
    mkdir -p "$TEST_DIR/docs/project-memory/.index"

    # Session without Title field (old format)
    cat > "$TEST_DIR/docs/project-memory/sessions/S-2026-09-02-1000-no-title.md" << 'EOF'
# Session

Session-ID: S-2026-09-02-1000-no-title
Date: 2026-09-02
Author: dev

## Goal

Legacy session without title field
EOF

    cd "$TEST_DIR"
    bash "$OLDPWD/scripts/build-index.sh" > /dev/null 2>&1

    # Should not crash, should produce valid JSON
    assert_json_valid "$TEST_DIR/docs/project-memory/.index/metadata.json"

    # Title should be empty string, not null or missing
    local title=$(jq -r '.[0].title' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals "" "$title" "Missing Title produces empty string (no crash)"

    # Other fields should still work
    local date=$(jq -r '.[0].date' "$TEST_DIR/docs/project-memory/.index/metadata.json")
    assert_equals "2026-09-02" "$date" "Date still extracted when Title missing"

    cd "$OLDPWD"
}

# Run all tests
test_build_with_sessions
test_build_empty
test_metadata_format
test_special_characters
test_session_id_extraction
test_session_sorting
test_real_project_sessions
test_field_extraction
test_keyword_extraction
test_inverted_index
test_last_updated
test_title_extraction
test_missing_title

# Print summary
echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo -e "Total tests: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
