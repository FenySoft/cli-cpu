# LED blink smoke test

> Magyar verzió: [README-hu.md](README-hu.md)

The first CLI-CPU bitstream of our own on the A7-Lite 200T board: a ~10-line Verilog counter blinks the two user LEDs at different rates. Its purpose is to validate the **FPGA → A7-Lite 200T** end-to-end bring-up flow before we synthesize the real Nano core RTL (F2.7).

## Two parallel toolchains, same Verilog

| Toolchain | Subdirectory | Build time | License |
|-----------|--------------|------------|---------|
| **Vivado ML Standard 2024.2** | [`Vivado/`](Vivado/README.md) | ~5–10 min | closed, free (WebPACK) |
| **OpenXC7** (Yosys + nextpnr-xilinx) | [`OpenXC7/`](OpenXC7/README.md) | ~15 min (first) / ~1 min (cached) | 100% open source |

Both synthesize the **same `led_blink.v`** onto canonical A7-Lite 200T pins. As of 2026-04-24 both are verified on real hardware (LEDs blinking).

## Files

```
rtl/fpga/smoke_test/
  ├── led_blink.v           ← shared Verilog RTL (used by both toolchains)
  ├── README.md (en)
  ├── README-hu.md (hu)
  ├── Vivado/               ← Vivado-specific build
  │   ├── led_blink.xdc
  │   ├── create_project.tcl
  │   ├── README.md (en)
  │   └── README-hu.md (hu)
  └── OpenXC7/              ← OpenXC7-specific build
      ├── led_blink.xdc
      ├── Makefile
      ├── build.sh
      ├── README.md (en)
      └── README-hu.md (hu)
```

`led_blink.v` is a **single** shared file — 10 lines of Verilog, 25-bit counter, two LED outputs at different frequencies:
- **LED1 (M18):** `counter[24]` → ~0.75 Hz
- **LED2 (N18):** `counter[23]` → ~1.5 Hz (twice as fast)

## Which to use?

**Vivado** — when:
- You need fast iteration during development
- Detailed timing report matters (WNS/TNS/WHS/THS)
- Closed flow is acceptable (e.g. NLnet "libre silicon" assessment not urgent)

**OpenXC7** — when:
- Full libre silicon flow is the goal (for CI, publication)
- Vivado license / access is limited
- You want to prove Vivado-independence

**Or both** — per `docs/tool-openness-en.md`, this is the recommended strategy moving toward F4.

## Why no testbench?

This is a smoke test, not the real Nano core. Simulating a 25-bit counter would take ~33 million cycles — pointless. The "test" is the physical LED blinking itself.

Real RTL modules (ALU, decoder, microcode) are all covered by cocotb testbenches under `rtl/tb/`.
