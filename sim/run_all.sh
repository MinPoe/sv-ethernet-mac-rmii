#!/usr/bin/env bash
# Run all UVM tests and merge functional coverage
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/sim/obj/sim"
COV_DIR="$ROOT/sim/cov"
LOG_DIR="$ROOT/sim/logs"

TESTS=(
  eth_rx_rand_test
  eth_rx_corner_test
  eth_rx_err_test
  eth_tx_rand_test
  eth_tx_corner_test
  eth_rx_bp_test
  eth_full_test
)

if [ ! -x "$SIM" ]; then
  echo "ERROR: sim binary not found - run build_verilator.sh first" >&2
  exit 1
fi

rm -rf "$COV_DIR" "$LOG_DIR"
mkdir -p "$COV_DIR" "$LOG_DIR"

PASS=0
FAIL=0
COV_FILES=()
FAIL_LIST=()

for t in "${TESTS[@]}"; do
  echo "--- $t ---"
  COV_FILE="$COV_DIR/${t}.dat"
  LOG="$LOG_DIR/${t}.log"
  RC=0
  "$SIM" +UVM_TESTNAME="$t" +verilator+coverage+file+"$COV_FILE" >"$LOG" 2>&1 || RC=$?

  if [ "$RC" -ne 0 ] || grep -qE 'UVM_(ERROR|FATAL)\s*:\s*[1-9]' "$LOG"; then
    tail -5 "$LOG"
    echo "FAIL (rc=$RC)"
    FAIL=$((FAIL + 1))
    FAIL_LIST+=("$t")
  else
    tail -3 "$LOG"
    PASS=$((PASS + 1))
  fi

  if [ -f "$COV_FILE" ]; then
    COV_FILES+=("$COV_FILE")
  fi
  echo ""
done

echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#FAIL_LIST[@]} -gt 0 ]; then
  echo "FAILED: ${FAIL_LIST[*]}"
fi

if [ ${#COV_FILES[@]} -gt 0 ]; then
  MERGED="$COV_DIR/merged.dat"
  verilator_coverage --write "$MERGED" "${COV_FILES[@]}"
  echo ""
  echo "=== Merged Coverage ==="
  verilator_coverage "$MERGED"
fi

[ "$FAIL" -eq 0 ]