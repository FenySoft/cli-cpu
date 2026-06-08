---
status: educational
---

# 8-bit CIL-T0 — Discrete TTL/CMOS Build

> Magyar verzió: [8bit-cil-t0-hu.md](8bit-cil-t0-hu.md)

> **⚠️ Educational / demonstration document.** This is a **breadboard-level, discrete 74HC logic chip** build of an 8-bit CIL-T0 processor — a Ben Eater-style "build it yourself" project. It is NOT part of the CFPU silicon roadmap; its purpose is to teach the ISA, support education, and build community. The main simulator and FPGA implementation (F1.5–F2.8) realize the 32-bit CIL-T0; this 8-bit variant is a didactic descendant.

This document summarizes how the CIL-T0 ISA can be built as an **8-bit, discrete-component** version in tangible hardware, and how it can be programmed.

## Motivation

The CLI-CPU project lacks an accessible, physically tangible entry point. There is no Ben Eater-level, component-level CPU-building content on Hungarian YouTube (see the research in the [Background](#background) section). A discrete 8-bit CIL-T0 is:

- **Tangible**: the data bus is visible on LEDs, the clock can be single-stepped
- **Educational**: every step of stack-based execution can be followed
- **Community-building**: sellable as a kit to interested makers
- **Credible**: part of the CLI-CPU "build journey" credibility-first strategy

## Why is a stack-based ISA suited to discrete builds?

CIL-T0 is **stack-based** — a concrete hardware advantage at breadboard level compared to register-based ISAs (6502, RISC-V):

| Aspect | Register-based | Stack-based (CIL-T0) |
|---|---|---|
| Register file | Many flip-flop chips | ❌ None — only TOS/TOS1 cache |
| Forwarding logic | Complex | ❌ None |
| Bus control | Complex | Simpler (push/pop) |
| Instruction encoding | Register fields | Implicit (shorter decoder) |

Because there are no named registers, there is no "register size" problem either: the stack values are uniformly 8-bit in this variant.

## Block diagram

```
        ┌─────────────┐      ┌──────────────┐
        │  Program    │      │  Microcode   │
        │  EEPROM     │      │  ROM (3×)    │
        │  AT28C256   │      │  AT28C256    │
        └──────┬──────┘      └──────┬───────┘
               │ instruction        │ control signals
               ▼                    ▼
        ┌─────────────────────────────────────┐
        │           CONTROL + DECODER         │
        │         (74HC138 chip-select)       │
        └─────────────────┬───────────────────┘
                          │
   ┌──────────┬───────────┼───────────┬──────────┐
   ▼          ▼           ▼           ▼          ▼
┌──────┐  ┌──────┐   ┌────────┐  ┌────────┐  ┌──────┐
│  PC  │  │  SP  │   │  ALU   │  │  TOS   │  │ Stack│
│HC191 │  │HC191 │   │ HC283  │  │ cache  │  │ SRAM │
│      │  │      │   │ +86/08 │  │ HC374  │  │62256 │
│      │  │      │   │ /32/04 │  │        │  │      │
└──────┘  └──────┘   └────────┘  └────────┘  └──────┘
   │          │           │           │          │
   └──────────┴───────────┴─────8-bit BUS────────┘
                  (74HC245 buffer ×5)
                          │
                    ┌─────┴───────┐
                    │ LED display │
                    │ 8 red +     │
                    │ 8 yellow    │
                    └─────────────┘
```

## Functional units

| Unit | Chip | Role |
|---|---|---|
| **ALU** | 2× 74LS181 (+1× 74HCT245 level shifter) | complete 8-bit ALU, 32 functions (ADD/SUB/AND/OR/XOR/NOT...) |
| **Registers** | 74HC374 ×6 | TOS, TOS-1, IR, control-word latch, MAR×2 (16-bit) |
| **Program counter** | 74HC191 ×4 + 74HC245 ×2 | 16-bit instruction address, up/down + jump load |
| **Stack pointer** | 74HC191 ×4 + 74HC245 ×2 | 16-bit stack address, push/pop |
| **Micro-step counter** | 74HC191 ×1 | microcode phase (opcode → control word) |
| **Bus buffer** | 74HC245 ×6 total | 8-bit bus + 16-bit address buffer |
| **Decoder** | 74HC138 ×2 | memory map / chip-select |
| **Stack memory** | 62256 SRAM | 32 KB — full 32K used (16-bit address) |
| **Program store** | AT28C256 | 32 KB EEPROM |
| **Microcode ROM** | AT28C256 ×3 | control signals per opcode |
| **Clock (Ben Eater)** | 3× NE555 + 1 MΩ pot | astable (run) + monostable (step) + bistable (debounce) |

The total chip count is **~37 ICs** — with 16-bit addressing (full 32K memory) and the **2× 74LS181** ALU. The 74LS181 cuts the discrete ALU (~15 chips) down to 2. Comparable to Ben Eater's 8-bit CPU project.

## Microcode is the key

The 48 opcodes would be unmanageable with discrete control logic. The solution is a **microcode ROM**: the opcode + state-machine phase forms the ROM address input, and the output drives all chip `enable`/`direction` lines. This is exactly Ben Eater's approach. 3× AT28C256 store the full control-signal map.

## Programming and power

The AT28C256 EEPROMs (program + microcode) are written with a **dedicated EEPROM programmer** — the chip placed in a ZIF socket, connected to the PC over USB. This is faster and more reliable than manual GPIO bitbanging.

- **Programmer**: TL866II+ or XGecu T48 (wide AT28Cxxx support, `minipro` / `Xgpro` software)
- **Power (for running)**: 5V USB-C or Raspberry Pi 5V GPIO → breadboard power rail (~270 mA consumption)
- **Microcode generation**: a script produces the control-signal map as a binary image, the programmer's software writes it to the chip

> The programmer is a **one-time tool investment**, not part of the per-kit bill of materials.

## Bill of materials (BOM)

The complete ordering list with Hestore part numbers (tab-separated, paste-able into the cart) is in a separate file, outside the repo:

➡️ `~/Work/CFPU/8bit-cil-t0/8bit-cil-t0-bom.txt`

Every chip is orderable in **DIP/THT package from Hestore**. One caveat: the **74HC283 has limited stock** — check it first; if out of stock it can be sourced from AliExpress (~3–5 weeks).

> The **EEPROM dominates the material cost** (4× AT28C256 per kit). The detailed pricing and the volume (1/5/10/15/20 kit) calculation live next to the BOM file in the `~/Work/CFPU/8bit-cil-t0/` working folder — deliberately kept out of the public document.

## Relationship to the CLI-CPU project

| | 8-bit discrete (this) | 32-bit simulator/FPGA (main project) |
|---|---|---|
| Goal | Education, demo, community | Reference + silicon path |
| Width | 8-bit | 32-bit |
| Implementation | 74HC breadboard | C# sim + Verilog FPGA |
| ISA | CIL-T0 subset | Full CIL-T0 (48 opcodes) |
| Phase | Standalone didactic branch | F1.5 DONE → F2.8 |

The 8-bit variant demonstrates the same **ISA philosophy** (stack-based, int-only, object-free) in tangible hardware that the 32-bit reference simulator and the FPGA implementation realize in full depth.

## Background

There is currently **no** Ben Eater-level, component-level CPU-building channel on Hungarian YouTube. The existing Hungarian tech channels (Kernel Pánik, Neonity, TECHWorldhu) focus on hardware reviews and IT news, not deep architectural education. This discrete CIL-T0 kit + documentation targets exactly this unfilled gap.
