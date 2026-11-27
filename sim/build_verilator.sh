#!/usr/bin/env bash
# Build and run UVM testbench with Verilator
# usage: sim/build_verilator.sh [TEST] [SEED]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
TB="$ROOT/tb"
OUT="$ROOT/sim/obj"

TEST="${1:-eth_rx_rand_test}"
SEED="${2:-1}"

: "${UVM_SRC:?set UVM_SRC to the Accellera uvm-core/src directory}"

mkdir -p "$OUT"

verilator --binary --timing --assert --timescale 1ns/1ps \
  --coverage \
  -Wno-fatal -Wno-lint -Wno-style \
  -CFLAGS "-std=c++20 -fcoroutines" \
  -j "${VL_JOBS:-2}" \
  +define+UVM_NO_DPI \
  +incdir+"$UVM_SRC" +incdir+"$TB" \
  --top-module tb_top --Mdir "$OUT" -o sim \
  "$UVM_SRC/uvm_pkg.sv" \
  "$RTL/crc32.sv" \
  "$RTL/rmii_tx.sv" \
  "$RTL/tx_ctrl.sv" \
  "$RTL/rmii_rx.sv" \
  "$RTL/rx_ctrl.sv" \
  "$RTL/eth_regs.sv" \
  "$RTL/eth_mac_top.sv" \
  "$TB/eth_ifs.sv" \
  "$TB/eth_pkg.sv" \
  "$TB/tb_top.sv"

LOG="$OUT/sim.log"
RC=0
"$OUT/sim" +UVM_TESTNAME="$TEST" +verilator+seed+"$SEED" 2>&1 | tee "$LOG" || RC=$?

if [ "$RC" -ne 0 ] || grep -qE 'UVM_(ERROR|FATAL)\s*:\s*[1-9]' "$LOG"; then
  echo "FAIL: $TEST (seed $SEED)" >&2
  exit 1
fi