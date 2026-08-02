#!/usr/bin/env bash
# tests/run_phase4_rewrite_guardrails.sh
#
# Runs Phase 4 rewrite guardrail suite with consolidated pass/fail summary.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TESTS=(
  "tests/test_phase4_koha_create_rewrite.sh"
  "tests/test_phase4_koha_plack_rewrite.sh"
  "tests/test_phase4_koha_worker_rewrite.sh"
  "tests/test_phase4_koha_functions_rewrite.sh"
  "tests/test_phase4_start_stop_daemon.sh"
)

PASS=0
FAIL=0

echo "# Phase 4 rewrite guardrail umbrella runner"
echo "# Working directory: $ROOT_DIR"
if [ -n "${KOHA_TEST_IMAGE:-}" ]; then
  echo "# KOHA_TEST_IMAGE: ${KOHA_TEST_IMAGE}"
else
  echo "# KOHA_TEST_IMAGE: <unset>"
fi
echo ""

for test_script in "${TESTS[@]}"; do
  echo "## Running ${test_script}"
  if [ ! -x "$test_script" ]; then
    chmod 0755 "$test_script"
  fi

  if "$test_script"; then
    echo "## RESULT: PASS - ${test_script}"
    PASS=$((PASS + 1))
  else
    echo "## RESULT: FAIL - ${test_script}"
    FAIL=$((FAIL + 1))
  fi
  echo ""
done

echo "# Suite summary"
echo "# Passed test scripts: ${PASS}"
echo "# Failed test scripts: ${FAIL}"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
