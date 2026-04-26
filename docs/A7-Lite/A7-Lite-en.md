# MicroPhase A7-Lite XC7A200T — board reference

> Magyar verzió: [A7-Lite-hu.md](A7-Lite-hu.md)
>
> Sources:
> - [MicroPhase fpga-docs GitHub — A7-LITE](https://github.com/MicroPhase/fpga-docs/tree/master/source/DEV_BOARD/A7-LITE)
> - `A7-LITE_R11.pdf` (schematic R11, local copy)
> - `A7-LITE_R11_Dimensions.pdf` (mechanical dimensions)
> - `XME0712_Pinout_Table_R12.xlsx` (GPIO pin table)

This document collects the most important technical parameters of the CLI-CPU project's FPGA reference platform. The board is the primary hardware for phases **F2.7 (single-core validation)**, **F4 (multi-core Cognitive Fabric)**, **F5 (Rich core)**, and **F6-FPGA (multi-board mesh)**.

## Board variants

The MicroPhase A7-Lite is manufactured in three FPGA variants sharing the same PCB. Pin assignments are identical across all variants (this document applies uniformly to the whole board family):

| Variant | FPGA | Package |
|---------|------|---------|
| 35T | XC7A35T-2FGG484L | FGG484 |
| 100T | XC7A100T-2FGG484L | FGG484 |
| **200T** (CLI-CPU) | **XC7A200T-2FBG484L** | **FBG484** |

**Vivado part string:** `xc7a200tfbg484-2`

## FPGA logic resources (XC7A200T)

| Element | Amount |
|---------|--------|
| Logic Cells | 215,360 |
| Slices | 33,650 |
| CLB Flip-Flops | 269,200 |
| Distributed RAM | 2,888 Kb |
| Block RAM (36 Kb blocks) | 365 × 36 Kb = **13,140 Kb (~13.1 Mbit)** |
| DSP48 Slices | 740 |
| CMTs (1 MMCM + 1 PLL) | 10 |
| Single-ended I/O | up to 500 |
| Differential I/O pair | 240 |
| GTP transceivers | 16 (up to 6.6 Gb/s) |
| PCIe Gen2 | 1 |
| XADC (analog) | 1 |
| AES/HMAC block | 1 |

## Memory

**DDR3L SDRAM** (on-board, not SODIMM):
- Chip: **Micron MT41K256M16** (256 M × 16 bit)
- Capacity: **512 MB** (1 × 16-bit wide)
- Speed: 1066 Mbps
- Relevance: **critical for F5 Rich core GC / heap**, **F6 inter-chip bridge buffer**

**QSPI Flash** (configuration + user data):
- Chip: **ISSI IS25L128F** (BLE variant)
- Capacity: **128 Mbit = 16 MB**
- Role: FPGA bitstream + user application + data

**Micro-SD card slot:**
- Relevance: later Symphact boot / filesystem (F7)

## Communication

| Interface | Chip | Notes |
|-----------|------|-------|
| **Gigabit Ethernet** | Realtek RTL8211F | 10/100/1000 M, RGMII, MDIO. **Required for F6 multi-board bridge.** |
| **HDMI** | built-in | 1080p output. Later: SNN inference visualization, demo output. |
| **USB-JTAG** | built-in | Vivado Hardware Manager access |
| **USB-UART** | **CH340** | **UART_TX = V2, UART_RX = U2**. Carries the Fibonacci UART output in the F2.7 demo. |

## User I/O

**Active-low LEDs** (per schematic: LED anode on VCC, cathode on FPGA pin — LED lights when pin is logic `0`; **verify against schematic** at bring-up time):

| Marker | Signal | FPGA Pin |
|--------|--------|----------|
| D6 | LED1 | **M18** |
| D5 | LED2 | **N18** |

**Push buttons:**

| Marker | Signal | FPGA Pin |
|--------|--------|----------|
| K1 | KEY1 | **AA1** |
| K2 | KEY2 | **W1** |
| K3 | Reset | — (FPGA reset) |

**Clock:**
- 50 MHz active oscillator
- FPGA pin: **J19**

## GPIO expansion headers

Two 50-pin 2.54 mm headers (**100 pins total**):

**JP1 (Header A):**
- 21 differential pairs (42 I/O)
- Voltage: default 3.3V, configurable 1.2V – 3.3V (VCCIO_A regulation)
- Plus 5V and 3.3V supply pins

**JP2 (Header B):**
- 21 differential pairs (42 I/O)
- Voltage: **fixed 3.3V**
- Plus 5V and 3.3V supply pins

All user I/Os are length-matched (required for differential pairs).

> The concrete GPIO1_*/GPIO2_* → FPGA pin mapping is in the `XME0712_Pinout_Table_R12.xlsx` file (100-row table).

## Power and dimensions

- **Power:** USB 5V or external 5V DC (on-board integrated power tree for 3.3V, 1.8V, 1.5V, 1.0V rails)
- **Dimensions:** compact form factor; exact dimensions in `A7-LITE_R11_Dimensions.pdf`

## Release notes and compatibility

- **Recommended Vivado version:** 2021.1+ — CLI-CPU uses **2024.2** (verified in the smoke test)
- **Pin assignments are stable** across all three MicroPhase A7-Lite variants (35T, 100T, 200T)
- **Vivado ML Standard (free WebPACK)** supports XC7A200T
- **OpenXC7 toolchain** also supports XC7A200T (verified 2026-04-24 with LED blink) — see `tool-openness-en.md`

## Phase-level usage in the CLI-CPU roadmap

| Phase | What we use the board for |
|-------|---------------------------|
| **F2.7** | Single Nano core + UART Fibonacci(20) demo |
| **F4** | 4 × Nano core + mailbox router + sleep/wake |
| **F5** | 1–2 Rich core + 4–8 Nano core (DDR3 for GC heap) |
| **F6-FPGA** | 3 boards in Ethernet mesh, cross-chip mailbox bridge |

## Document version

- **2026-04-24** — initial version upon board arrival, based on the GitHub reference manual
