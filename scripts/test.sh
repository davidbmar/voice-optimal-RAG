#!/bin/bash
# Test runner for Project Memory system

set -e

echo "╔════════════════════════════════════════════╗"
echo "║  Project Memory System - Test Suite       ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Run all test files
for test_file in tests/test-*.sh; do
    if [ -f "$test_file" ]; then
        bash "$test_file"
        echo ""
    fi
done

echo "All test suites completed!"
