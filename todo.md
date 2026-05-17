# TODO — halasztott taszkok

> Ez a fájl a roadmap-en kívül halasztott debug / bug-fix taszkokat tartja
> nyilván. Minden bejegyzéshez tartozik roadmap-sor és Vault-bejegyzés,
> hogy ne legyen "rejtett akna" a kódban.

---

## F2.7.E — Config-flash app-bázis-offszet (Sub5.A)

- **Roadmap:** F2.7 Sub5.A, `docs/roadmap-hu.md` / `docs/roadmap-en.md`
- **Vault:** `project_flash_base_offset` (MEGOLDVA)
- **Státusz:** ✅ MEGOLDVA — 2026-05-17 (Sub5.A, nincs külön commit-hash:
  a fő session commitol)
- **Felvéve:** 2026-05-17 (Sub5 build-infra README "nyitott HW-kérdés")

### Gyökér-ok

A Xilinx 7-series SPI master a `.bit` bitstream-et az IS25L128F config
flash **0x000000**-ról bootolja (~9,9 MB XC7A200T). A
`cilcpu_qspi_controller` a CODE szegmenst kőbe vésve a flash
`{4'h0, cpu_addr[19:0]}` címére fordította → a CIL-T0 app **is**
0x000000-ról indult volna → **bitstream ↔ app ütközés** a fizikai
flash-en. A korábbi Sub5 build-infra ezt "nyitott HW-kérdés"-ként
hagyta (sim-paritás `APP_OFFSET=0x0`, HW-ütközés nyíltan kimondva).

### Fix (RTL-gyökér, nem workaround)

`CODE_BASE_OFFSET` paraméterezhető generic a
`cilcpu_qspi_controller`-ben (default `0` → sim-paritás), végighúzva a
teljes láncon: `cilcpu_qspi_controller` ← `cilcpu_core` ←
`cilcpu_a7lite_top` ← `cilcpu_a7lite_board`. SEG_CODE ág:
`r_addr <= CODE_BASE_OFFSET[23:0] + {4'h0, cpu_addr[19:0]}`. FPGA-érték
`0xC00000` (12 MB, a ~9,9 MB bitstream fölé; app-ablak 1 MB
`0xC00000..0xCFFFFF` < 16 MB). Egyetlen forrás: a generic =
`write_cfgmem.tcl` `CODE_BASE_OFFSET_HEX` = OpenXC7 `CODE_BASE_OFFSET`
chparam = Vivado `create_project.tcl` generic.

`SEG_DATA` szándékosan NEM kapott offszetet (int-only CIL-T0 nem
használ statikus DATA flash-régiót; sim-paritás test_08 erre épül;
offszetelni teszt/use-case nélkül over-engineering). Ha DATA
flash-backed lesz → külön taszk + teszt.

### Regresszió (mind zöld, Verilator + cocotb)

- `test_qspi_controller` 31/31 (test_30/31 skip @ offset 0)
- `test_qspi_controller_offset` 2/2 (új, `CODE_BASE_OFFSET=256`)
- `test_core` 49/49, `test_stack_cache` 28/28,
  `test_a7lite_top` 8/8, `test_a7lite_fib` 1/1,
  `test_a7lite_board` 4/4, `test_a7lite_board_fib` 1/1
  (FibonacciIterative(20)=6765)

---

## F2.7.D — Rekurzív CALL/RET root-frame teardown bug fix

- **Roadmap:** F2.7.D (~10 órás debug sprint), `docs/roadmap-hu.md`
- **Vault:** `project_recursive_call_bug` (MEGOLDVA),
  `Bug-Debug-Log/2026-05-15-recursive-call-eval-depth-loss`
- **Státusz:** ✅ MEGOLDVA — commit `762536b` (2026-05-16)
- **Felvéve:** 2026-05-12 (F2.7 Sub3 KÉSZ commit, `c81e3f2`)

### Megoldás (gyökér-fix)

A `RET_FINALIZE` a caller Stack Cache-t az eval bázisra állította,
eldobva a hívás alatt megőrzendő eval-elemeket. Gyökér-fix 3 modulban
(`cilcpu_stack_cache.v` flush_en/ST_FLUSH + sp_depth/ST_SPFILL;
`cilcpu_core.v` ST_CALL FP_new a held elemek fölé + D a header reserved
mezőbe, ST_RET D-vel restore + RET_WAIT_SPFILL bridge). Állandó
regressziós teszt: `test_52c_recursive_fib10_roslyn_boot_no_caller`
(Fib(10)=55, rekurzív Roslyn, wrapper boot caller frame nélkül).

### Tünet

A Roslyn-linkelt **rekurzív** `Math.Fibonacci` a wrapper boot-mintával
(caller frame nélkül, `boot_pc=8` közvetlenül a Fib body-tól)
`TRAP_STACK_UNDERFLOW`-val trap-el ~5 mélységnél.

### Mi működik (kontroll)

- `test_52_call_recursive_fib_5` hand-coded cocotb teszt (caller frame-mel): zöld
- `TCpuNano` C# szim Fib(10)=55: helyes ugyanazzal a binárissal
- Az iteratív Math.FibonacciIterative wrapper-rel: 1/1 PASS (Sub3)

### Gyanú

A `cilcpu_core.v` Sub5 frame manager **teardown logikája**, amikor a
"root frame"-et nem CALL hozta létre (wrapper boot directly into Fib body).

### Workaround a Sub3-ban

`Math.FibonacciIterative` (loop-os Fibonacci) — ugyanaz az eredmény,
LDLOC/STLOC/ADD/BLT_S/BR_S opkódfedéssel (mind 100% fedett).

### Debug sprint terv (~10 h) — ✅ LEZÁRT (megtörtént, commit `762536b`)

1. Trace export rekurzív hívásnál (TCpuNanoTracer + cocotb trace mismatch)
2. Wrapper-rel azonos boot-séma a hand-coded tesztben → bug reprodukció
3. Frame manager FSM állapotok diff-je: CALL-by-CALL vs root-by-boot
4. Fix + golden vector regression

**Regresszió:** test_core 49/49, test_stack_cache 28/28 (+3 új unit
teszt), wrapper/board mind zöld. CORE_SPEC v1.5, roadmap v1.6.
