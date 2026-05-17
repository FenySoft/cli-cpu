# CLI-CPU FPGA integráció (F2.7 — A7-Lite XC7A200T)

> English version: [README.md](README.md)

> Verzió: 0.5.1 (Sub5.A)

Ez a könyvtár tartalmazza a CLI-CPU Nano core FPGA integrációját a
**MicroPhase A7-Lite XC7A200T** referencia board-ra. A cél az F3 (Tiny Tapeout
silicon) **előtt** validálni a magot valódi hardveren.

## Sub-iterációk

| Sub | Hatókör | Státusz |
|-----|---------|---------|
| Sub1 | Top-level wrapper + cocotb integrációs teszt | ✅ KÉSZ |
| Sub2 | UART TX + 32-bit decimális printer | ✅ KÉSZ |
| Sub3 | Fibonacci demó program + paraméterezhető boot | ✅ KÉSZ |
| Sub4 | QSPI flash bekötés (IS25L128F + STARTUPE2 + IOBUF) | ✅ KÉSZ |
| Sub5 | Vivado + OpenXC7 build + write_cfgmem + XDC timing + bring-up runbook | 🔧 Build-infra kész (HW bring-up a felhasználóra vár) |

## Sub1 — Top-level wrapper

**Fájlok:**

| Fájl | Szerep |
|------|--------|
| [`cilcpu_a7lite_top.v`](cilcpu_a7lite_top.v) | Top-level wrapper a `cilcpu_core` köré |
| [`cilcpu_a7lite.xdc`](cilcpu_a7lite.xdc) | Vivado XDC pin assignment (clock + KEY-ek + LED-ek) |

**A wrapper építőelemei:**

1. **Reset szinkronizer** — async assert / sync deassert, 3-stage. KEY1 (AA1)
   gomb hajtja, active low.
2. **Start gomb (KEY2, W1)** — 2-stage CDC szinkronizer + paraméterezhető
   debouncer (`DEBOUNCE_BITS`, default 22 = ~84 ms @ 50 MHz, sim-ben 4-re
   csökkentett) + falling-edge detektor.
3. **Boot szekvenszer FSM** — 6 állapot: IDLE → INIT → ARG_WAIT → ARG_DRV
   → RUN → DONE. KEY2 lenyomásra elindítja a core-t, push-olja az
   argumentumokat (`o_boot_arg_ready` handshake), majd RUN-ban figyel a
   `o_halt` / `o_trap` jelekre.
4. **Halt / trap latch** — a `r_halted` és `r_trapped` regiszterek tartottak
   a következő reset-ig, így a LED-ek látható kimenetet adnak.
5. **LED kimenet** — `o_led1_n` (M18) = halt indikátor, `o_led2_n` (N18) =
   trap indikátor. Active low (anód VCC, katód a pin-en).
6. **Core példányosítás** — `cilcpu_core` minden portja a wrapper jelekhez
   kötve. A QSPI portok pass-through-ként a top-szintre adódnak ki (Sub4-ben
   véglegesítve a board IS25L128F flash-re).

**Sub1 paraméterek:**

```verilog
parameter [23:0] BOOT_PC          = 24'h000008;  // header után 8 byte
parameter [7:0]  BOOT_ARG_COUNT   = 8'd1;
parameter [7:0]  BOOT_LOCAL_COUNT = 8'd0;
parameter [31:0] BOOT_ARG_VALUE   = 32'd5;
parameter integer DEBOUNCE_BITS   = 22;          // sim: 4
```

**cocotb tesztek (`rtl/tb/test_a7lite_top.py`):**

| Teszt | Hatókör |
|-------|---------|
| `test_01_reset_state` | Reset után LED-ek inaktívak |
| `test_02_idle_no_start` | Start gomb nélkül a core nem indul |
| `test_03_ldarg_ret_smoke` | KEY2 → push 5 → LDARG_0 + RET → return = 5, halt LED |
| `test_04_ldarg_add_smoke` | KEY2 → push 5 → LDARG_0 + LDC.I4_3 + ADD + RET → 8 |
| `test_05_invalid_opcode_trap` | 0xFF opkód → trap, trap LED |
| `test_06_short_press_ignored` | Túl rövid impulzus debouncer-rel kiszűrve |

**Futtatás:**

```bash
cd rtl/tb
make test_a7lite_top
```

**Eredmény:** TESTS=6 PASS=6 FAIL=0 (~40 µs sim time @ 50 MHz, ~0.05s wall).

## Mit nem fed le a Sub1

- A core funkcionalitása (LDC, ALU, branch, CALL, RET, trap aggregátor) **már
  teljes mértékben fedett** a `test_core.py` 48 cocotb tesztjében (F2.5a/b),
  ezért a wrapper teszt csak smoke-szintű. A meglévő test_core regresszió
  Sub1 után is **48/48 zöld**.
- Nincs UART → halt / trap eredménye csak a LED-eken és (Vivado-ban) ILA
  probe-on át látható. Sub2 hozza az UART TX-et.
- A QSPI portok a wrapper top-szintjére adódnak ki, de az XDC-ben még nincs
  bekötve (Sub4).

## Közös cocotb modulok

A Sub1 bevezet két új közös modult, hogy a wrapper teszt és a jövőbeli
top-level tesztek ne duplikáljanak:

- [`rtl/tb/tb_qspi.py`](../tb/tb_qspi.py) — `TQSPIFlashModel` + `qspi_flash_driver`
- [`rtl/tb/tb_isa.py`](../tb/tb_isa.py) — opkód / trap konstansok + `make_method` header builder

A meglévő `test_core.py` változatlan (self-contained marad, mert már stabil).

## Sub2 — UART TX + decimális printer

**Új fájlok:**

| Fájl | Szerep |
|------|--------|
| [`uart_tx.v`](uart_tx.v) | 8N1 UART transmitter, paraméterezhető `CLOCKS_PER_BAUD` |
| [`decimal_printer.v`](decimal_printer.v) | 32-bit signed/unsigned int → ASCII decimal → UART, `\r\n` terminátorral |

**Wrapper bővítés:**

- Új top-port: `o_uart_tx` (V2, CH340 USB-UART bridge)
- Új paraméter: `CLOCKS_PER_BAUD` (FPGA: 434 = 50 MHz / 115200; sim: 8)
- Boot FSM kibővítve: `S_PRINT_REQ` → `S_PRINT_WAIT` → `S_DONE`. Halt esetén
  a wrapper signed-ként, trap esetén unsigned-ként adja át az értéket a
  printer-nek.
- Belső `decimal_printer` példányosítva, ami egy `uart_tx` példányt
  vezérel.

**XDC bővítés:** `o_uart_tx` → V2 (LVCMOS33, DRIVE 8).

**cocotb tesztek:**

| Teszt | Hatókör | Eredmény |
|-------|---------|----------|
| `test_uart_tx.py` (8 teszt) | UART TX standalone (idle, byte-minták, busy, back-to-back) | 8/8 PASS |
| `test_decimal_printer.py` (10 teszt) | Printer standalone (0, single/multi digit, INT32 MIN/MAX, 6765 = Fibonacci(20), back-to-back) | 10/10 PASS |
| `test_a7lite_top.py` Sub2 új tesztek | `test_07`: halt → UART "5\r\n", `test_08`: trap → UART "3\r\n" | 2/2 PASS |

**Új közös cocotb modul:** [`tb_uart.py`](../tb/tb_uart.py) — `uart_rx_byte` és
`uart_rx_string` 8N1 dekódolók a wrapper UART output verifikációjához.

**Futtatás:**

```bash
cd rtl/tb
make test_uart_tx          # 8/8 PASS
make test_decimal_printer  # 10/10 PASS
make test_a7lite_top       # 8/8 PASS (6 Sub1 + 2 Sub2)
```

**Szintézis-előzetes:** A printer-ben a `r_abs / 32'd10` (32-bit / 10) Yosys
és Vivado is szintetizálja — a tényleges LUT/DSP területet a Sub5 build
mutatja. Sim-ben combinational ágként elfogadott, ~3 ciklus/digit,
8 jegyhez ~24 ciklus.

## Sub3 — Fibonacci(20) end-to-end demó

**Cél:** A teljes toolchain (C# → Roslyn → CIL-T0 linker → core → wrapper →
UART) verifikálása valós CIL-T0 binárissal a wrapper-en.

**Új C# metódus** (`samples/PureMath/Math.cs`):
```csharp
public static int FibonacciIterative(int n)
{
    if (n < 2) return n;
    int a = 0;
    int b = 1;
    for (int i = 2; i <= n; i++)
    {
        int c = a + b;
        a = b;
        b = c;
    }
    return b;
}
```

A linker 40 byte-os `.t0` binárist generál (8 byte header + 32 byte body),
ami `LDLOC/STLOC`, `ADD/SUB`, `BLT_S/BR_S` opkódokat használ — mind
100%-ban fedett a `cilcpu_core` Sub3/Sub4 implementációjában.

**Wrapper paraméter változás:** A `BOOT_PC`, `BOOT_ARG_COUNT`,
`BOOT_LOCAL_COUNT`, `BOOT_ARG_VALUE` paraméterek immár `parameter integer`
típusúak (32-bit), hogy a Verilator `-G<name>=<value>` command-line override
ne dobjon WIDTHTRUNC hibát. A wrapper-en belül slice-eljük a megfelelő
méretűre. Így a sim build paraméterezhető:

```bash
make test_a7lite_fib  # -GBOOT_ARG_VALUE=20 -GBOOT_LOCAL_COUNT=4
```

**Új cocotb teszt** (`test_a7lite_fib.py`):
- Build-time hívja a `dotnet $RUNNER_DLL link ... --method FibonacciIterative`-et
- A `.t0` byte-okat a flash slave-be tölti
- KEY2 lenyomás → wrapper boot N=20-szal → core fut → halt → UART
- Várakozott eredmény: `"6765\r\n"` (= Fib(20))
- **Eredmény: 1/1 PASS** (~1.13ms sim time, ~1.35s wall time)

**Megjegyzés:** Az `iteratív FibonacciIterative` a Sub3 elfogadott
demója — a loop-opkód-fedezetet (`LDLOC/STLOC`, `ADD/SUB`, `BLT_S/BR_S`)
gyakorolja az end-to-end toolchain-en.

**Rekurzív Math.Fibonacci — MEGOLDVA (F2.7.D, commit `762536b`):** A
Roslyn-linkelt **rekurzív** `Math.Fibonacci` (CALL self) a wrapper
boot-mintával (caller frame nélkül, `boot_pc=8` közvetlenül a Fib
body-tól) korábban `TRAP_STACK_UNDERFLOW`-val trap-elt ~5 mélységnél.
Gyökér-ok: a `RET_FINALIZE` a caller Stack Cache-t az eval bázisra
állította, eldobva a hívás alatt megőrzendő eval-elemeket. 3-modulos
gyökér-fix (`cilcpu_stack_cache.v` flush + sp_depth; `cilcpu_core.v`
ST_CALL/ST_RET frame-eval megőrzés). A rekurzív Roslyn Fibonacci a
wrapper boot-mintával is zöld: `test_52c_recursive_fib10_roslyn_boot_no_caller`
(Fib(10)=55). Vault: `project_recursive_call_bug` (MEGOLDVA).

**Futtatás:**

```bash
# Előfeltétel:
dotnet build CLI-CPU.sln -c Debug

cd rtl/tb
make test_a7lite_fib  # 1/1 PASS — UART "6765\r\n"
```

## Sub4 — QSPI flash bekötés (IS25L128F)

**Cél:** A `cilcpu_a7lite_top` köré rakott board-szintű wrapper, amely a
Xilinx 7-széria **STARTUPE2** primitívvel hajtja a CCLK pinjét (a CCLK
fizikai pin a dedikált config bankban van, user módban közvetlenül nem
köthető GPIO-ra), és négy **IOBUF** primitív kezeli a DQ[3:0] inout buszt.
Az IS25L128F (128 Mbit) QSPI flash a board konfigurációs flash-e — a
bitstream után user módban innen olvassa a CIL-T0 programot is a core.

**Új fájlok:**

| Fájl | Szerep |
|------|--------|
| [`cilcpu_a7lite_board.v`](cilcpu_a7lite_board.v) | Board-szintű (FPGA) top wrapper. `cilcpu_a7lite_top` + STARTUPE2 + 4 IOBUF |
| [`sim_stubs/xilinx_primitives_sim.v`](sim_stubs/xilinx_primitives_sim.v) | Behavioral STARTUPE2 + IOBUF stub Verilator-hoz (Xilinx 'unisims' helyett sim-ben) |

**Architektúra döntés:**

A board.v két módban viselkedik a `+define+CILCPU_SIM_BOARD` makró
alapján:

- **FPGA build** (Vivado/OpenXC7, makró undef): port-interfész
  `output o_qspi_cs_n` + `inout wire [3:0] io_qspi_dq`, a négy IOBUF
  szétválasztja a master-hajtott / flash-hajtott fázisokat.
- **Sim build** (Verilator + cocotb, `+define+CILCPU_SIM_BOARD`):
  IOBUF-ok kihagyva (Verilator multi-driver konfliktust dobna az
  `assign IO = T ? 'bz : I`-re egy külső driver-rel egyszerre), helyettük
  split debug portok (`o_qspi_dq_out_dbg`, `i_qspi_dq_in_dbg`,
  `o_qspi_dq_oe_dbg`, `o_qspi_clk_dbg`) közvetlenül a belső net-ekre.

A STARTUPE2 mindkét módban példányosítva: FPGA-n a Xilinx 'unisims'
valódi primitív, sim-ben a `sim_stubs/xilinx_primitives_sim.v` behavioral
modellje (USRCCLKO transzparens — a board.v belső `w_qspi_clk_user`
net-jén át megfigyelhető a flash slave-hez).

**XDC frissítés** (`cilcpu_a7lite.xdc`):

- Top module váltás: `cilcpu_a7lite_top` → `cilcpu_a7lite_board`
- `o_qspi_cs_n` (T19), `io_qspi_dq[0..3]` (P22, R22, P21, R21) pin assignment
- CCLK NEM kerül `set_property PACKAGE_PIN`-be — a STARTUPE2 hajtja
- `create_generated_clock` a STARTUPE2 USRCCLKO útvonalra: `qspi_sck` =
  sys_clk / 2 = 25 MHz
- `set_input_delay` / `set_output_delay` az IS25L128F datasheet alapján
  (tV max 7 ns, tIS / tIH 2 ns; finomítás Sub5-ben)

**cocotb tesztek:**

| Teszt | Hatókör | Eredmény |
|-------|---------|----------|
| [`test_a7lite_board.py`](../tb/test_a7lite_board.py) | Reset + LDARG/RET + LDARG+ADD + INVALID_OPCODE trap, UART "5\r\n" / "3\r\n" | 4/4 PASS |
| [`test_a7lite_board_fib.py`](../tb/test_a7lite_board_fib.py) | FibonacciIterative(20) = 6765 a board.v-n keresztül | 1/1 PASS |

Mindkét teszt a STARTUPE2 + (sim módban null) IOBUF útvonalon viszi
keresztül a flash slave-flash master kommunikációt — bizonyítja, hogy a
board.v új réteg nem regresszió a Sub3 demóhoz képest.

**Futtatás:**

```bash
cd rtl/tb
make test_a7lite_board       # 4/4 PASS
make test_a7lite_board_fib   # 1/1 PASS — UART "6765\r\n" a board.v-n át
```

**Sub5-be halasztott munka:**

- Vivado / OpenXC7 build a board.v-vel + IS25L128F-ra ténylegesen
- Bitstream `write_cfgmem` flow (alkalmazás bináris a config flash-en
  beágyazva, vagy külön JEDEC/MCS sectorban)
- 50 MHz timing zárás (a `qspi_sck` constraint pontosítása mérés alapján)
- Tényleges A7-Lite hardver bring-up — UART terminal a CH340 felett

## Sub5 — Vivado + OpenXC7 build + bring-up

> **Fontos — a hatókör határa:** A szintézis, a PnR, a `write_bitstream`,
> a `write_cfgmem`, a 50 MHz timing-zárás és a fizikai bring-up **a
> felhasználó WSL-gépén és A7-Lite hardverén** fut — ezen a session-ön
> NEM futtatható (nincs `vivado`/`yosys`/`nextpnr-xilinx`, nincs HW).
> A Sub5 acceptance ezért: **build-infrastruktúra + bring-up runbook
> kész**; a tényleges HW-verifikáció (timing WNS ≥ 0, UART "6765\r\n")
> a felhasználóra vár.

**Cél:** A Sub4 board.v-t valódi bitstream-mé fordítani mindkét
toolchain-en, a CIL-T0 alkalmazás-binárist a config flash-be ágyazni, és
a Sub3/Sub4 sim-ben bizonyított "6765\r\n" mintát hardveren reprodukálni.

**Új fájlok:**

| Fájl | Szerep |
|------|--------|
| [`Vivado/create_project.tcl`](Vivado/create_project.tcl) | Teljes `cilcpu_a7lite_board` projekt: szintézis → impl → write_bitstream + timing report. Part `xc7a200tfbg484-2` |
| [`Vivado/write_cfgmem.tcl`](Vivado/write_cfgmem.tcl) | `.bit` + CIL-T0 `.t0` → egyetlen `.mcs` (SPIx4, 16 MB IS25L128F) |
| [`OpenXC7/Makefile`](OpenXC7/Makefile) | Yosys → nextpnr-xilinx → fasm2frames → xc7frames2bit, teljes forrásfa |
| [`OpenXC7/build.sh`](OpenXC7/build.sh) | WSL launcher (PATH, S: mount, `make`) |
| [`OpenXC7/cilcpu_a7lite.xdc`](OpenXC7/cilcpu_a7lite.xdc) | OpenXC7-formátumú constraint (nincs `-dict`) |
| [`scripts/build_app_bin.sh`](scripts/build_app_bin.sh) | `dotnet build` → linker → `.t0` (paraméterezhető metódus/N) |

**Forrásfa-paritás:** Mindkét build a `rtl/tb/Makefile`
`test_a7lite_board_fib` `VERILOG_SOURCES` listájával **azonos** RTL
forrásfát szintetizál, a `sim_stubs/` **nélkül** — FPGA-n a STARTUPE2 +
IOBUF a Vivado 'unisims' / Yosys `synth_xilinx` beépített cellái. A
`cilcpu_defines.vh` include path-ként van hozzáadva.

**Flash-offszet paritás (sim ↔ cfgmem) — Sub5.A-ban MEGOLDVA:**

A `cilcpu_qspi_controller` a CODE szegmenst (`cpu_addr[23:20]=0x0`) a
flash `CODE_BASE_OFFSET + {4'h0, cpu_addr[19:0]}` címére fordítja. A
`CODE_BASE_OFFSET` paraméterezhető generic (Sub5.A), végighúzva a
teljes példányosítási láncon (`cilcpu_qspi_controller` ←
`cilcpu_core` ← `cilcpu_a7lite_top` ← `cilcpu_a7lite_board`):

- **SIM:** default `0` → a cocotb `TQSPIFlashModel` a `.t0[i]`-t az
  `i` flash-címre teszi → **bit-azonos sim-paritás**, minden meglévő
  teszt változatlanul zöld (`BOOT_PC=0x08`).
- **FPGA:** a Vivado `create_project.tcl`
  `set_property generic CODE_BASE_OFFSET=32'hC00000` (12 MB), az
  OpenXC7 `Makefile` `chparam -set CODE_BASE_OFFSET 12582912`, a
  `write_cfgmem.tcl` pedig a `.t0`-t PONTOSAN `0x00C00000`-ra ágyazza.
  A config-flash a `.bit`-et 0x0-tól tölti (SPIx4 master config), az
  app a **~9,9 MB XC7A200T bitstream FÖLÉ** kerül → **nincs ütközés**
  az IS25L128F-en (16 MB; app-ablak 1 MB: `0xC00000..0xCFFFFF`).

> **EGYETLEN FORRÁS:** a `CODE_BASE_OFFSET` generic, a
> `write_cfgmem.tcl` `CODE_BASE_OFFSET_HEX` és az OpenXC7
> `CODE_BASE_OFFSET` MINDIG egyezzen (mindhárom = 12 MB). A
> `write_cfgmem.tcl` 2. argumentuma csak akkor írja felül, ha a
> generic-et is ugyanarra állítod. Forrás:
> `rtl/src/cilcpu_qspi_controller.v` ST_IDLE `SEG_CODE` ág
> (`CODE_BASE_OFFSET`) + `rtl/tb/test_qspi_controller.py` test_30/31.
>
> Megjegyzés: a `SEG_DATA` (flash `{4'h1, cpu_addr[19:0]}` = 0x100000)
> **szándékosan NEM kapott offszetet** — a jelenlegi int-only CIL-T0
> programok (PureMath) nem használnak statikus DATA flash-régiót, a
> sim-paritás (test_08) erre az offszetlen mappingre épül, és külön
> teszt/use-case nélkül offszetelni over-engineering lenne. Ha a DATA
> flash-backed lesz, külön taszk + teszt szükséges (lásd `todo.md`).

**XDC timing finomítás (`cilcpu_a7lite.xdc`):**

- `create_clock -period 20.000` az `i_clk_50m` (J19) pinre — explicit 50
  MHz fő constraint (változatlan, Sub1 óta megvan).
- `qspi_sck` `create_generated_clock` = sys_clk / 2 = 25 MHz (változatlan).
- `set_input_delay` / `set_output_delay` pontosítva az IS25L128F (ISSI)
  datasheet 0x6B Quad Output Read értékeivel: tCLQV max 7.0 ns, tCLQX
  min 1.5 ns, tDVCH/tCHDX min 2.0 ns, CS# tSLCH/tCHSH min 5.0 ns,
  becsült FBG484+PCB trace skew ~0.5 ns. Az input-ablak a skew-val
  tágítva (−min 1.0 / −max 7.5), az output a flash s/h-val (−2.5 / +2.5).

**OpenXC7 STARTUPE2-támogatás (nyíltan kimondott korlát):**

Az `IOBUF` az nextpnr-xilinx/prjxray flow-ban **támogatott** (a DQ[3:0]
busz rendben). A **STARTUPE2** (config-bank startup blokk, a user CCLK a
`USRCCLKO`-n keresztül) az nextpnr-xilinx + prjxray-db artix7 flow-ban
**NEM megbízhatóan támogatott** — a STARTUP site fuzzing hiányos a
prjxray-db-ben. Ezért az **OpenXC7 path Sub5-ben best-effort; az
elsődleges Sub5 path a Vivado.** Ezt a single-layer-trust /
no-compromise elv szerint **kimondjuk, nem kerüljük meg**: ha a
nextpnr-xilinx a STARTUPE2-n elbukik, az a dokumentált OpenXC7-korlát,
nem RTL/XDC-hiba. (Megjegyzés: a smoke-teszt LED-blink STARTUPE2 nélkül
ment át OpenXC7-en 2026-04-24-én — a STARTUPE2 a board.v új igénye.)

Az app-bináris OpenXC7-path-on: a `xc7frames2bit` után külön flash-image
összefűzés vagy `openFPGALoader` (`--external-flash`, `-o <offszet>`) —
a konkrét lépést a bring-up runbook írja le.

**Futtatás (a felhasználó WSL-gépén):**

```bash
# 1. App-bináris (CIL-T0 .t0) — a sim-mel azonos linker-parancs
rtl/fpga/scripts/build_app_bin.sh           # FibonacciIterative, N=20

# 2a. Vivado (elsődleges path)
cd rtl/fpga/Vivado
vivado -mode batch -source create_project.tcl
vivado -mode batch -source write_cfgmem.tcl -tclargs build/app.t0

# 2b. OpenXC7 (best-effort, lehet STARTUPE2-bukás)
cd rtl/fpga/OpenXC7
bash build.sh check-env
bash build.sh chipdb        # egyszeri, ~5-10 perc
bash build.sh all
```

**Bring-up runbook (a felhasználó A7-Lite hardverén):**

1. **Bitstream JTAG-feltöltés (gyors smoke):** Vivado Hardware Manager →
   Open target → Auto Connect → Program Device → `cilcpu_a7lite_board.bit`.
   (Csak RAM-ba tölt, flash nélkül — gyors funkció-ellenőrzés.)
2. **Config flash programozás:** Hardware Manager →
   Add Configuration Memory Device → `is25lp128f` (IS25L128F kompatibilis,
   128 Mbit) → Program Configuration Memory Device → `build/cilcpu_a7lite.mcs`.
   (Ez tölti a bitstream-et + a `.t0` app-binárist.) OpenXC7-en:
   `openFPGALoader -b <board> --write-flash cilcpu_a7lite.bit`, az
   app-image-et külön offszetre.
3. **UART terminál:** CH340 USB-soros, **115200 baud, 8N1**, no
   flow-control. (Linux: `screen /dev/ttyUSB0 115200`; Windows: PuTTY /
   TeraTerm.)
4. **Power-cycle / KEY1 reset:** az FPGA a flash-ből konfigurálódik,
   majd user módban a core a QSPI flash-ről olvassa a CIL-T0-t.
5. **KEY2 (W1) lenyomás:** a boot FSM elindítja a core-t
   N=`BOOT_ARG_VALUE` (=20) argumentummal.
6. **Várható kimenet:** a UART terminálon **`6765\r\n`** (= Fib(20)),
   a **D6 LED (M18) világít** (halt latch), a D5 (trap) **sötét**.
   Trap esetén a D5 világít, és a UART a trap-kódot decimálisan adja.

**Mit hagy a felhasználóra (explicit):** a tényleges szintézis/PnR
futtatás, a `write_bitstream`/`write_cfgmem` előállítása, a **50 MHz
timing-zárás igazolása** (sys_clk WNS ≥ 0 a `timing_summary.rpt`-ből),
az OpenXC7 STARTUPE2-bukás tényleges megfigyelése, és a hardveres
bring-up (UART "6765\r\n"). A Sub5 acceptance a build-infra + runbook;
a HW-verifikáció ezeken a deliverable-ökön nyitva marad.

## Smoke-teszt (LED blink)

Külön mappa: [`smoke_test/`](smoke_test/) — board bring-up LED blink, két
toolchain-en (Vivado és OpenXC7). 2026-04-24-én verifikálva valódi
hardveren. Nem része az F2.7-nek, de igazolja, hogy a flow áll.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 0.1 | 2026-05-08 | Sub1 — top-level wrapper skeleton + 6 cocotb teszt zöld |
| 0.2 | 2026-05-08 | Sub2 — UART TX + decimális printer (8+10+2 cocotb teszt zöld); halt/trap UART-on |
| 0.3 | 2026-05-10 | Sub3 — FibonacciIterative(20) end-to-end UART "6765\r\n"; rekurzív bug külön taszk |
| 0.4 | 2026-05-14 | Sub4 — board.v wrapper STARTUPE2 + IOBUF; XDC QSPI pinekkel; 4+1 új cocotb teszt zöld |
| 0.4.1 | 2026-05-17 | F2.7.D rekurzív CALL/RET gyökér-fix átvezetve (commit 762536b); a Sub3 „Ismert bug" feloldva, test_52c zöld |
| 0.5 | 2026-05-17 | Sub5 build-infra — Vivado `create_project.tcl` + `write_cfgmem.tcl`, OpenXC7 `Makefile`/`build.sh`/XDC, `scripts/build_app_bin.sh`, XDC timing finomítás (IS25L128F datasheet). Flash-offszet paritás 0x000000 (sim ↔ cfgmem); OpenXC7 STARTUPE2-korlát nyíltan dokumentálva; bring-up runbook. Szintézis/timing/bring-up a felhasználóra vár (nem HW-verifikált) |
| 0.5.1 | 2026-05-17 | Sub5.A — paraméterezhető `CODE_BASE_OFFSET` generic (qspi_controller ← core ← a7lite_top ← board). Flash-ütközés „nyitott kérdés" → MEGOLDVA: sim default 0 (bit-azonos paritás), FPGA 0xC00000 (12 MB, ~9,9 MB bitstream fölé). Egyetlen forrás: generic = write_cfgmem `CODE_BASE_OFFSET_HEX` = OpenXC7 chparam. 2 új cocotb teszt (test_30/31) + 7 regressziós target zöld; SEG_DATA szándékosan offszetlen (indoklás a Sub5 szakaszban) |
