# LED blink — OpenXC7 build

> Magyar verzió: [README-hu.md](README-hu.md)

Same `led_blink.v` as the Vivado build, but through an **open-source toolchain**: **Yosys + nextpnr-xilinx + Project X-Ray**. The goal is to show that the CLI-CPU F2.7 smoke test isn't Vivado-specific, and to lay groundwork for parallel CI around F4.

**Status (2026-04-24):** ✅ Build and programming successful on A7-Lite 200T (`xc7a200tfbg484-2`). Bitstream: 9.3 MB, chipdb: 331 MB. Programming done with openFPGALoader v1.1.1 without Vivado — LEDs blink.

## Files

| File | Role |
|------|------|
| `led_blink.xdc` | Pin constraints in OpenXC7 format (no `-dict`, `LOC` / `IOSTANDARD` separate) |
| `Makefile` | Build pipeline: Yosys → nextpnr-xilinx → fasm2frames → xc7frames2bit |
| `build.sh` | WSL wrapper: PATH setup, S: drvfs mount, `make` launch |

`led_blink.v` is **the same** as in the Vivado build — located one level up (`../led_blink.v`).

## Requirements

- **Ubuntu 22.04** (or compatible) in WSL2
- **OpenXC7 snap package**: `wget -qO - https://raw.githubusercontent.com/openXC7/toolchain-installer/main/toolchain-installer.sh | bash`
  - Installs: `yosys`, `nextpnr-xilinx`, `bbasm`, `fasm2frames`, `xc7frames2bit`, `bit2fasm` → `/snap/bin/`
- **make**: `sudo apt install make`
- **python3** (for chipdb generation; `pypy3` is faster, but optional)

## Usage

From WSL Ubuntu (or via WSL wrapper from Windows CMD/PowerShell):

```bash
# Full build
bash build.sh all

# Environment check only
bash build.sh check-env

# Clean
bash build.sh clean
```

From Windows PowerShell (no separate mounting needed — build.sh handles it):
```powershell
wsl -d Ubuntu-22.04 -- bash /mnt/s/github.com/FenySoft/CLI-CPU/rtl/fpga/smoke_test/OpenXC7/build.sh all
```

## Build pipeline stages

```
led_blink.v
    │
    ▼ [yosys synth_xilinx]
led_blink.json (post-synth netlist)
    │
    ▼ [nextpnr-xilinx --chipdb xxx.bin --xdc yyy.xdc]
led_blink.fasm (FPGA Assembly — text)
    │
    ▼ [fasm2frames --part xx --db-root prjxray-db/artix7]
led_blink.frames (binary frames)
    │
    ▼ [xc7frames2bit --part_file part.yaml]
led_blink.bit (bitstream — uploadable)
```

**First build:** ~10–15 minutes (due to chipdb generation, ~5–10 min for 200T with pypy3, ~15–25 min with python3).
**Subsequent builds:** ~1–2 minutes (chipdb is cached in the `chipdb/` folder).

## Comparison to Vivado

A successful OpenXC7 build proves:
- The `led_blink.v` design is **tool-independent** — uses no Vivado-specific primitives
- The **full XC7A200T pipeline** (synth + P&R + bitstream) works with the open toolchain
- **Parallel CI is technically feasible** for F4 (Nano core, MMCM + UART only)

## Bitstream programming

**With Vivado Hardware Manager** (most convenient for us):

The `led_blink.bit` loads just like the original Vivado-generated bitstream. The bitstream format is identical.

**Open-source alternative (`openFPGALoader` from WSL, verified 2026-04-24):**

Prerequisite: **usbipd-win** USB passthrough so the Windows host FTDI is accessible from WSL.

```powershell
# Windows admin PowerShell — one-time bind (on install):
winget install --interactive --exact dorssel.usbipd-win
& "C:\Program Files\usbipd-win\usbipd.exe" bind --busid <BUSID>
```

```powershell
# Windows regular PowerShell — attach to WSL (every session):
& "C:\Program Files\usbipd-win\usbipd.exe" attach --wsl --busid <BUSID>
```

```bash
# WSL — openFPGALoader build (one-time):
sudo apt install libftdi1-dev libhidapi-dev libusb-1.0-0-dev cmake build-essential git pkg-config libudev-dev zlib1g-dev
git clone https://github.com/trabucayre/openFPGALoader.git
cd openFPGALoader && mkdir build && cd build && cmake .. && make -j$(nproc) && sudo make install

# WSL — programming (for A7-Lite 200T):
sudo openFPGALoader --cable ft232 --fpga-part xc7a200tfbg484 --bitstream led_blink.bit
```

A7-Lite USB-JTAG uses an FTDI FT232H (VID:PID `0403:6014`). The `--cable ft232` parameter matches, `--fpga-part xc7a200tfbg484` names the exact chip.

**Note:** before running openFPGALoader, **Disconnect the board in Vivado Hardware Manager** to release the JTAG device. Once `usbipd attach` is done, Windows also loses the device and it's only accessible from WSL.

## Known differences from Vivado build

| Item | Vivado | OpenXC7 |
|------|--------|---------|
| XDC syntax | `set_property -dict { PACKAGE_PIN X IOSTANDARD Y }` | `set_property LOC X [...]` + `set_property IOSTANDARD Y [...]` |
| Clock constraint | `create_clock -period 20.000` in XDC | nextpnr auto-detects (not needed for LED blink) |
| Bitstream config | `CONFIG_VOLTAGE`, `CFGBVS`, `BITSTREAM.*` in XDC | command-line arguments to `xc7frames2bit` |
| Warning style | `[Synth 8-7080]`, `[Place 30-2953]` | Yosys + nextpnr native style |
| Build time (LED blink) | ~45 sec | ~15 min (first, chipdb) / ~1 min (cached) |
| Bitstream size | ~1–2 MB (compressed) | 9.3 MB (uncompressed) |
| Timing report detail | Full WNS/TNS/WHS/THS | Slack number, less detailed visualization |

## Troubleshooting

**`make: command not found`** — `sudo apt install make`

**`yosys: command not found`** — `/snap/bin` not in PATH. `build.sh` handles this. Manually: `export PATH=/snap/bin:$PATH`

**`cannot access /mnt/s`** — Not auto-mounted in WSL. `build.sh` auto-mounts on run. Manually: `sudo mount -t drvfs S: /mnt/s`

**`chipdb generation failed`** — pypy3 would be ideal, python3 works. For pypy3: `sudo apt install pypy3`, then in `Makefile`: `PYTHON := pypy3`

**`libffi.so.7: cannot open shared object file`** — warning in `fasm2frames`, not an error. Slower Python parser fallback is used. To speed up: `pip install -v fasm` — but not needed for LED blink.

**P&R takes much longer than expected** — XC7A200T is large, first P&R is ~1–2 minutes. If much longer, likely XDC error (e.g., nonexistent pin).
