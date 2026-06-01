# F2.4 QSPI Controller — Kontrakt és Portspec

> English version: [QSPI_CONTROLLER_SPEC-en.md](QSPI_CONTROLLER_SPEC-en.md)

> Belső munka-spec a TDD ciklushoz. Az architekturális kontextus a `docs/architecture-hu.md`-ben.
>
> **Hatókör:** Belső RTL munka-spec, nem publikus dokumentum.
>
> Version: 1.2

## Cél

A CPU belső SRAM-szerű olvasás/írás kéréseit QSPI protokollra fordítja. Két külső eszközt kezel:
- **QSPI Flash** — CODE és DATA szegmens (read **+ write**, F2 óta: erase+program)
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
| `4'h0` | CODE | Flash | **Igen** (F2) | `0x6B` (Quad Output Read) | `0x06`/`0x20`/`0x02`/`0x05` (erase+program) |
| `4'h1` | DATA | Flash | **Igen** (F2) | `0x6B` (Quad Output Read) | `0x06`/`0x20`/`0x02`/`0x05` (erase+program) |
| `4'h2` | STACK | PSRAM | Igen | `0xEB` (Fast Read QIO) | `0x38` (Quad Write) |
| egyéb | — | — | — | `cpu_ready=1` azonnal, NOP | `cpu_ready=1` azonnal, NOP |

**Flash erase+program (F2):** A NOR flash csak `1→0` programozható, ezért a Page Program ELŐTT a 4 KB-os szektort törölni kell. Egy `cpu_we` a CODE/DATA szegmensre a teljes szekvenciát futtatja: `WREN → Sector Erase (0x20) → WIP-poll → WREN → Page Program (0x02) → WIP-poll`. **Auto-erase szektorváltáskor:** a controller az `r_last_erased_sector` regiszterben tartja az utoljára törölt 4 KB szektort (`flash_addr[23:12]`), és csak akkor töröl, ha a célszektor eltér (vagy reset óta még nem törölt). Így a streaming, szavankénti betöltés egy szektoron belül **egyszer** töröl, és a multi-word program nem korrumpálódik. A flash-cím a CODE szegmensnél a `CODE_BASE_OFFSET` fölé tolva (mint olvasásnál), DATA-nál `{4'h1, addr[19:0]}`.

> **Megjegyzés a flash-írás latenciájáról:** A valós sector erase ~45 ms (≫ egy UART byte ~434 ciklus @ 115200), ezért a host-protokollnak throttle-öznie kell a streaming betöltésnél (buffer-mentes loader). Ezt a SoC-szintű e2e teszt (`test_soc.test_09`) szavankénti throttle-lel modellezi. Lásd Vault: `f2-flash-write-uart-throttle`.

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
- `r_fw_step[2:0]` — flash-write al-szekvenszer lépés (F2): `FW_WREN_E / FW_ERASE / FW_POLL_E / FW_WREN_P / FW_PROGRAM / FW_POLL_P`
- `r_status[7:0]` — RDSR-ből beolvasott status byte (WIP = bit 0)
- `r_last_erased_sector[11:0]` — utoljára törölt 4 KB szektor (`flash_addr[23:12]`)
- `r_have_erased` — 1 = reset óta legalább egy szektor törölve

### FSM állapotok

```
localparam [3:0] ST_IDLE        = 4'd0;   // Vár cpu_re/cpu_we-re
localparam [3:0] ST_CMD         = 4'd1;   // 8-bit parancs küldése (SPI, 1-bit)
localparam [3:0] ST_ADDR        = 4'd2;   // 24-bit cím küldése (Quad, 4-bit)
localparam [3:0] ST_DUMMY       = 4'd3;   // Dummy ciklusok (DQ Hi-Z)
localparam [3:0] ST_DATA_RD     = 4'd4;   // 32-bit adat olvasás (Quad, 4-bit)
localparam [3:0] ST_DATA_WR     = 4'd5;   // 32-bit adat írás PSRAM-ba (Quad, 4-bit)
localparam [3:0] ST_DONE        = 4'd6;   // cpu_ready=1, CS# deassert, → IDLE
localparam [3:0] ST_INIT_CS_HI  = 4'd7;   // F2.7 Sub5 QE-init CS# spacing
localparam [3:0] ST_INIT_DATA_SPI = 4'd8; // F2.7 Sub5 QE-init WRSR data (SPI)
// F2 — flash erase+program (SPI mód, 1-1-1):
localparam [3:0] ST_FW_CMD      = 4'd9;   // 8-bit CMD küldés (WREN/ERASE/PROGRAM/RDSR)
localparam [3:0] ST_FW_ADDR     = 4'd10;  // 24-bit cím küldés (erase/program)
localparam [3:0] ST_FW_DATA     = 4'd11;  // 32-bit adat küldés (program)
localparam [3:0] ST_FW_RDSR_RD  = 4'd12;  // 8-bit status olvasás MISO-n (DQ[1])
localparam [3:0] ST_FW_CS_HI    = 4'd13;  // CS# spacing + al-szekvenszer léptetés
```

**Flash-write al-szekvenszer (F2):** A CODE/DATA szegmensre érkező `cpu_we` az `r_fw_step` által vezérelt, CS#-szel elválasztott SPI tranzakció-láncot futtat. Szektorváltáskor (vagy reset óta első írás): `FW_WREN_E → FW_ERASE → FW_POLL_E → FW_WREN_P → FW_PROGRAM → FW_POLL_P → ST_DONE`. Azonos szektoron belül az erase kimarad: `FW_WREN_P → FW_PROGRAM → FW_POLL_P → ST_DONE`. A `FW_POLL_*` lépések RDSR-t olvasnak, amíg a WIP (status bit 0) nem 0.

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
`define QSPI_CMD_FLASH_WREN    8'h06   // F2: Write Enable (WEL latch)
`define QSPI_CMD_FLASH_RDSR    8'h05   // F2: Read Status Register (WIP = bit 0)
`define QSPI_CMD_FLASH_ERASE   8'h20   // F2: Sector Erase (4 KB)
`define QSPI_CMD_FLASH_PROGRAM 8'h02   // F2: Page Program
`define QSPI_DUMMY_FLASH       6'd8    // 0x6B: 8 dummy QSPI ciklus
`define QSPI_DUMMY_PSRAM       6'd6    // 0xEB: 6 dummy QSPI ciklus
`define QSPI_FLASH_SECTOR_HI   23      // F2: szektor = flash_addr[23:12]
`define QSPI_FLASH_SECTOR_LO   12
`define SEG_CODE               4'h0    // CODE szegmens azonosító
`define SEG_DATA               4'h1    // DATA szegmens azonosító
`define SEG_STACK              4'h2    // STACK szegmens azonosító
```

## Tesztstratégia (TDD)

### QSPI Slave Behavioral Model

Python cocotb koroutin, ami QSPI slave eszközt szimulál:
- **TQSPIFlashModel**: dict-alapú memória, read (0x6B) **+ write (F2)**: WREN (WEL latch), Sector Erase (0x20, szektor → 0xFF), Page Program (0x02, NOR `1→0` AND), RDSR (0x05, WIP busy számláló). `erase_count`/`program_count` teszt-introspekció.
- **TQSPIPSRAMModel**: dict-alapú memória, read-write, 0xEB és 0x38 parancsokat ismeri
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
10. **Flash-be írás VÉGREHAJTÓDIK (F2)** — `cpu_we=1` CODE címre → Flash CS# assert, erase+program, PSRAM CS# inaktív, beírt szó visszaolvasható (a korábbi „elutasítva" viselkedés megszűnt)

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

**Audit-javítások (26–29):** CMD DQ[3:1]=0b111, IDLE dq_out=0xF, érvénytelen szegmens NOP, busy alatt új kérés ignorálva.

**Sub5.A — CODE_BASE_OFFSET (30–31):** offszet alkalmazva / offset @ addr 0 (skip default 0-nál).

**F2 — flash erase+program (32–35):**
32. **Flash írás→olvasás round-trip** — WREN→erase→program→WIP-poll, majd 0x6B olvasás visszaadja a szót; `erase_count>=1`, `program_count==1`
33. **Multi-word egy szektorban → 1 erase** — 4 egymás utáni szó egy szektorban, pontosan 1 sector erase (auto-erase szektorváltáskor), mind a 4 helyesen visszaolvasható
34. **WIP-poll** — a controller program után RDSR-rel WIP=0-ig pollozik (`wip_remaining==0` a végén); program tényleg lefutott
35. **Erase törli a régi adatot** — előre 0x00-ra töltött szektor, program 0xFFFFFFFF; erase nélkül a NOR `1→0` AND 0x00000000-t adna → a 0xFFFFFFFF bizonyítja az erase-t

> **SoC-szintű e2e (`test_soc.test_09`):** UART WRITE (dev=0) → flash erase+program → BOOT (code_src=0) → core flash-fetch → futás. Throttle-öző host (a flash-latencia ≫ UART byte miatt).

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-28 | Első verzió — QSPI Flash + PSRAM controller, 0x6B/0xEB/0x38, 25 teszt-pont |
| 1.1 | 2026-04-30 | HW interlock kikötés reset alatti tranzakcióhoz; CS# deassert szigorítva ST_DONE-ban |
| 1.2 | 2026-06-01 | **F2 — flash erase+program**: a Flash CODE/DATA szegmens írhatóvá vált (WREN→Sector Erase→WIP-poll→WREN→Page Program→WIP-poll, SPI 1-1-1). Auto-erase szektorváltáskor (`r_last_erased_sector`/`r_have_erased`) → buffer-mentes streaming betöltés egy szektorban 1 erase. 5 új FSM állapot (`ST_FW_*`), al-szekvenszer (`r_fw_step`). Parancskódok: 0x06/0x05/0x20/0x02. 4 új controller teszt (32–35) + SoC e2e (test_09). `test_10` viselkedésváltás (flash-írás végrehajtódik). |
