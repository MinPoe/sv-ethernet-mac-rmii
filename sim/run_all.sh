#!/usr/bin/env bash
# Run all UVM tests over multiple seeds and merge functional coverage
# usage: N_SEEDS=10 bash sim/run_all.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/sim/obj/sim"
COV_DIR="$ROOT/sim/cov"
LOG_DIR="$ROOT/sim/logs"
N_SEEDS="${N_SEEDS:-5}"

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
  echo "--- $t ($N_SEEDS seeds) ---"
  T_FAIL=()

  for s in $(seq 1 "$N_SEEDS"); do
    COV_FILE="$COV_DIR/${t}_s${s}.dat"
    LOG="$LOG_DIR/${t}_s${s}.log"
    RC=0
    "$SIM" +UVM_TESTNAME="$t" +verilator+seed+"$s" \
      +verilator+coverage+file+"$COV_FILE" >"$LOG" 2>&1 || RC=$?

    if [ "$RC" -ne 0 ] || grep -qE 'UVM_(ERROR|FATAL)\s*:\s*[1-9]' "$LOG"; then
      T_FAIL+=("$s")
    fi

    if [ -f "$COV_FILE" ]; then
      COV_FILES+=("$COV_FILE")
    fi
  done

  if [ ${#T_FAIL[@]} -gt 0 ]; then
    echo "  FAIL seeds: ${T_FAIL[*]}"
    FAIL=$((FAIL + ${#T_FAIL[@]}))
    for s in "${T_FAIL[@]}"; do
      FAIL_LIST+=("${t}:s${s}")
    done
  else
    echo "  all $N_SEEDS seeds passed"
  fi

  PASS=$((PASS + N_SEEDS - ${#T_FAIL[@]}))
  echo ""
done

TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed (${#TESTS[@]} tests x $N_SEEDS seeds) ==="
if [ ${#FAIL_LIST[@]} -gt 0 ]; then
  echo "FAILED:"
  printf '  %s\n' "${FAIL_LIST[@]}"
fi

if [ ${#COV_FILES[@]} -gt 0 ]; then
  MERGED="$COV_DIR/merged.dat"
  verilator_coverage --write "$MERGED" "${COV_FILES[@]}"
  echo ""
  echo "=== Merged Coverage ==="
  verilator_coverage "$MERGED"
fi

[ "$FAIL" -eq 0 ]
