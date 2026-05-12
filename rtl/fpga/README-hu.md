# CLI-CPU FPGA integráció (F2.7 — A7-Lite XC7A200T)

> English version: [README.md](README.md)

> Verzió: 0.1 (Sub1)

Ez a könyvtár tartalmazza a CLI-CPU Nano core FPGA integrációját a
**MicroPhase A7-Lite XC7A200T** referencia board-ra. A cél az F3 (Tiny Tapeout
silicon) **előtt** validálni a magot valódi hardveren.

## Sub-iterációk

| Sub | Hatókör | Státusz |
|-----|---------|---------|
| Sub1 | Top-level wrapper + cocotb integrációs teszt | ✅ KÉSZ |
| Sub2 | UART TX + 32-bit decimális printer | ✅ KÉSZ |
| Sub3 | Fibonacci demó program + paraméterezhető boot | ✅ KÉSZ |
| Sub4 | QSPI flash bekötés (IS25L128F) | ⬜ Tervezett |
| Sub5 | Vivado + OpenXC7 build, timing zárás 50 MHz | ⬜ Tervezett |

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

**Ismert bug — rekurzív Math.Fibonacci:** A Roslyn-linkelt **rekurzív**
`Math.Fibonacci` (CALL self) a wrapper boot-mintával (caller frame nélkül,
`boot_pc=8` közvetlenül a Fib body-tól) `TRAP_STACK_UNDERFLOW`-val trap-el
~5 mélységnél. A hand-coded `test_52_call_recursive_fib_5` (caller frame-mel)
zöld; a `TCpuNano` C# szim is helyes Fib(10)=55-öt ad ugyanezzel a
binárissal. A bug a `cilcpu_core.v` Sub5 frame manager teardown logikájában
van, amikor a "root frame"-et nem CALL hozta létre. **Workaround Sub3-ban:
iteratív verzió** (loop, ugyanaz az eredmény, kevesebb opkód-fedezetet
gyakorol). A javítás külön debug sprintbe kerül — Vault `project_recursive_call_bug`.

**Futtatás:**

```bash
# Előfeltétel:
dotnet build CLI-CPU.sln -c Debug

cd rtl/tb
make test_a7lite_fib  # 1/1 PASS — UART "6765\r\n"
```

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
