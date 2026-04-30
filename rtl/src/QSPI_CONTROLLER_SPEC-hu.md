# F2.4 QSPI Controller — Kontrakt és Portspec

> English version: [QSPI_CONTROLLER_SPEC-en.md](QSPI_CONTROLLER_SPEC-en.md)

> Belső munka-spec a TDD ciklushoz. Az architekturális kontextus a `docs/architecture-hu.md`-ben.
>
> **Hatókör:** Belső RTL munka-spec, nem publikus dokumentum.
>
> Version: 1.1

## Cél

A CPU belső SRAM-szerű olvasás/írás kéréseit QSPI protokollra fordítja. Két külső eszközt kezel:
- **QSPI Flash** — CODE és DATA szegmens (read-only)
- **QSPI PSRAM** — STACK szegmens (read-write)

A modul a stack cache `sram_*` master portjaival kompatibilis interfészt nyújt a CPU-oldali portokon. A jövőbeli I-cache és load/store unit is ezen az interfészen keresztül éri el a külső memóriát (bus arbiter-en át).

**F2.4 hatókör:** Single-word (32-bit) tranzakciók, nincs burst. A burst mód (I-cache line fill) F5-re marad.

## Modul: `cilcpu_qspi_controller`

### Portok

| Irány | Név | Szélesség | Leírás |
|-------|-----|-----------|--------|
| in | `clk` | 1 | Fő órajel (50 MHz) |
| in | `rst_n` | 1 | Aszinkron aktív-low reset |
| **CPU-oldal** | | | |
| in | `cpu_addr` | 24 | Byte cím — felső nibble (`[23:20]`) a szegmens szelektáló |
| in | `cpu_wdata` | 32 | Írandó adat |
| out | `cpu_rdata` | 32 | Olvasott adat (regisztrált, `cpu_ready`-vel egyidőben érvényes) |
| in | `cpu_re` | 1 | Olvasás indítás (1-ciklusos pulzus) |
| in | `cpu_we` | 1 | Írás indítás (1-ciklusos pulzus) |
| out | `cpu_ready` | 1 | Tranzakció kész (1-ciklusos pulzus) |
| out | `cpu_busy` | 1 | Tranzakció folyamatban |
| **QSPI-oldal** | | | |
| out | `qspi_clk` | 1 | QSPI órajel kimenet (main_clk / 2 = 25 MHz) |
| out | `qspi_cs_flash_n` | 1 | Flash chip select (aktív-low) |
| out | `qspi_cs_psram_n` | 1 | PSRAM chip select (aktív-low) |
| out | `qspi_dq_out` | 4 | Adat kimenet DQ[3:0] |
| in | `qspi_dq_in` | 4 | Adat bemenet DQ[3:0] |
| out | `qspi_dq_oe` | 1 | Output enable (1 = DQ-t a controller hajtja) |

**Megjegyzés:** Verilator nem kezeli az `inout` tri-state-et, ezért a DQ vonalak szimulációban `dq_out/dq_in/dq_oe` külön portokra bontva. Szintézis wrapper-ben `inout wire [3:0] qspi_dq`.

### Cím dekódolás

| `cpu_addr[23:20]` | Szegmens | Eszköz | Írható? | QSPI parancs (olvasás) | QSPI parancs (írás) |
|--------------------|----------|--------|---------|------------------------|----------------------|
| `4'h0` | CODE | Flash | Nem | `0x6B` (Quad Output Read) | — (elutasítva) |
| `4'h1` | DATA | Flash | Nem | `0x6B` (Quad Output Read) | — (elutasítva) |
| `4'h2` | STACK | PSRAM | Igen | `0xEB` (Fast Read QIO) | `0x38` (Quad Write) |
| egyéb | — | — | — | `cpu_ready=1` azonnal, NOP | `cpu_ready=1` azonnal, NOP |

**Flash-be írás elutasítása:** Ha `cpu_we=1` és a cím CODE vagy DATA szegmensbe esik, a controller `cpu_ready=1`-et ad azonnal, QSPI tranzakció nélkül. Nem trap — a microcode/firmware felelőssége nem írni read-only szegmensbe.

### Belső állapot

- `r_state[3:0]` — FSM állapot
- `r_bit_cnt[5:0]` — bit/nibble számláló a fázison belül
- `r_cmd[7:0]` — aktuális QSPI parancs byte
- `r_addr[23:0]` — aktuális QSPI cím (cpu_addr alsó 20 bitje, a szegmens prefix nélkül)
- `r_shift_out[31:0]` — kimenő adat shift regiszter
- `r_shift_in[31:0]` — bejövő adat shift regiszter
- `r_clk_phase` — QSPI órajel fázis (toggle flip-flop, /2 osztó)
- `r_is_write` — aktuális tranzakció írás-e
- `r_device` — 0=Flash, 1=PSRAM

### FSM állapotok

```
localparam [3:0] ST_IDLE     = 4'd0;   // Vár cpu_re/cpu_we-re
localparam [3:0] ST_CMD      = 4'd1;   // 8-bit parancs küldése (SPI, 1-bit)
localparam [3:0] ST_ADDR     = 4'd2;   // 24-bit cím küldése (Quad, 4-bit)
localparam [3:0] ST_DUMMY    = 4'd3;   // Dummy ciklusok (DQ Hi-Z)
localparam [3:0] ST_DATA_RD  = 4'd4;   // 32-bit adat olvasás (Quad, 4-bit)
localparam [3:0] ST_DATA_WR  = 4'd5;   // 32-bit adat írás (Quad, 4-bit)
localparam [3:0] ST_DONE     = 4'd6;   // cpu_ready=1, CS# deassert, → IDLE
```

### FSM átmenetek

```
                     cpu_re=1 (olvasás)
                    ┌──────────────────────────────────────────────┐
                    │                                              │
ST_IDLE ─→ ST_CMD ─→ ST_ADDR ─→ ST_DUMMY ─→ ST_DATA_RD ─→ ST_DONE ─→ ST_IDLE
                    │                    │
                    │  cpu_we=1 (írás)   └─→ ST_DATA_WR ─→ ST_DONE ─→ ST_IDLE
                    │                        (nincs DUMMY)
                    └──────────────────────────────────────────────┘
```

### Fázisonkénti viselkedés

#### ST_IDLE
- `cpu_ready=0` (kivéve érvénytelen cím vagy Flash-be írás → azonnali `cpu_ready=1`)
- `cpu_busy=0`
- `qspi_clk` gated (0-n tartva)
- `qspi_cs_flash_n=1`, `qspi_cs_psram_n=1` (mindkettő inaktív)
- `qspi_dq_oe=0` (Hi-Z)
- Ha `cpu_re=1` vagy `cpu_we=1`: latch address, select device, latch command, CS# assert → ST_CMD
- Ha `cpu_re=1` ÉS `cpu_we=1` egyszerre: az olvasás prioritást kap

#### ST_CMD — Parancs küldés
- SPI mód: kizárólag DQ[0] (MOSI) használata, `qspi_dq_oe=1`
- DQ[1]=1 (MISO — ki kell hajtani high-ra, mert a Flash idle állapotban high-t vár)
- DQ[2]=1, DQ[3]=1 (WP# és HOLD# inaktív)
- A parancs byte MSB-first, 1 bit per QSPI CLK rising edge
- 8 QSPI CLK = 16 main CLK ciklus
- `r_bit_cnt`: 7→0, minden QSPI CLK falling edge-en léptet
- Az `r_bit_cnt==0` és falling edge → ST_ADDR

#### ST_ADDR — Cím küldés
- Quad mód: DQ[3:0] mind használva, `qspi_dq_oe=1`
- 24-bit cím, MSB-first, 4 bit (1 nibble) per QSPI CLK
- 6 QSPI CLK = 12 main CLK ciklus
- `r_bit_cnt`: 5→0
- `r_bit_cnt==0` és falling edge → olvasásnál: ST_DUMMY; írásnál: ST_DATA_WR

#### ST_DUMMY — Dummy ciklusok
- `qspi_dq_oe=0` (Hi-Z) — bus turnaround
- Flash (0x6B): 8 QSPI CLK dummy
- PSRAM (0xEB): 6 QSPI CLK dummy
- `r_bit_cnt`: (dummy_count-1)→0
- `r_bit_cnt==0` és falling edge → ST_DATA_RD

#### ST_DATA_RD — Adat olvasás
- Quad mód: DQ[3:0] bemenet, `qspi_dq_oe=0`
- 32 bit, MSB-first nibble-ök, 4 bit per QSPI CLK rising edge-en mintavétel
- 8 QSPI CLK = 16 main CLK ciklus
- `r_shift_in` balra léptet, alsó 4 bitre beírja `qspi_dq_in`
- `r_bit_cnt==0` → ST_DONE

#### ST_DATA_WR — Adat írás
- Quad mód: DQ[3:0] kimenet, `qspi_dq_oe=1`
- 32 bit, MSB-first nibble-ök
- 8 QSPI CLK = 16 main CLK ciklus
- `r_shift_out` felső 4 bitje → DQ[3:0], balra léptet
- `r_bit_cnt==0` → ST_DONE

#### ST_DONE — Befejezés
- CS# deassert (mindkettő high)
- `cpu_ready=1` (1-ciklusos pulzus)
- `cpu_rdata = r_shift_in` (olvasás esetén)
- `qspi_clk` gated
- Következő main CLK rising edge → ST_IDLE

### QSPI órajel generálás

- Toggle flip-flop: `r_clk_phase` invertálódik minden main CLK rising edge-en, ha a tranzakció aktív
- `qspi_clk = r_clk_phase & clk_en` — gated, IDLE-ban 0
- Adat setup: a controller a **falling edge-en** (r_clk_phase 1→0) állítja be a DQ kimeneteket
- Adat mintavétel: a **rising edge-en** (r_clk_phase 0→1) történik az olvasás
- A `r_bit_cnt` a QSPI CLK falling edge-en dekrementálódik

### Ciklusszám (main CLK @ 50 MHz, QSPI CLK @ 25 MHz)

| Művelet | Parancs | CMD | ADDR | DUMMY | DATA | DONE | Össz QSPI CLK | Össz main CLK |
|---------|---------|-----|------|-------|------|------|----------------|----------------|
| Flash Read | 0x6B | 8 | 6 | 8 | 8 | 1 | 31 | 62 |
| PSRAM Read | 0xEB | 8 | 6 | 6 | 8 | 1 | 29 | 58 |
| PSRAM Write | 0x38 | 8 | 6 | 0 | 8 | 1 | 23 | 46 |

**Megjegyzés:** A 0x6B parancsnál az ADDR fázis is SPI módban (1-bit) megy, nem quad-ban. Ez 24 QSPI CLK az ADDR fázisban. A teljes Flash Read: 8+24+8+8+1 = 49 QSPI CLK = 98 main CLK. Alternatíva: 0xEB (quad ADDR), ami 8+6+6+8+1 = 29. **Döntés:** Az F2.4 a **0x6B**-t implementálja (egyszerűbb, szélesebb chip kompatibilitás). A 0xEB opció a jövőbeli optimalizáció.

**Javított ciklusszám (0x6B, SPI ADDR):**

| Művelet | Parancs | CMD (SPI) | ADDR (SPI) | DUMMY | DATA (Quad) | DONE | Össz QSPI CLK | Össz main CLK |
|---------|---------|-----------|------------|-------|-------------|------|----------------|----------------|
| Flash Read | 0x6B | 8 | 24 | 8 | 8 | 1 | 49 | 98 |
| PSRAM Read | 0xEB | 8 | 6 | 6 | 8 | 1 | 29 | 58 |
| PSRAM Write | 0x38 | 8 | 6 | 0 | 8 | 1 | 23 | 46 |

### Reset viselkedés

- `rst_n=0` → `r_state=ST_IDLE`, minden regiszter törölve
- `cpu_ready=0`, `cpu_busy=0`
- `qspi_cs_flash_n=1`, `qspi_cs_psram_n=1`
- `qspi_clk=0`, `qspi_dq_oe=0`, `qspi_dq_out=4'hF`
- Reset alatt érkező `cpu_re`/`cpu_we` ignorálva

**HW interlock követelmény:** A reset assertálását csak `cpu_busy=0` állapotban szabad kezdeményezni. Tranzakció közepén érkező reset esetén a külső QSPI eszköz (PSRAM) félig megírt szót láthat — ezt a CPU-oldali bus arbiter-nek kell garantálnia.

### `cpu_busy` alatti `cpu_re`/`cpu_we`

- Bármely kérés `cpu_busy=1` alatt **csendben ignorálva**
- A CPU-oldali felsőbb logika (microcode, bus arbiter) felelős nem indítani új tranzakciót busy alatt

## QSPI parancs kódok (`cilcpu_defines.vh`)

```verilog
`define QSPI_CMD_FLASH_READ    8'h6B   // Quad Output Read (cmd+addr SPI, data Quad)
`define QSPI_CMD_PSRAM_READ    8'hEB   // Fast Read Quad I/O (cmd SPI, addr+data Quad)
`define QSPI_CMD_PSRAM_WRITE   8'h38   // Quad Write (cmd SPI, addr+data Quad)
`define QSPI_DUMMY_FLASH       6'd8    // 0x6B: 8 dummy QSPI ciklus
`define QSPI_DUMMY_PSRAM       6'd6    // 0xEB: 6 dummy QSPI ciklus
`define SEG_CODE               4'h0    // CODE szegmens azonosító
`define SEG_DATA               4'h1    // DATA szegmens azonosító
`define SEG_STACK              4'h2    // STACK szegmens azonosító
```

## Tesztstratégia (TDD)

### QSPI Slave Behavioral Model

Python cocotb koroutin, ami QSPI slave eszközt szimulál:
- **QSPIFlashModel**: dict-alapú memória, read-only, 0x6B parancsot ismeri
- **QSPIPSRAMModel**: dict-alapú memória, read-write, 0xEB és 0x38 parancsokat ismeri
- A modell figyeli CS#, CLK rising edge-eket, DQ bemeneteket
- Olvasáskor a DUMMY fázis után a modell hajtja a `qspi_dq_in` vonalat

### Tesztlista (25 teszt)

**Alap (1–2):**
1. **Reset állapot** — `cpu_busy=0`, `qspi_cs_flash_n=1`, `qspi_cs_psram_n=1`, `qspi_clk=0`, `qspi_dq_oe=0`
2. **IDLE-ban nincs QSPI CLK** — 100 main CLK várakozás, `qspi_clk` mindig 0

**Olvasás (3–4):**
3. **Flash olvasás** — CODE szegmens cím, helyes 32-bit adat a Flash model-ből
4. **PSRAM olvasás** — STACK szegmens cím, helyes 32-bit adat a PSRAM model-ből

**Írás (5–6):**
5. **PSRAM írás** — 0xDEADBEEF írás STACK címre, PSRAM model fogadja
6. **PSRAM írás→olvasás round-trip** — írás majd olvasás, azonos adat

**Cím dekódolás (7–10):**
7. **CODE→Flash CS#** — `qspi_cs_flash_n=0` assert, `qspi_cs_psram_n=1`
8. **DATA→Flash CS#** — `cpu_addr[23:20]=1`, Flash CS# assert
9. **STACK→PSRAM CS#** — `qspi_cs_psram_n=0` assert, `qspi_cs_flash_n=1`
10. **Flash-be írás elutasítva** — `cpu_we=1` CODE címre → `cpu_ready=1` azonnal, nincs QSPI tranzakció

**Protokoll (11–16):**
11. **CMD fázis időzítés** — 8 QSPI CLK, DQ[0] MSB-first, helyes parancs byte bitek
12. **ADDR fázis** — helyes cím nibble-ök/bitek, MSB-first, helyes QSPI CLK szám
13. **Flash dummy ciklus szám** — 8 QSPI CLK dummy a 0x6B után
14. **PSRAM dummy ciklus szám** — 6 QSPI CLK dummy a 0xEB után
15. **Olvasás DATA fázis** — 8 QSPI CLK, 4-bit nibble-ök, MSB-first, helyes shift-in
16. **Írás DATA fázis** — 8 QSPI CLK, helyes nibble sorrend DQ[3:0]-n

**Időzítés (17–18):**
17. **cpu_ready pulzus** — pontosan 1 main CLK ciklusos pulzus a tranzakció végén
18. **cpu_busy tranzakció alatt** — `cpu_busy=1` a teljes QSPI tranzakció alatt, `cpu_busy=0` IDLE-ban

**Él-esetek (19–24):**
19. **Back-to-back olvasások** — két egymás utáni Flash olvasás, mindkettő helyes adat
20. **CS# deassert tranzakciók között** — CS# high legalább 1 main CLK a tranzakciók között
21. **Cím 0x000000 olvasás** — nulla cím, helyes adat
22. **Szegmensenként max cím** — CODE max (0x0FFFFF), STACK max (0x23FFF)
23. **Egyidejű cpu_re + cpu_we** — olvasás prioritás, írás ignorálva
24. **dq_oe fázisátmenetek** — CMD: oe=1, ADDR: oe=1, DUMMY: oe=0, DATA_RD: oe=0, DATA_WR: oe=1

**Stressz (25):**
25. **200 random R/W** — seeded RNG, Python referencia dict vs. PSRAM model, minden adat egyezik

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-28 | Első verzió — QSPI Flash + PSRAM controller, 0x6B/0xEB/0x38, 25 teszt-pont |
| 1.1 | 2026-04-30 | HW interlock kikötés reset alatti tranzakcióhoz; CS# deassert szigorítva ST_DONE-ban |
