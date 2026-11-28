# sv-ethernet-mac-rmii

Synthesizable 10/100 Ethernet MAC in SystemVerilog, targeting a Terasic DE1-SoC
(Cyclone V) with an RMII LAN8720 PHY module. Verified with a UVM testbench
on Verilator.

## Architecture

The MAC sits between an AXI-Stream user interface (8-bit, tvalid/tready/tlast)
and an RMII PHY. TX and RX are independent datapaths sharing a common CRC-32
engine and register block.

**TX path:** AXI-Stream in -> `tx_ctrl` (prepends preamble/SFD, pads to 64B,
appends CRC-32, enforces IFG) -> `rmii_tx` (byte-to-dibit serializer) -> PHY

**RX path:** PHY -> `rmii_rx` (dibit-to-byte deserializer) -> `rx_ctrl`
(strips preamble, checks CRC, filters by MAC address, buffers up to 8 frames
in M10K block RAM) -> AXI-Stream out

**Registers:** `eth_regs` exposes control bits (tx/rx enable, promiscuous mode,
MAC address) and read-only event counters over a simple write/read bus.

## RTL modules

| File | Description |
|------|-------------|
| `rtl/eth_mac_top.sv` | Top-level wiring |
| `rtl/tx_ctrl.sv` | TX: preamble, padding to 64B, CRC-32 append, IFG |
| `rtl/rmii_tx.sv` | TX: byte-to-dibit serializer |
| `rtl/rx_ctrl.sv` | RX: preamble strip, CRC check, MAC filter, 8-entry frame buffer |
| `rtl/rmii_rx.sv` | RX: dibit-to-byte deserializer |
| `rtl/eth_regs.sv` | Config registers + event counters |
| `rtl/crc32.sv` | CRC-32 (Ethernet FCS), byte-serial, reflected polynomial |

## Register map

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | CTRL | RW | `[0]` tx_en `[1]` rx_en `[2]` promisc |
| 0x04 | MAC_ADDR_L | RW | Lower 4 bytes of MAC address |
| 0x08 | MAC_ADDR_H | RW | Upper 2 bytes of MAC address |
| 0x10 | TX_FRAMES | RO | Transmitted frame count |
| 0x14 | RX_FRAMES | RO | Good received frame count |
| 0x18 | RX_FCS_ERR | RO | Frames with bad CRC |
| 0x1C | RX_DROPPED | RO | Runt + oversize + filtered frames |
| 0x20 | RX_FIFO_OVF | RO | Buffer overflow count |
| 0x24 | CLEAR | WO | Write 1 to clear all counters |

## Verification

UVM testbench with 7 test classes, run on Verilator 5.054. Each test runs
over multiple seeds (`N_SEEDS`, default 5) via `+verilator+seed+N`. The
regression script detects UVM errors in the report summary and exits non-zero
on any failure.

| Test | What it covers |
|------|---------------|
| `eth_rx_rand_test` | 100 random RX frames, all lengths/IFGs |
| `eth_rx_corner_test` | Directed: min/max length, exact 64B boundary |
| `eth_rx_err_test` | Bad CRC, runt, oversize, truncated frames |
| `eth_tx_rand_test` | 50 random TX frames |
| `eth_tx_corner_test` | Directed: padding boundary, max payload |
| `eth_rx_bp_test` | RX under 10%, 50% random and bursty backpressure |
| `eth_full_test` | Simultaneous TX + RX traffic |

### SVA

6 assertion properties in the interfaces (`tb/eth_ifs.sv`), checked on every
test:

- AXI-Stream tvalid hold, tdata/tlast/tuser stability while waiting for
  tready, tlast only with tvalid (5 properties, checked on both TX input
  and RX output interfaces)
- RMII TX inter-frame gap (tx_en stays low for at least 42 cycles after
  deassertion)

### Coverage

Functional coverage (covergroup) at 100% (55/55 bins) across all tests.
The covergroup crosses RX frame error type, body length, and backpressure
mode. 34 structurally impossible cross bins are excluded (e.g. a runt frame
can't also be 1500 bytes).

### Regression output

```
$ N_SEEDS=5 bash sim/run_all.sh

--- eth_rx_rand_test (5 seeds) ---
  all 5 seeds passed

--- eth_rx_corner_test (5 seeds) ---
  all 5 seeds passed

--- eth_rx_err_test (5 seeds) ---
  all 5 seeds passed

--- eth_tx_rand_test (5 seeds) ---
  all 5 seeds passed

--- eth_tx_corner_test (5 seeds) ---
  all 5 seeds passed

--- eth_rx_bp_test (5 seeds) ---
  all 5 seeds passed

--- eth_full_test (5 seeds) ---
  all 5 seeds passed

=== Results: 35/35 passed, 0 failed (7 tests x 5 seeds) ===

=== Merged Coverage ===
  covergroup : 100.0% (   55/   55)
```

### Testbench structure

| File | Description |
|------|-------------|
| `tb/tb_top.sv` | Top module, clock/reset, DUT instantiation |
| `tb/eth_ifs.sv` | Interfaces with SVA (rmii_if, axis_if, reg_if) |
| `tb/eth_pkg.sv` | Package, pulls in all .svh includes |
| `tb/eth_types.svh` | Transaction classes (rx_frame, tx_frame, reg_item) |
| `tb/eth_agents.svh` | UVM agents, drivers, monitors |
| `tb/eth_model.svh` | Reference model (golden CRC, filtering) |
| `tb/eth_scb.svh` | Scoreboard (expected vs actual comparison) |
| `tb/eth_cov.svh` | Functional coverage (frame length x error x backpressure) |
| `tb/eth_seqs.svh` | Sequences (random, corner, error injection) |
| `tb/eth_tests.svh` | Test classes |
| `tb/eth_env.svh` | Environment wiring |

## Synthesis results (Quartus Prime 18.1, Cyclone V 5CSEMA5F31C6)

| Resource | Used | Available | % |
|----------|------|-----------|---|
| ALMs | 419 | 32,070 | 1% |
| Registers | 587 | 64,140 | <1% |
| M10K blocks | 16 | 397 | 4% |
| DSP blocks | 0 | 87 | 0% |
| Fmax | ~55 MHz | 50 MHz target | met |

The RX frame buffers (8 x 2048 bytes) are inferred as M10K block RAM.

## Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Verilator | 5.054+ | UVM simulation, functional coverage |
| Accellera UVM | 1.2 / uvm-core | UVM class library (set `UVM_SRC` to its `src/` directory) |
| z3 | any | SAT solver for `randomize()` constraints |
| Quartus Prime | 18.1 Lite | Synthesis targeting Cyclone V |

### Simulation

```bash
export UVM_SRC=/path/to/uvm-core/src
bash sim/build_verilator.sh              # builds + runs eth_rx_rand_test
bash sim/build_verilator.sh eth_full_test 42  # specific test + seed
N_SEEDS=10 bash sim/run_all.sh           # all 7 tests x 10 seeds, merged coverage
```

### Synthesis

Open `quartus/eth_mac.qpf` in Quartus Prime and compile. Pin assignments in the
`.qsf` are commented out and should be set to match the GPIO wiring to the PHY
module.

## Hardware used

- Terasic DE1-SoC (Cyclone V 5CSEMA5F31C6)
- LAN8720 RMII breakout module, wired to GPIO header
- 50 MHz REF_CLK from PHY or FPGA PLL
