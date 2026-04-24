# MicroPhase A7-Lite XC7A200T — board referencia

> English version: [A7-Lite-en.md](A7-Lite-en.md)
>
> Források:
> - [MicroPhase fpga-docs GitHub — A7-LITE](https://github.com/MicroPhase/fpga-docs/tree/master/source/DEV_BOARD/A7-LITE)
> - `A7-LITE_R11.pdf` (schematic R11, helyi másolat)
> - `A7-LITE_R11_Dimensions.pdf` (mechanikai méretek)
> - `XME0712_Pinout_Table_R12.xlsx` (GPIO pin tábla)

Ez a dokumentum a CLI-CPU projekt FPGA referencia platformjának legfontosabb technikai paramétereit gyűjti össze. A board **az F2.7 (egymagos validáció)**, **F4 (multi-core Cognitive Fabric)**, **F5 (Rich core)** és **F6-FPGA (multi-board háló)** fázisok elsődleges hardvere.

## Board-változatok

A MicroPhase A7-Lite három FPGA variánssal gyártott, közös PCB-vel. A pin-assignment mindhárom variánson azonos (a doksi egységesen erre a board-ra vonatkozik):

| Variáns | FPGA | Package |
|---------|------|---------|
| 35T | XC7A35T-2FGG484L | FGG484 |
| 100T | XC7A100T-2FGG484L | FGG484 |
| **200T** (CLI-CPU) | **XC7A200T-2FBG484L** | **FBG484** |

**Vivado part string:** `xc7a200tfbg484-2`

## FPGA logikai erőforrások (XC7A200T)

| Elem | Mennyiség |
|------|-----------|
| Logic Cells | 215 360 |
| Slices | 33 650 |
| CLB Flip-Flops | 269 200 |
| Distributed RAM | 2 888 Kb |
| Block RAM (36 Kb blokkok) | 365 × 36 Kb = **13 140 Kb (~13.1 Mbit)** |
| DSP48 Slices | 740 |
| CMTs (1 MMCM + 1 PLL) | 10 |
| Single-ended I/O | max 500 |
| Differenciális I/O pár | 240 |
| GTP transceiver | 16 (max 6.6 Gb/s) |
| PCIe Gen2 | 1 |
| XADC (analóg) | 1 |
| AES/HMAC blokk | 1 |

## Memória

**DDR3L SDRAM** (on-board, nem SODIMM):
- Chip: **Micron MT41K256M16** (256 M × 16 bit)
- Kapacitás: **512 MB** (1 × 16-bit wide)
- Sebesség: 1066 Mbps
- Relevancia: **F5 Rich core GC / heap** kritikus, **F6 inter-chip bridge** buffer

**QSPI Flash** (konfiguráció + user adat):
- Chip: **ISSI IS25L128F** (BLE változat)
- Kapacitás: **128 Mbit = 16 MB**
- Szerep: FPGA bitstream + user alkalmazás + adat

**Micro-SD card slot:**
- Relevancia: későbbi Neuron OS boot / filesystem (F7)

## Kommunikáció

| Interfész | Chip | Megjegyzés |
|-----------|------|-----------|
| **Gigabit Ethernet** | Realtek RTL8211F | 10/100/1000 M, RGMII interfésszel, MDIO. **F6 multi-board bridge-hez kell.** |
| **HDMI** | beépített | 1080p output. Később SNN inference vizualizáció, demó kimenet. |
| **USB-JTAG** | beépített | Vivado Hardware Manager hozzáférés |
| **USB-UART** | **CH340** | **UART_TX = V2, UART_RX = U2**. Ezen fog menni a Fibonacci UART kimenet az F2.7 demóban. |

## User I/O

**Aktív alacsony / active-low LED-ek** (a schematic szerint a LED anódja VCC-n, katódja az FPGA pin-en — LED akkor világít, ha a pin logikai `0`; **ellenőrzendő a schematic-kel** a bring-up során):

| Jelölés | Signal | FPGA Pin |
|---------|--------|----------|
| D6 | LED1 | **M18** |
| D5 | LED2 | **N18** |

**Push button-ok:**

| Jelölés | Signal | FPGA Pin |
|---------|--------|----------|
| K1 | KEY1 | **AA1** |
| K2 | KEY2 | **W1** |
| K3 | Reset | — (FPGA reset) |

**Órajel:**
- 50 MHz aktív oszcillátor
- FPGA pin: **J19**

## GPIO expanziós header-ek

Két darab 50-pin, 2.54 mm raszterű header (**összesen 100 pin**):

**JP1 (Header A):**
- 21 differenciális pár (42 I/O)
- Feszültség: default 3.3V, konfigurálható 1.2V – 3.3V (VCCIO_A szabályozás)
- Plusz 5V és 3.3V táp pin-ek

**JP2 (Header B):**
- 21 differenciális pár (42 I/O)
- Feszültség: **fix 3.3V**
- Plusz 5V és 3.3V táp pin-ek

Minden user I/O length-matched (differenciális párokhoz szükséges).

> A konkrét GPIO1_*/GPIO2_* → FPGA pin mapping az `XME0712_Pinout_Table_R12.xlsx` fájlban található (100 soros tábla).

## Táp és méret

- **Táp:** USB 5V vagy külön 5V DC (board-on integrált power tree a 3.3V, 1.8V, 1.5V, 1.0V rail-ekhez)
- **Méret:** kompakt form factor, pontos méretek a `A7-LITE_R11_Dimensions.pdf`-ben

## Release notes és kompatibilitás

- **Ajánlott Vivado verzió:** 2021.1+ — a CLI-CPU projekt **2024.2-t** használja (tesztelve a smoke-teszten)
- **Pin-assignment stabil** a MicroPhase A7-Lite mindhárom variánson (35T, 100T, 200T)
- **Vivado ML Standard (ingyenes WebPACK)** támogatja az XC7A200T-t
- **OpenXC7 toolchain** szintén támogatja az XC7A200T-t (2026-04-24-én verifikálva LED blink-kel) — lásd `tool-openness-hu.md`

## Fázis-szintű használat a CLI-CPU roadmap-ben

| Fázis | Mire használjuk a board-ot |
|-------|---------------------------|
| **F2.7** | Egymagos Nano core + UART Fibonacci(20) demó |
| **F4** | 4 × Nano core + mailbox router + sleep/wake |
| **F5** | 1–2 Rich core + 4–8 Nano core (DDR3 a GC heap-hez) |
| **F6-FPGA** | 3 darab board Ethernet hálóban, cross-chip mailbox bridge |

## Dokumentum-verzió

- **2026-04-24** — első verzió a board megérkezésekor, a GitHub reference manual alapján
