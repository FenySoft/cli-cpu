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
| Sub2 | UART TX + 32-bit decimális printer | ⬜ Tervezett |
| Sub3 | Fibonacci(20) demó program + paraméterezhető boot | ⬜ Tervezett |
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

## Smoke-teszt (LED blink)

Külön mappa: [`smoke_test/`](smoke_test/) — board bring-up LED blink, két
toolchain-en (Vivado és OpenXC7). 2026-04-24-én verifikálva valódi
hardveren. Nem része az F2.7-nek, de igazolja, hogy a flow áll.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 0.1 | 2026-05-08 | Sub1 — top-level wrapper skeleton + 6 cocotb teszt zöld |
