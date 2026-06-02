# F2.5a Top-level Nano Core — Kontrakt és Portspec

> English version: [CORE_SPEC-en.md](CORE_SPEC-en.md)

> Belső munka-spec a TDD ciklushoz. Aranypélda: `TCpuNano` (`src/CilCpu.Sim/TCpuNano.cs`).
>
> **Hatókör:** Belső RTL munka-spec, nem publikus dokumentum. A publikus ISA spec a `docs/ISA-CIL-T0-{hu,en}.md`, a publikus architektúra a `docs/architecture-hu.md`.
>
> Version: 1.6

### Changelog
- **1.6 (F3 — egységes on-chip SRAM):** A core a TELJES programot a saját 4 KB
  on-chip SRAM-jából futtatja (CODE+DATA+STACK egy lineáris térben). Az alábbi
  F2.5a memória/fetch/boot leírást ez **felülírja** — lásd a „F3 egységes
  on-chip SRAM" szekciót. ADR: `Vault/Decisions/2026-06-01-unified-onchip-sram`.
- 1.5 és korábbi: F2.4–F2.8 (16 KB SRAM stack-only, CODE-fetch a QSPI flash-ből).

### F3 — egységes on-chip SRAM (felülírja az F2.5a memória-modellt)
- **4 KB egységes on-chip SRAM** `reg [31:0] r_sram[0:1023]` — CODE + DATA + STACK
  egy lineáris címtérben (scratchpad/TCM). Szintézisben SRAM-makró (IHP 1P 1024×32).
  Térkép: CODE+DATA `[0, STACK_BASE)`=`[0,2048)`, STACK `[STACK_BASE,4096)`. A
  `STACK_BASE`=`0x800` (`cilcpu_defines.vh`). Stack-túlcsordulás határ = 4092.
- **CODE-fetch az on-chip SRAM-ból** egy belső *fetch-SRAM adapteren* át (a fetch/
  CALL FSM változatlanul a `r_qspi_*`/`w_qspi_*` kérő-jeleket használja, de azokat
  az adapter hajtja az `r_sram`-ból: byte-granuláris 2-szavas olvasás + LE→BE
  byteswap). A külső `o_xmem` busz **lekötve** (`o_xmem_re` VÉGIG 0).
- **Boot:** a root frame a `STACK_BASE`-re kerül (`FP=SP=STACK_BASE`, nem 0).
- **`i_ld_*` SRAM load-write port:** a programot a boot ELŐTT írja az SRAM-ba a
  SoC — mód A-ban közvetlenül az UART-loader, mód B-ben a QSPI→SRAM copy-engine.
- **Boot-mód strap (`i_boot_mode`, SoC):** L=mód A (UART→SRAM direkt, QSPI tétlen),
  H=mód B (loader→QSPI + boot-kori copy-engine QSPI→SRAM; perzisztencia + autonóm
  flash cold-boot). A QSPI = betöltés-idejű backing store.
- A `cilcpu_qspi_controller`/`cilcpu_mailbox` RTL a repóban marad (F4); a mailbox
  az F3 tape-out-configból kimarad.

## Cél

Az 5 részegység (`cilcpu_alu`, `cilcpu_decoder`, `cilcpu_microcode`, `cilcpu_stack_cache`, `cilcpu_qspi_controller`) integrációja egyetlen **Nano core**-rá: fetch → decode → execute pipeline, PC kezelés, frame manager, belső 16 KB SRAM, trap aggregátor, halt FSM. A core a TCpuNano F1 viselkedését reprodukálja az F2.4 RTL primitívekkel.

**F2.5a hatókör** (mi van itt):
- Belső 16 KB SRAM `reg [31:0] sram[0:4095]` inferred BRAM (foundry SRAM macro F2.6-ra marad)
- Egyszerű byte-szintű fetch buffer 5 byte mélységgel (I-cache F5+)
- Stack régió **CSAK belső SRAM-ban** — túlcsordulás → `TRAP_SRAM_OVERFLOW` (PSRAM spill F5+)
- HEAP régió nincs (Nano core-nak nincs is — F5 Rich)
- MMIO nincs (mailbox F3, UART F2.7)

**F2.5a NEM tartalmaz** (F2.5b-re marad):
- Golden vector harness (cocotb vs C# szim trace összevetés)
- C# szimulátor `--trace` export

## Modul: `cilcpu_core`

### Portok

| Irány | Név | Szélesség | Leírás |
|-------|-----|-----------|--------|
| **Clock / reset** | | | |
| in | `clk` | 1 | Fő órajel (50 MHz) |
| in | `rst_n` | 1 | Aszinkron aktív-low reset |
| **Boot config** | | | |
| in | `i_boot_pc` | 24 | Belépési pont a CODE szegmensen belüli byte-offset (TMethodHeader RVA + `METHOD_HEADER_SIZE`) |
| in | `i_boot_arg_count` | 8 | A boot frame argumentum száma (0..16) |
| in | `i_boot_local_count` | 8 | A boot frame lokális száma (0..16) |
| in | `i_boot_start` | 1 | 1-pulzus a futás indítására (RESET → BOOT FSM ág) |
| in | `i_boot_arg_data` | 32 | Argumentum streaming bemenet (boot szekvencia alatt szállítja az arg értékeket) |
| in | `i_boot_arg_valid` | 1 | `i_boot_arg_data` érvényes (1 ciklus pulzus per arg) |
| out | `o_boot_arg_ready` | 1 | A core kész fogadni a következő arg-ot (boot szekvencia alatt) |
| **Status / observability** | | | |
| out | `o_halt` | 1 | A core megállt (RET a root frame-en) — TOS érték a return value |
| out | `o_trap` | 1 | Trap történt (1-ciklusos pulzus, utána halt-szerű állapot) |
| out | `o_trap_code` | 8 | `TTrapReason` byte (csak `o_trap=1` ciklusban érvényes) |
| out | `o_pc` | 24 | Aktuális PC (debug observability) |
| out | `o_return_value` | 32 | Halt-kor a TOS értéke (a root frame return value-ja) |
| **QSPI pinek** | | | |
| out | `qspi_clk` | 1 | QSPI órajel (clk / 2 = 25 MHz) |
| out | `qspi_cs_flash_n` | 1 | Flash chip select (aktív-low) |
| out | `qspi_cs_psram_n` | 1 | PSRAM chip select (aktív-low; F2.5a: mindig 1 — nem használjuk) |
| out | `qspi_dq_out` | 4 | DQ kimenet |
| in | `qspi_dq_in` | 4 | DQ bemenet |
| out | `qspi_dq_oe` | 1 | DQ output enable |

### Belső 16 KB SRAM

A core-on belüli `reg [31:0] r_sram[0:4095]` (4096 × 32-bit = 16 KB), Verilog inferred BRAM. **Nem külső interfész** — a Stack Cache `sram_*` master portjai és a microcode SRAM hozzáférések ide csatlakoznak egy belső 2:1 mux-on át (lásd „Memory bus arbiter").

A reset után a teljes SRAM nullázva van — a `byte[] FSram` C#-os `new byte[16384]` viselkedéssel megegyezik.

### Belső állapot (a részegységeken kívül)

| Regiszter | Szélesség | Leírás |
|-----------|-----------|--------|
| `r_state` | 4 | Top-level FSM állapot |
| `r_pc` | 24 | Program counter (CODE szegmens byte offset) |
| `r_sp` | 14 | Stack pointer (SRAM byte cím) |
| `r_fp` | 14 | Frame pointer (aktuális frame base, SRAM byte cím) |
| `r_call_depth` | 10 | Call depth számláló (0..512) |
| `r_arg_count` | 5 | Aktuális frame arg száma (0..16) |
| `r_local_count` | 5 | Aktuális frame local száma (0..16) |
| `r_step` | 4 | Microcode mikrolépés számláló |
| `r_opcode` | 16 | Aktuális dekódolt opcode (microcode bemenet) |
| `r_length` | 3 | Aktuális utasítás hossza (1..5) |
| `r_operand` | 32 | Aktuális utasítás operandusa |
| `r_fetch_buf` | 8×8 | 8-byte rolling fetch buffer (FIFO) |
| `r_fetch_count` | 4 | Buffer-ben lévő érvényes byte-ok száma (0..8) |
| `r_fetch_pc` | 24 | A buffer első byte-jának PC-je (mindig `≤ r_pc`) |
| `r_halt` | 1 | Halt latch |
| `r_trap` | 1 | Trap latch (1 ciklus pulzus után 0) |
| `r_trap_code` | 8 | Trap kód latch |
| `r_boot_args_remaining` | 5 | Hátralévő boot arg-ok (0..16) |

### Top-level FSM állapotok

```
localparam [3:0] ST_RESET     = 4'd0;   // Reset utáni init állapot
localparam [3:0] ST_BOOT      = 4'd1;   // Boot frame felépítése (header + args + locals)
localparam [3:0] ST_FETCH     = 4'd2;   // Fetch buffer feltöltés (5 byte garantált)
localparam [3:0] ST_DECODE    = 4'd3;   // 1 ciklus: decoder eredmény → r_opcode/r_length/r_operand
localparam [3:0] ST_EXECUTE   = 4'd4;   // Microcode sequencer fut (1..N ciklus)
localparam [3:0] ST_MEM_WAIT  = 4'd5;   // Stack cache spill/fill VAGY QSPI fetch wait
localparam [3:0] ST_CALL      = 4'd6;   // Call frame felépítése (header + args copy)
localparam [3:0] ST_RET       = 4'd7;   // Ret: header olvasás, frame leszerelés
localparam [3:0] ST_HALT      = 4'd8;   // Halt — végállapot
localparam [3:0] ST_TRAP      = 4'd9;   // Trap — végállapot (halt-szerű)
```

### Boot szekvencia (ST_RESET → ST_BOOT → ST_FETCH)

A reset után a core a **root frame-et** építi az SRAM elejére (`r_fp = 0`):

1. **ST_RESET** (`rst_n` után): `r_pc = 0`, `r_sp = 0`, `r_fp = 0`, `r_call_depth = 0`, minden trap/halt = 0. `o_boot_arg_ready = 0`. Vár `i_boot_start`-ra.
2. **`i_boot_start = 1` pulzus** → ST_BOOT, `r_arg_count <= i_boot_arg_count`, `r_local_count <= i_boot_local_count`, `r_boot_args_remaining <= i_boot_arg_count`.
3. **ST_BOOT** alállapotok (sequencer-rel):
   - **Header írás** (3 SRAM write): `[FP+0] <= -1` (ReturnPC), `[FP+4] <= -1` (PrevFrameBase), `[FP+8] <= {16'h0, local_count, arg_count}` (a felső 16 bit reserved=0, a TCpuNano formátumával egyezően)
   - **Args streaming**: minden `i_boot_arg_valid=1` ciklusban `[FP + 12 + idx*4] <= i_boot_arg_data`, `idx++`. Két arg között `o_boot_arg_ready=1` jelzi a fogadásra-készet.
   - **Locals nullázás**: `r_local_count` darab írás, mind 0
   - **Frame finalize**: `r_sp <= 12 + arg_count*4 + local_count*4`, `r_call_depth <= 1`, `r_pc <= i_boot_pc`. Stack cache `sp_load=1`, `sp_init = r_sp` (üres eval stack ezen a frame-en).
4. **→ ST_FETCH**: a futás megkezdődik.

**Megjegyzés:** A boot szekvencia ezen formája egyezik a TCpuNano `Execute(byte[] AProgram, int AArgCount, int ALocalCount, int[]? AInitialArgs)` viselkedésével — a tesztharness ugyanazokat az init paramétereket adja át.

### Fetch unit (ST_FETCH)

**Cél:** garantálni, hogy a Decoder mindig 5 byte-ot lásson (`i_bytes_available = min(r_fetch_count, 5)`), kivéve a CODE szegmens végén.

**Buffer:** 8-byte FIFO (a 4-byte QSPI burst miatt felesleges 5 byte-osnál szűkebbnek lenni; 8 byte komfortot ad a 0xFE-prefixes 5-byte instrukciók után is).

**Logika:**
- Ha `r_fetch_count >= 5` → `→ ST_DECODE` (nincs fetch szükséges)
- Ha `r_fetch_count < 5` → QSPI controller `cpu_re=1`, `cpu_addr = {4'h0, r_pc + r_fetch_count[7:0]}` (CODE szegmens, 4 byte burst). Várakozás `cpu_ready=1`-re.
- `cpu_ready=1` ciklusban: `r_fetch_buf[r_fetch_count +: 4] <= cpu_rdata` (4 byte append), `r_fetch_count += 4`.
- Ha `r_fetch_count >= 5` → `→ ST_DECODE`.

**PC ugrásnál (branch/call/ret) a buffer flush:** `r_fetch_count <= 0`, `r_fetch_pc <= új_pc`, és a fetch újraindul.

**FETCH és DECODE ütemezés:** ST_DECODE 1 órajelig tart (a decoder kombinációs, az eredményt regiszterbe latcheljük). Aztán → ST_EXECUTE.

### Sequencer (ST_EXECUTE)

A microcode kombinációs — `i_opcode = r_opcode`, `i_step = r_step`. Minden ciklusban a `o_ctrl` vezérlőszót dekódoljuk és kibontjuk az enable jeleket:

| Vezérlőszó mező | Hatás |
|------------------|-------|
| `UC_TRAP=1` | `r_trap <= 1`, `r_trap_code <= o_ctrl[UC_TRAP_CODE_HI:UC_TRAP_CODE_LO]`, `→ ST_TRAP` |
| `UC_HALT=1` | `r_halt <= 1`, `→ ST_HALT` |
| `UC_STACK_POP_HI:LO` | Stack Cache `pop_en=1`, N-szer (1 vagy 2) |
| `UC_STACK_PUSH=1` | Stack Cache `push_en=1`, `push_data = mux(UC_PUSH_SRC_*)` |
| `UC_ALU_EN=1` | ALU `i_op_a = stack_cache.tos1`, `i_op_b = stack_cache.tos`, `i_alu_op = UC_ALU_OP_*` |
| `UC_SRAM_RD=1` | Belső SRAM olvasás, cím = `addr_calc(UC_ADDR_SRC_*)` |
| `UC_SRAM_WR=1` | Belső SRAM írás, cím = `addr_calc(UC_ADDR_SRC_*)`, adat = `pop_data` |
| `UC_PC_WR=1` | PC update, forrás = `UC_PC_SRC_*` |
| `UC_FRAME_PUSH=1` | `→ ST_CALL` (a sequencer a call szekvenciát többciklusosan futtatja) |
| `UC_FRAME_POP=1` | `→ ST_RET` |
| `UC_COND_EN=1` | Branch feltétel kiértékelés (lásd alább) |
| `UC_DONE=1` | `r_step <= 0`, **a vezérlőszó hatásai bekerülnek** ebben a ciklusban, majd `→ ST_FETCH` |
| egyéb | `r_step += 1`, `→ ST_EXECUTE` (következő microstep) |

**Push source mux:**
- `PUSH_SRC_ALU` → ALU `o_result`
- `PUSH_SRC_IMM` → `r_operand` (vagy a `r_operand[7:0]` egy-byte short formákhoz — a microcode külön kezeli)
- `PUSH_SRC_SRAM` → SRAM `r_data` (az aktuális ciklus végén regisztrált érték)
- `PUSH_SRC_TOS` → Stack Cache `tos`

**Cím számítás (`addr_calc`):**
- `ADDR_SRC_ARG`: `r_fp + 12 + r_operand[3:0] * 4`
- `ADDR_SRC_LOCAL`: `r_fp + 12 + r_arg_count * 4 + r_operand[3:0] * 4`
- `ADDR_SRC_FRAME`: `r_fp + r_operand[3:0]` (header mezőkre, ld. call/ret szekvenciák)
- `ADDR_SRC_IND`: `stack_cache.tos[13:0]` (`ldind.i4` / `stind.i4`)

**Tartomány-ellenőrzés:**
- `arg_index >= r_arg_count` → `TRAP_INVALID_ARG`
- `local_index >= r_local_count` → `TRAP_INVALID_LOCAL`
- `addr >= 16384` → `TRAP_INVALID_MEMORY` (csak indirect-nél lehetséges)

**Branch feltétel (`UC_COND_EN=1`):**
- A `UC_PC_SRC_*` `PC_SRC_BRANCH`, de a tényleges PC update **csak akkor** történik meg, ha a feltétel teljesül
- Feltétel: `cond_type` (EQ/NE/LT/GE), `cond_signed` (signed/unsigned), forrás: ALU result vagy stack TOS
- `UC_COND_POP=1` → mindig pop, függetlenül a feltétel teljesülésétől (brfalse/brtrue): a single-operand branch-ek esetén
- Bináris branch (beq, blt, …): pop2 + ALU + cond_check → push NEM, branch IGEN/NEM

### Memory bus arbiter (belső SRAM)

A 16 KB belső SRAM-hoz **két potenciális master**:
1. **Microcode SRAM read/write** (`UC_SRAM_RD/WR=1`)
2. **Stack Cache spill/fill** (`sram_we`/`sram_re` a `cilcpu_stack_cache` master portjáról)

**Egymást kizáró használat — egyszerű mux:**
- Ha `(UC_SRAM_RD | UC_SRAM_WR) == 1` ÉS Stack Cache `busy == 0` → microcode oldal
- Ha Stack Cache `busy == 1` → Stack Cache spill/fill fut, microcode VÁRNI köteles → `→ ST_MEM_WAIT`
- A microcode garantálja, hogy egy mikrolépésen belül vagy stack push/pop, vagy SRAM rd/wr fut, de nem mindkettő

A belső SRAM **1-ciklus latencia, registered output**: címet és we/re-t regisztráljuk, az olvasott adat a következő ciklusban érvényes (`sram_ready` mindig 1, ha nem busy). A Stack Cache spec ezzel kompatibilis.

### QSPI controller integráció

Csak a **CODE fetch path** — `cpu_addr = {4'h0, r_pc + offset}`, `cpu_re = 1` egy ciklusra, várjuk `cpu_ready`-t. Az F2.4 spec szerint egy CODE fetch ~30-40 main clock ciklus (cmd 16 + addr 12 + dummy 16 + data 8 ≈ 52 ciklus, optimalizáció nélkül).

A fetch ennyire lassú a kis modell miatt, ezért a fetch buffer kritikus: **az ALU/stack műveletek a buffer feltöltése után „ingyen" futnak**, a Decoder/Sequencer 1-3 ciklus per opcode.

### Frame manager (ST_CALL és ST_RET)

> **F2.5a státusz (Sub5 KÉSZ):** Az `ST_CALL` és `ST_RET` állapotok **teljes
> implementációval** rendelkeznek. A microcode `OP_CALL` 1-step (UC_FRAME_PUSH +
> UC_PC_WR + UC_PC_SRC=PC_SRC_CALL); a teljes szekvenciát a top-level FSM
> végzi (header read QSPI-ról, validáció, args reverse-pop, header write,
> locals zero, finalize). 48/48 cocotb teszt zöld, 13/13 trap kód lefedett:
> `test_50_call_simple_add_2_3` (Add(2,3)→5), `test_51_call_returns_then_continues`
> (Add(2,3)+5=10), `test_52_call_recursive_fib_5` (rekurzív Fibonacci(5)→5),
> `test_53_invalid_call_target` (TRAP_INVALID_CALL_TARGET), `test_54_call_depth_exceeded`
> (TRAP_CALL_DEPTH_EXCEEDED). A `TRAP_SRAM_OVERFLOW` ellenőrzés implementált
> (frame_size előzetes check), de tesztelése a 16 KB SRAM mérete miatt nehéz —
> F5+ stack PSRAM spill-tesztben záródik le.

#### ST_CALL (a `UC_FRAME_PUSH=1` után, a `call` opcode kontextusában)

A `call` opcode operandusa az új method header RVA. A szekvencia:

1. **Header olvasás** a CODE-ról a `TMethodHeader` formátum szerint (8 byte, `src/CilCpu.Sim/TMethodHeader.cs`):

   ```
    Offset  Méret  Mező          Megjegyzés
    +0      1      Magic = 0xFE  Validáció
    +1      1      arg_count     0..16
    +2      1      local_count   0..16
    +3      1      max_stack     0..64 (F2.5a: nem ellenőrzött, F5+ stack budget verifier)
    +4      2      code_size     LE u16, body hossz byte-ban (F2.5a: nem használt, F5+ branch range)
    +6      2      reserved      0
   ```

   F2.5a-ban a HW csak a `+0..+2` byte-okat dolgozza fel (3 SRAM read a fetch buffer-en át). A `+3..+5` byte-okat **átugorja** (max_stack és code_size) — ezek a Linker által generálódnak és F1-ben validáltak, az F2.5a HW ellenőrzés F5+-re marad. **Validáció:** magic ≠ `0xFE` → `TRAP_INVALID_CALL_TARGET`. A body első byte-ja `RVA + 8`.
2. **CallDepth ellenőrzés:** `r_call_depth >= 512` → `TRAP_CALL_DEPTH_EXCEEDED`
3. **Frame méret:** `frame_size = 12 + new_arg_count*4 + new_local_count*4`
4. **F2.7.D — caller eval depth:** `D = total_eval_depth (args-szal) − new_arg_count`. `caller_eval_base = r_sp` (a caller frame eval bázisa, a CALL alatt nem mozdul). `FP_new = caller_eval_base + D*4` — a callee frame a caller **megőrzött eval-eleme(i) fölé** kerül, NEM a caller eval bázisra, így nem írja felül azokat.
5. **SRAM overflow ellenőrzés:** `FP_new + 12 + new_arg_count*4 + new_local_count*4 > 16384` → `TRAP_SRAM_OVERFLOW`
6. **F2.7.D — caller eval flush (`ST_FLUSH`):** a caller TELJES eval stack-je (cache + spilled) SRAM-ba ürül, contiguous `[caller_eval_base .. caller_eval_base + total*4)`. A held D elem `[caller_eval_base .. FP_new)`, az args `[FP_new .. FP_new + N*4)`. A Stack Cache `cache_count <= 0` (a callee tiszta cache-sel indul).
7. **Args másolás SRAM→SRAM** (a flush után): `SRAM[FP_new + j*4]` (= arg j) → callee slot `[FP_new + 12 + j*4]`, `j = N−1..0` csökkenő sorrendben (a `dst = src+12` felülírás és a header-írás így nem ütközik).
8. **Header írás az új frame-be:** `[FP_new + 0] <= return_pc = r_pc + r_length`, `[FP_new + 4] <= r_fp`, `[FP_new + 8] <= {16'h0, new_local_count, new_arg_count}`
9. **F2.7.D — caller eval depth mentése:** `[caller_fp + 8][22:16] <= D` (a header reserved 2 byte-ja, `[FP+10:11]`; D ≤ 64 → 7 bit). RET-kor innen olvassuk vissza. Az alsó bitek (caller arg/local count) változatlanok.
10. **Locals nullázás:** `new_local_count` darab írás a `[FP_new + 12 + new_arg_count*4 + i*4]` slotokba.
11. **Regiszter frissítés:** `r_fp <= FP_new`, `r_sp <= FP_new + 12 + new_arg_count*4 + new_local_count*4` (callee eval bázis), `r_arg_count <= new_arg_count`, `r_local_count <= new_local_count`, `r_call_depth += 1`, `r_pc <= call_target_rva + 8`
12. **Stack cache reset a callee-re:** `sp_load=1`, `sp_init = callee eval bázis`, `sp_depth = 0` (üres eval; a `sp_load` MINDIG üríti a cache-t — a megőrzött elemek az SRAM-ban élnek).

#### ST_RET (a `UC_FRAME_POP=1` után, a `ret` opcode kontextusában)

1. **Return value pop:** ha az aktuális method-nak van return value-ja (most: minden `ret` 1 értéket ad vissza, kivéve void — F2.5a: feltesszük, hogy ret előtt 1 érték van TOS-on; ha eval stack üres → return value = 0 default; void support F5+).
2. **Root frame ellenőrzés:** `r_call_depth == 1` → halt: `r_halt <= 1`, `o_return_value <= return_val`, `→ ST_HALT`
3. **Frame header olvasás:** `return_pc = SRAM[r_fp + 0]`, `prev_fp = SRAM[r_fp + 4]`
4. **SP visszaállítás:** `r_sp <= caller eval bázis = prev_fp + 12 + caller_arg_count*4 + caller_local_count*4` (a callee SRAM felszabadul; a frame eval-pointer regiszter a caller bázisára áll).
5. **Frame regiszterek caller-ra:** `r_fp <= prev_fp`. Az `r_arg_count`, `r_local_count` és a megőrzött caller eval depth `D` a **caller frame header-jéből** (`SRAM[prev_fp + 8]`): `caller_arg_count = [7:0]`, `caller_local_count = [15:8]`, `D = [22:16]`.
6. **F2.7.D — Stack cache caller-re a megőrzött eval depth-tel:** `sp_load=1`, `sp_init = caller eval bázis`, `sp_depth = D`. A Stack Cache `ST_SPFILL` szekvenciája a top `min(D,4)` held elemet SRAM-ból a cache-be tölti (`r_t0 = SRAM[base+(D-1)*4]` = TOS ...). **Invariáns:** `cache_count = min(depth,4)` — az ALU 2-operandus opjai a `tos`/`tos1` cache-only kombinációs kimeneteket olvassák, ezért a top elemeknek a cache-ben kell lenniük. A `RET_PUSH_RV` megvárja a `ST_SPFILL` befejezését (`!busy`).
7. **Return value push a caller eval stack-jére:** `push_data = return_val`, `push_en=1` → caller eval depth `D → D+1`.
8. **PC update:** `r_pc <= return_pc`
9. **Call depth dekrement:** `r_call_depth -= 1`
10. **→ ST_FETCH**

**Megjegyzés a frame header reserved mezőről (F2.7.D — IMPLEMENTÁLT):** a TCpuNano `[FP+10:11]` 2 byte-ot alignment reserved-ként dokumentálja; a HW a **caller eval depth** (`D ≤ 64 → 7 bit`) tárolására használja: `[caller_fp+8][22:16]`. A `call` ezt írja, a `ret` visszaolvassa, és a Stack Cache `ST_SPFILL` ennek alapján tölti vissza a caller megőrzött eval-elemeit SRAM-ból. Ezzel a rekurzív / multi-eval CALL/RET (pl. `Fib(n-1)+Fib(n-2)`) **helyesen** működik — regresszió: `test_core.py::test_52c_recursive_fib10_roslyn_boot_no_caller` (Fib(10)=55) és `test_52_call_recursive_fib_5`. Ez **eltér a TCpuNano-tól**, ahol a caller eval depth az `FCallStack` rekordban van — ezért **az F2.5b golden vector harness-ben a memória-trace nem byte-pontos** ezen a 2 byte-on (tudatos, dokumentált eltérés). Korábbi állapot (project_recursive_call_bug): a `RET_FINALIZE` kihagyta a `+ D` tagot → a caller megőrzendő eval-elemei elvesztek, `TRAP_STACK_UNDERFLOW`. Vault: `Bug-Debug-Log/2026-05-15-recursive-call-eval-depth-loss`.

### Trap aggregátor

A trap források prioritása (felülről lefelé), egy ciklusban legfeljebb egy trap aktív:

1. **Decoder** `o_trap_invalid` → `TRAP_INVALID_OPCODE`
2. **Microcode** `o_valid=0` → `TRAP_INVALID_OPCODE` (a decoder elfogadta, de a microcode nem ismeri — F1-ben mind a 48 elfogadott)
3. **ALU** `o_trap_div_zero` → `TRAP_DIV_BY_ZERO`
4. **ALU** `o_trap_overflow` → `TRAP_OVERFLOW`
5. **Stack Cache** `trap=1` → `trap_code` (overflow/underflow)
6. **Microcode** `UC_TRAP=1` → `o_ctrl[UC_TRAP_CODE_*]`
7. **Frame manager** belső ellenőrzések: `TRAP_CALL_DEPTH_EXCEEDED`, `TRAP_INVALID_CALL_TARGET`, `TRAP_SRAM_OVERFLOW`, `TRAP_INVALID_BRANCH`, `TRAP_INVALID_ARG`, `TRAP_INVALID_LOCAL`, `TRAP_INVALID_MEMORY`
8. **Microcode** `OP_BREAK` (`0xDD`) → `TRAP_DEBUG_BREAK`

**Trap szemantika:**
- `o_trap` **pontosan 1 órajel pulzus** a trap detekció ciklusát követő rising edge-en, `o_trap_code` ekkor érvényes
- Trap után a core `ST_TRAP` állapotba kerül, ahonnan **nincs visszatérés** reset nélkül (`rst_n=0`)
- `o_halt` és `o_trap` **nem aktív egyszerre** (egy run vagy halt-tal vagy trap-pel végződik)

### Halt szemantika

- `o_halt = 1` egy run végéig (új run csak reset után indítható)
- `o_return_value` a TOS értéke a halt ciklusban (vagy 0, ha az eval stack üres volt)
- `o_pc` a halt-ot okozó `ret` PC-jét tartja (debug)

### PC update szemantika (mit jelent a `PC_SRC_*`)

- **`PC_SRC_NEXT`**: `r_pc <= r_pc + r_length` (a decoder által számolt utasításhossz)
- **`PC_SRC_BRANCH`**: `r_pc <= r_pc + r_length + signed_extend(r_operand[7:0])` rövid (`*_S`) branch-ekhez. A signed_extend 8→24-re a 2-komplemensből.
  - **Branch target validáció:** ha `target < 0` vagy `target >= code_size` → `TRAP_INVALID_BRANCH`. F2.5a-ban a `code_size`-t nem ismerjük → csak a negatív címet trap-eljük; pozitív túlcsordulást a fetch unit detektál (QSPI olvasás 0xFF byte-okat ad → `TRAP_INVALID_OPCODE` a következő dekódoláson).
- **`PC_SRC_CALL`**: `r_pc <= r_operand + 8` (RVA + METHOD_HEADER_SIZE)
- **`PC_SRC_RET`**: `r_pc <= sram[r_fp + 0]` (a frame header ReturnPC mezője)

### Időzítés (egy opcode lefutása)

| Esemény | Tipikus ciklus |
|---------|----------------|
| Cold fetch (üres buffer, 4 byte) | ~52 main clock (QSPI) |
| Warm fetch (buffer >= 5 byte) | 0 (azonnal ST_DECODE) |
| Decode | 1 |
| Execute (egyszerű ALU/const) | 1 |
| Execute (LDARG/STLOC) | 2 (1 mikrolépés + 1 SRAM ciklus) |
| Execute (CALL) | 5–20 (header read + N args + locals zero) |
| Execute (RET) | 4–6 |
| Execute (Stack Cache spill) | +1 ciklus |

**Kódsűrűség per fetch:** átlag 1.5 byte/opcode, 4 byte fetch → ~2.7 opcode/fetch → cold fetch amortizálva ~20 ciklus/opcode. F5+ I-cache-szel ~1 ciklus/opcode warm path.

### Cocotb tesztcsoportok (F2.5a TDD piros)

A `rtl/tb/test_core.py` tesztsuite-jának fedezni kell:

**1. Reset és boot smoke**
- `test_reset` — `rst_n=0` után minden regiszter 0, `o_halt=0`, `o_trap=0`
- `test_boot_no_args` — `i_boot_pc=0`, `i_boot_arg_count=0`, `i_boot_local_count=0`, `i_boot_start=1` → root frame felállítva (header SRAM-ban), `o_pc=0`, futás megkezdődik
- `test_boot_with_args` — 2 arg streaming, args megtalálhatóak `[FP+12]`, `[FP+16]` címeken

**2. Egyetlen utasítás (LDC + RET)**
- `test_ldc_i4_5_ret` — program: `0x1B 0x2A` (LDC.I4_5, RET) → `o_halt=1`, `o_return_value=5`
- `test_ldc_i4_s_ret` — `0x1F 0x2A 0x2A` (LDC.I4.S 42, RET) → `o_return_value=42`
- `test_ldc_i4_ret` — `0x20 imm32 0x2A` → `o_return_value=imm32`

**3. Aritmetika (ADD/SUB/MUL/DIV)**
- `test_add_2_3` — LDC 2, LDC 3, ADD, RET → 5
- `test_sub_10_4` — 6
- `test_mul_7_8` — 56
- `test_div_20_5` — 4
- `test_div_zero_trap` — LDC 5, LDC 0, DIV, RET → `o_trap=1`, `o_trap_code=TRAP_DIV_BY_ZERO`

**4. Branch (BR_S, BRFALSE_S, BEQ_S, …)**
- `test_br_s_forward` — egy unconditional ugrás, target stmt fut le
- `test_brtrue_s_taken` — feltétel = 1 → branch
- `test_brfalse_s_not_taken` — feltétel = 1 → fall-through
- `test_beq_s_taken` — két egyenlő érték
- `test_blt_s_signed` — -5 < 3 → taken

**5. Local variable**
- `test_ldloc_stloc_roundtrip` — STLOC.0 42, LDLOC.0, RET → 42
- `test_invalid_local_trap` — LDLOC.5 amikor local_count=2 → `TRAP_INVALID_LOCAL`

**6. Argument**
- `test_ldarg_0_ret` — boot args = [99], LDARG.0, RET → 99
- `test_ldarg_1_ret` — boot args = [10, 20], LDARG.1, RET → 20

**7. Call/Ret**
- `test_call_simple` — `Add(2, 3) → 5` (egyszerű 2-arg statikus call)
- `test_call_recursive_fib_5` — Fibonacci(5) → 5

**8. Stack overflow / underflow**
- `test_stack_overflow_trap` — 65 LDC.I4.S → `TRAP_STACK_OVERFLOW`
- `test_stack_underflow_trap` — POP üres stack-en → `TRAP_STACK_UNDERFLOW`

**9. Invalid opcode**
- `test_invalid_opcode_trap` — fetch buffer 0xFF byte-tal → `TRAP_INVALID_OPCODE`

**10. Halt and observability**
- `test_halt_after_root_ret` — root RET → `o_halt=1` egy ciklusra felmegy és tartja
- `test_pc_observability` — `o_pc` nyomon követi a futást (legalább néhány smoke ciklus)

**Aranypéldához kötés:** minden teszt `o_return_value` és/vagy `o_trap_code` mezőit a TCpuNano F1 szimulátor azonos programmal kapott eredményével hasonlítja össze. Az SRAM byte-trace összehasonlítás az F2.5b golden harness része lesz.

### Verifikációs minimum

A `make test_core` futtatás esetén:
- Minden tesztcsoport (1–10) tartalmaz legalább 1 esetet
- Minden trap kód (a 13 közül) **legalább egy teszt által triggerelve van**: TRAP_STACK_OVERFLOW, TRAP_STACK_UNDERFLOW, TRAP_INVALID_OPCODE, TRAP_INVALID_LOCAL, TRAP_INVALID_ARG, TRAP_INVALID_BRANCH, TRAP_INVALID_CALL_TARGET, TRAP_DIV_BY_ZERO, TRAP_OVERFLOW, TRAP_CALL_DEPTH_EXCEEDED, TRAP_DEBUG_BREAK, TRAP_INVALID_MEMORY, TRAP_SRAM_OVERFLOW
- Cél: 30+ cocotb teszt zöld

### Egyszerűsítések / nyitott kérdések (F2.5a tudatos kompromisszumai)

1. **Eval stack megőrzése `call` előtt (F2.7.D — MEGOLDVA):** a `call` előtti caller eval-elemek (pl. `Fib(n-1)`, miközben `Fib(n-2)`-t számoljuk) **megőrződnek**: a CALL `ST_FLUSH`-sal SRAM-ba üríti a caller eval-t, a callee frame-et a held elemek **fölé** teszi (`FP_new = caller_eval_base + D*4`), a `D`-t a caller header reserved mezőjébe menti; a RET `sp_depth=D`-vel és a Stack Cache `ST_SPFILL` cache-újratöltéssel állítja vissza. Rekurzív / multi-eval CALL/RET helyes. (Korábban F2.5a undefined behavior volt — lásd project_recursive_call_bug.)
2. **Frame header reserved mező:** caller eval depth tárolására használjuk (eltérés a C# szimtól). Az F2.5b golden harness ezen a 2 byte-on tűr.
3. **PSRAM stack overflow:** az F2.5a-ban a 16 KB belső SRAM túlcsordulásakor `TRAP_SRAM_OVERFLOW`. F5+ fázisban a Stack Cache PSRAM-ra spillel.
4. **Inferred BRAM:** Verilog `reg [31:0] r_sram[0:4095]`, FPGA-n a Vivado/Yosys BRAM-ba mappolja. ASIC-on F2.6-ban Sky130 SRAM macro-ra cseréljük.
5. **Power-on init:** a SRAM nem garantáltan 0 reset után FPGA/ASIC-on. **F2.5a viselkedés:** a boot szekvencia mindent felül-ír, amit használ, és az olvasás csak felül-írt címekről történik (a TCpuNano-tól örökölt invariáns). A boot trap (random olvasás) F1-szabály: nincs.

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.5 | 2026-05-16 | **F2.7.D KÉSZ — rekurzív CALL/RET caller eval depth megőrzés (gyökér-fix).** A korábbi „F2.5a egyszerűsítés" (a caller eval-elemei elvesztek CALL/RET között → `TRAP_STACK_UNDERFLOW` rekurzív `Fib(n-1)+Fib(n-2)`-nél, project_recursive_call_bug) megoldva. **Stack Cache** (`cilcpu_stack_cache.v`): új `flush_en` (teljes cache → SRAM, `depth` invariáns) + `ST_FLUSH`; `sp_depth` bemenet + módosított `sp_load` (a cache MINDIG ürül, `r_sp = base + sp_depth*4`); új `ST_SPFILL` (a top `min(D,4)` held elem SRAM→cache visszatöltés, fenntartja a `cache_count = min(depth,4)` invariánst, amit az ALU `tos`/`tos1` cache-only kimenetei megkövetelnek). **Core** (`cilcpu_core.v`): `ST_CALL` — `FP_new = caller_eval_base + D*4` (a held elemek fölé), `CALL_FLUSH` + SRAM→SRAM arg-másolás + `CALL_SAVE_D` (`[caller_fp+8][22:16] <= D`); `ST_RET` — `RET_LATCH_AL` kiolvassa `D`-t, `RET_FINALIZE` `sp_depth=D`-vel restore-ol, `RET_WAIT_SPFILL` bridge + `RET_PUSH_RV` `!busy` őr. Regresszió: **test_core 49/49, test_stack_cache 28/28** (3 új flush/sp_depth unit teszt), test_a7lite_top 8/8, test_a7lite_fib 1/1, test_a7lite_board 4/4 (+fib 1/1), test_core_golden 3/3. Új regressziós teszt: `test_52c_recursive_fib10_roslyn_boot_no_caller` (Roslyn-linkelt rekurzív Fib(10)=55). Vault: `Bug-Debug-Log/2026-05-15-recursive-call-eval-depth-loss`. |
| 1.4 | 2026-05-05 | **F2.5a Sub5 KÉSZ — CALL/RET non-root frame manager.** Az `ST_CALL` és `ST_RET` állapotok teljes szekvenciális implementációja: header read QSPI-ról (4 byte word, magic+arg+local+max_stack), magic ≠ 0xFE → `TRAP_INVALID_CALL_TARGET`; call_depth ≥ 512 → `TRAP_CALL_DEPTH_EXCEEDED`; r_sp + frame_size > 16384 → `TRAP_SRAM_OVERFLOW`. Args reverse-pop (TOS = arg[N-1] első) a Stack Cache-ből SRAM-ba; 3 ciklus header write (return_pc, prev_fp, arg+local count); locals nullázása; finalize (regiszterek + sc_sp_load + fetch flush). RET: 3× SRAM read (return_pc, prev_fp, caller arg+local count) 2-ciklus latency-vel; finalize + return value push a caller eval stack-jére. Microcode `OP_CALL` 1-step-re egyszerűsítve (UC_FRAME_PUSH + UC_PC_WR + UC_PC_SRC=PC_SRC_CALL). 5 új cocotb teszt: simple CALL (Add(2,3)→5), continue-after-CALL (Add(2,3)+5=10), recursive Fibonacci(5)→5, invalid_call_target trap, call_depth_exceeded trap. **48/48 cocotb teszt zöld**, 12/13 trap kód tesztelt (TRAP_SRAM_OVERFLOW implementált de F5+-ban tesztelt), 0 Verilator warning. |
| 1.3 | 2026-05-04 | Devil's Advocate végaudit hiánypótlás: (1) Sub4 `TRAP_INVALID_BRANCH` (0x06) — negatív branch target (`pc_next[23] == 1`) detektálása BR_S / BRFALSE_S / BRTRUE_S / BEQ_S / BLT_S / BGE_S taken ágban, új `branch_target_invalid` wire + 2 trap pont (1-op és 2-op branch). F2.5a egyszerűsítés: pozitív túlcsordulás a fetch-en detektálódik (0xFF → INVALID_OPCODE). (2) Sub2 OVERFLOW trap (0x09) — `INT_MIN/-1` eset már HW-támogatott az ALU-ban, csak a teszt hiányzott (`test_25_div_overflow`). (3) Frame manager szekció elejére explicit „F2.5a státusz" doboz: `ST_CALL`/`ST_RET` placeholder, Sub5 a következő ülésre halasztva (5+ teszt: simple CALL/RET, Fibonacci(5), `call_depth_exceeded`, `invalid_call_target`). 43 cocotb teszt zöld (41 + 2 új), 9/13 trap kód lefedett (Sub5 halasztott 4 trap-pel), 0 Verilator warning. |
| 1.2 | 2026-05-04 | Sub-iteráció állapot: Sub1 (skeleton, LDC+RET) ✅, Sub2 (aritmetika+ALU phase) ✅, Sub2.1 (`r_qspi_inflight`+`r_next_fetch_addr` Verilator NBA fetch addr fix) ✅, Sub2.2 (APPEND general count 0..4) ✅, Sub3 (LDARG/STARG/LDLOC/STLOC + ST_MEM_WAIT 2-fázisú + SRAM bus arbiter) ✅, Sub4 (BR_S/BRTRUE/BRFALSE/BEQ/BLT/BGE branch eldöntés) ✅, Sub6 (Stack Cache trap aggregátor) ✅. **Sub5 (CALL/RET nem-root) — NYITOTT, a következő ülésre marad.** Verilator gotcha-k dokumentálva: SRAM read 1-ciklus latency miatt ST_MEM_WAIT 2 ciklus kell (X = r_sram_re=1, X+1 = `if (r_sram_re)` lefut → r_sram_rdata_latched <= sram NBA, X+2 = friss érték látszik). 41 cocotb teszt zöld, 0 FAIL, 0 expect_fail, Verilator 0 warning. |
| 1.1 | 2026-05-04 | Devil's Advocate audit: TMethodHeader formátum pontosítás (4 mező: arg_count, local_count, max_stack, code_size). F2.5a HW csak az első 3 byte-ot dolgozza, max_stack és code_size F5+-re marad. Megerősítés, hogy branch közbeni fetch abort nincs (a branch csak ST_EXECUTE-ban fut, QSPI ekkor IDLE). |
| 1.0 | 2026-05-04 | Kezdeti F2.5a top-level Nano core spec — 5 részegység integráció, fetch/decode/execute pipeline, frame manager, trap aggregátor |
