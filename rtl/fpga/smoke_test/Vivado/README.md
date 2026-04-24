# LED blink — Vivado build

> Magyar verzió: [README-hu.md](README-hu.md)

The CLI-CPU F2.7 smoke test on the **Vivado toolchain**: same `led_blink.v` as the OpenXC7 build, but through the traditional AMD/Xilinx closed-source tool chain. The "convenient" path — faster build (45 sec vs 15 min), better timing report, GUI.

**Status (2026-04-24):** ✅ Build and programming successful on A7-Lite 200T. WNS = 17.972 ns at 50 MHz.

## Files

| File | Role |
|------|------|
| `led_blink.xdc` | Pin constraints (J19 clock, M18/N18 LEDs, bitstream config) |
| `create_project.tcl` | Vivado project auto-generation script — synth + implementation + bitstream |

`led_blink.v` is **one level up** (`../led_blink.v`) — shared with the OpenXC7 build.

## Requirements

- **Vivado ML Standard 2024.2** (or newer) on Windows or Linux
  - Free WebPACK license supports XC7A200T
  - Artix-7-only install is enough (~32 GB final disk)

## Usage

**Batch mode (fast, from command line):**

```bash
cd rtl/fpga/smoke_test/Vivado/
vivado -mode batch -source create_project.tcl
```

**GUI mode:**

1. Open Vivado
2. Tools → Run Tcl Script → `create_project.tcl`
3. Wait for "Build SIKERES" message

The build takes ~5–10 minutes. Result:
```
rtl/fpga/smoke_test/Vivado/build/led_blink.runs/impl_1/led_blink.bit
```

## Bitstream upload via JTAG

1. Connect the board via USB-JTAG cable
2. Vivado GUI → Open Hardware Manager → Open target → **Auto Connect**
3. Right-click `xc7a200t_0` → **Program Device...**
4. Select the `.bit` file → **Program**
5. After ~2–3 sec, the LEDs should blink:
   - **LED1 (M18):** ~0.75 Hz (slower)
   - **LED2 (N18):** ~1.5 Hz (twice as fast)

## Expected result

The board's two green LEDs **blink at different rates** — one twice as fast as the other. This proves:

- Vivado 2024.2 correctly synthesizes for Artix-7
- The XDC constraint file is correct (pin names and I/O standard)
- The JTAG programming chain works
- Our own bitstream runs on the FPGA

If the LEDs **light up inversely** (on when they should be off), invert the `led_blink.v` assign lines — a consequence of the MicroPhase active-low LED wiring.

## Troubleshooting

- **Vivado doesn't find the FPGA when programming:** restart Open Hardware Manager → Auto Connect. Swap USB-JTAG cable / port.
- **Timing violation during synthesis:** unlikely, 50 MHz for a counter has massive slack — if it happens, check the `create_clock` definition in the XDC.
- **LEDs don't light up:** (a) wrong pin (check `docs/A7-Lite/A7-Lite-en.md`), (b) active-low issue (invert), (c) bitstream wasn't uploaded (check Hardware Manager status).

## Vivado warnings (4 items, all benign)

The build produces these warnings, all in the "design too simple" category:

1. `[Vivado 12-7122]` Auto Incremental Compile — always on first build
2. `[Synth 8-7080]` Parallel synthesis criteria not met — design is small
3. `[Place 30-2953]` Timing driven mode turned off — slack is massive
4. `[Place 46-29]` Physical synthesis skipped — same reason

Nothing needs fixing.

## Why no testbench?

This is a smoke test, not the real Nano core. Simulating a 25-bit counter would take ~33 million cycles — pointless. The "test" is the physical LED blinking itself.

Real RTL modules (ALU, decoder, microcode) are all covered by cocotb testbenches under `rtl/tb/`.
