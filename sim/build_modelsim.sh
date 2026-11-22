#!/usr/bin/env bash
# Build and run UVM testbench with ModelSim
# usage: sim/build_modelsim.sh [TEST] [SEED]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
TB="$ROOT/tb"
OUT="$ROOT/sim/work"

TEST="${1:-eth_rx_rand_test}"
SEED="${2:-1}"

rm -rf "$OUT"
vlib "$OUT"

vlog -work "$OUT" +incdir+"$TB" \
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

vsim -c -do "run -all; quit -f" \
  -work "$OUT" \
  -sv_seed "$SEED" \
  +UVM_TESTNAME="$TEST" \
  tb_top