#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"
TB="$ROOT/tb"
OUT="$ROOT/sim/obj"

TEST="${1:-eth_rx_rand_test}"
SEED="${2:-1}"

mkdir -p "$OUT"

verilator --cc --exe --build \
  -Wall -Wno-fatal \
  --timing \
  +incdir+"$TB" \
  --top-module tb_top \
  -CFLAGS "-std=c++17" \
  -o "$OUT/sim" \
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

"$OUT/sim" +UVM_TESTNAME="$TEST" +UVM_SEED="$SEED"
