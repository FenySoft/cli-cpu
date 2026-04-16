#!/bin/bash
# CLI-CPU GitHub Milestones & Issues létrehozó script
# Használat:
#   1. gh auth login
#   2. bash scripts/create-github-milestones-and-issues.sh

REPO="FenySoft/cli-cpu"

echo "=== Milestones létrehozása ==="

gh api repos/$REPO/milestones -f title="F2 — RTL (Register Transfer Level)" \
  -f description="Synthesizable RTL implementation of the single Nano core, verified bit-for-bit against the F1 C# reference simulator using cocotb golden-vector testing. Yosys synthesis targeting Sky130 PDK for area estimation." \
  -f state="open"
echo "✓ F2 milestone"

gh api repos/$REPO/milestones -f title="F3 — Tiny Tapeout (First Silicon)" \
  -f description="First physical CLI-CPU chip on a Tiny Tapeout Sky130 shuttle. Single Nano core + hardware mailbox + UART in 12-16 tiles. Bring-up PCB design. Post-silicon verification: Fibonacci(20) and echo neuron demo via UART." \
  -f state="open"
echo "✓ F3 milestone"

gh api repos/$REPO/milestones -f title="F4 — Multi-core FPGA (Cognitive Fabric)" \
  -f description="4 Nano cores on MicroPhase A7-Lite XC7A200T FPGA, communicating via hardware mailboxes in a shared-nothing, event-driven fabric. Ping-pong, echo-chain, and SNN demos." \
  -f state="open"
echo "✓ F4 milestone"

echo ""
echo "=== Milestone számok lekérdezése ==="

F2_NUM=$(gh api repos/$REPO/milestones --jq '.[] | select(.title | startswith("F2")) | .number')
F3_NUM=$(gh api repos/$REPO/milestones --jq '.[] | select(.title | startswith("F3")) | .number')
F4_NUM=$(gh api repos/$REPO/milestones --jq '.[] | select(.title | startswith("F4")) | .number')

echo "F2=#$F2_NUM  F3=#$F3_NUM  F4=#$F4_NUM"
echo ""

echo "=== F2 Issues ==="

gh issue create -R $REPO -t "F2.1: ALU module (32-bit integer, Verilog + cocotb)" \
  -b "Implement the 32-bit integer ALU: add, sub, mul, div, rem, neg, and, or, xor, not, shl, shr, ceq, cgt, clt. Cocotb testbench matching C# TExecutor ALU tests." \
  -m "$F2_NUM" -l "F2-RTL"
echo "✓ F2.1"

gh issue create -R $REPO -t "F2.2a: Decoder — length decoder + opcode decode (hardwired)" \
  -b "CIL variable-length instruction length decoder and opcode decoder. Hardwired path: decode opcode byte, determine instruction length (1–5 bytes), extract immediate operand. Cocotb testbench. Match TDecoder behavior for all 48 CIL-T0 opcodes." \
  -m "$F2_NUM" -l "F2-RTL"
echo "✓ F2.2a"

gh issue create -R $REPO -t "F2.2b: Decoder — microcode ROM for complex opcodes" \
  -b "Microcode ROM dispatch for multi-cycle opcodes (mul, div, call, ret). Sequencer FSM that expands a single opcode into a sequence of micro-operations. Depends on F2.2a (basic decoder) and F2.1 (ALU). Cocotb testbench matching C# TExecutor behavior." \
  -m "$F2_NUM" -l "F2-RTL"
echo "✓ F2.2b"

gh issue create -R $REPO -t "F2.3: Stack cache (4×32-bit TOS + spill logic)" \
  -b "Top-of-stack cache: 4 registers holding the top stack elements. Automatic spill/fill to SRAM/QSPI when cache overflows/underflows. Match TCpu stack semantics." \
  -m "$F2_NUM" -l "F2-RTL"
echo "✓ F2.3"

gh issue create -R $REPO -t "F2.4: QSPI controller (code + data fetch)" \
  -b "QSPI flash controller for code fetch and QSPI PSRAM controller for data/stack access. Prefetch buffer for sequential code. 10-50 cycle latency budget." \
  -m "$F2_NUM" -l "F2-RTL"
echo "✓ F2.4"

gh issue create -R $REPO -t "F2.5: Golden vector test harness (cocotb vs C# simulator)" \
  -b "Automated test infrastructure: export C# simulator test vectors (opcode, input state, expected output state) and verify RTL matches bit-for-bit using cocotb. All 267 existing tests must pass." \
  -m "$F2_NUM" -l "F2-RTL"
echo "✓ F2.5"

gh issue create -R $REPO -t "F2.6: Yosys synthesis for Sky130 — area estimate" \
  -b "Synthesize the complete Nano core with Yosys targeting Sky130 PDK. Report: std cell count, estimated area (mm²), timing analysis (target: 50 MHz). Verify it fits in 12-16 Tiny Tapeout tiles." \
  -m "$F2_NUM" -l "F2-RTL"
echo "✓ F2.6"

echo ""
echo "=== F3 Issues ==="

gh issue create -R $REPO -t "F3.1: Tiny Tapeout 16-tile integration (core + mailbox + UART)" \
  -b "Integrate Nano core + mailbox FIFO (8-deep inbox/outbox) + UART into a single Tiny Tapeout top-level module. Pin assignment for 24 GPIO (8in + 8out + 8bidi). OpenLane2 flow." \
  -m "$F3_NUM" -l "F3-TinyTapeout"
echo "✓ F3.1"

gh issue create -R $REPO -t "F3.2: Bring-up PCB design (KiCad)" \
  -b "KiCad PCB design: QSPI flash socket, QSPI PSRAM socket, FTDI USB-UART bridge, power regulation, debug LEDs, PMOD connectors. Compatible with TT demo board carrier." \
  -m "$F3_NUM" -l "F3-TinyTapeout"
echo "✓ F3.2"

gh issue create -R $REPO -t "F3.3: Post-silicon verification test plan" \
  -b "Test plan for the physical chip: Fibonacci(10) via UART, echo neuron demo (host sends message → chip processes → chip responds), basic trap testing (div by zero, stack overflow)." \
  -m "$F3_NUM" -l "F3-TinyTapeout"
echo "✓ F3.3"

echo ""
echo "=== F4 Issues ==="

gh issue create -R $REPO -t "F4.1: 4-core mailbox mesh router" \
  -b "Fair, deadlock-free message router for 4 Nano cores. Round-robin arbiter with per-core FIFO buffers. Configurable routing (direct + broadcast). Synthesize on A7-Lite XC7A200T." \
  -m "$F4_NUM" -l "F4-FPGA"
echo "✓ F4.1"

gh issue create -R $REPO -t "F4.2: Sleep/wake event-driven logic" \
  -b "Per-core sleep/wake mechanism: core sleeps on empty inbox (clock-gated), wakes on mailbox message arrival (interrupt). Measure idle power reduction on FPGA." \
  -m "$F4_NUM" -l "F4-FPGA"
echo "✓ F4.2"

gh issue create -R $REPO -t "F4.3: Multi-core demos — ping-pong + echo-chain + SNN" \
  -b "Three demos on 4-core FPGA fabric:
1. Ping-pong: Core 0 sends to Core 1, Core 1 responds — minimal actor pattern
2. Echo-chain: 4 cores in a chain, message passes through all, last outputs via UART
3. SNN: 4 LIF neurons, configurable topology, spike-based communication" \
  -m "$F4_NUM" -l "F4-FPGA"
echo "✓ F4.3"

echo ""
echo "=== Labelek létrehozása ==="

gh label create "F2-RTL" -R $REPO -c "1d76db" -d "Phase F2: RTL implementation" 2>/dev/null || echo "(F2-RTL already exists)"
gh label create "F3-TinyTapeout" -R $REPO -c "0e8a16" -d "Phase F3: Tiny Tapeout first silicon" 2>/dev/null || echo "(F3-TinyTapeout already exists)"
gh label create "F4-FPGA" -R $REPO -c "d93f0b" -d "Phase F4: Multi-core FPGA" 2>/dev/null || echo "(F4-FPGA already exists)"

echo ""
echo "=== Kész! ==="
echo "Milestones: https://github.com/$REPO/milestones"
echo "Issues: https://github.com/$REPO/issues"
