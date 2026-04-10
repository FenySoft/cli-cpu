# CIL-T0 — ISA Specifikáció

Ez a dokumentum a **CIL-T0** subset-et specifikálja, amely a CLI-CPU első megvalósított utasításkészlete, és amely **Tiny Tapeout-on (F3)** gyártásra kerül.

## Áttekintés

A CIL-T0 az ECMA-335 CIL **szigorú, bitről-bitre kompatibilis részhalmaza**. Minden CIL-T0 opkód a standard CIL opkód ugyanazt a bájt-kódolást használja, ugyanazzal a stack-szemantikával. Ez azt jelenti, hogy egy CIL-T0 programot **bármely szabványos CIL disassemblerrel** (pl. `ildasm`, `dnSpy`) meg lehet nézni, és **bármely szabványos CIL runtime** (CoreCLR, Mono, nanoFramework) futtatni tudná — de ez fordítva nem igaz: egy CoreCLR alatt futó tetszőleges .NET program nem fog futni CIL-T0-n, mert a legtöbb valódi program objektumokat, stringeket, virtuális hívásokat, kivételeket használ, amiket a CIL-T0 **nem implementál**.

### Célkitűzések

1. **Minimális** — elférjen egy Tiny Tapeout 8×2 tile budget-ben (~15-20k standard cell).
2. **Teljes** az integer-only, statikus-hívás programokra — egy Fibonacci, egy GCD, egy integer bubble-sort futtatható legyen.
3. **Szigorúan szabványos** — nincsenek saját opkódok, minden ECMA-335-ből származik.
4. **Hardveres biztonság F0-ban is** — stack overflow/underflow, branch target, lokális index bounds mind hardveres trap.
5. **TDD-barát** — minden opkód egyértelműen specifikált, a szimulátor tesztek egy-egyértelműen megfeleltethetőek.

### Ami NINCS a CIL-T0-ban

| Hiányzó funkció | Miért | Mikor kerül be |
|----------------|-------|----------------|
| Objektum model (class, struct field) | Metaadat-walker hiánya, heap allocator hiánya | F4 |
| Garbage collection | Heap hiánya | F4 |
| Virtuális hívás, interface | vtable cache hiánya | F4 |
| Tömbök | Bounds check hardver és allocator hiánya | F4 |
| String | Intern tábla és heap hiánya | F4 |
| Floating point (R4, R8) | FPU terület | F5 |
| 64-bit integer | Dupla szélesség terület | F5 |
| Exception handling (try/catch) | Shadow reg file hiánya | F5 |
| Generics | Metaadat komplexitás | F5 |
| Delegate | Method reference modell hiánya | F5 |
| Thread synchronization (volatile., stb.) | Egyetlen mag, nincs SMP | F6+ |

## Memória modell

A CIL-T0-ra a `docs/architecture.md` memória modelljének **szűkített változata** érvényes:

| Régió | Cím tartomány | Tartalom | Backing | Méret (F3) |
|-------|---------------|----------|---------|------------|
| **CODE** | `0x0000_0000` – `0x000F_FFFF` | CIL bytecode (.cil-t0 bináris formátum) | QSPI Flash | 1 MB |
| **DATA** | `0x1000_0000` – `0x1003_FFFF` | `.data` szegmens (konstansok, statikus mezők) | QSPI Flash / PSRAM | 256 KB |
| **STACK** | `0x2000_0000` – `0x2000_3FFF` | Eval stack + lokálisok + arg-ok + frame-ek | QSPI PSRAM | 16 KB |
| **MMIO** | `0xF000_0000` – `0xFFFF_FFFF` | UART, GPIO, timer | On-chip | — |

**Nincs HEAP** a CIL-T0-ban, mert nincs `newobj`/`newarr`.

## Stack szemantika

A CIL-T0 stack-gépként működik, **32-bit széles** stack elemekkel (`I4` típus).

- **Evaluation stack:** max 64 elem mélység. Spill a STACK régió frame-jébe, ha szükséges.
- **Lokális változók:** max 16 per metódus (`ldloc.0..3`, `ldloc.s 4..15`).
- **Argumentumok:** max 16 per metódus (`ldarg.0..3`, `ldarg.s 4..15`).
- **Top-of-Stack Cache:** 4 elem (F3 Tiny Tapeout), azaz TOS, TOS-1, TOS-2, TOS-3 fizikai regiszterben.

Minden stack elem típusa **`I4` (32-bit signed integer)**. A CIL-T0-ban nincs más típus.

## Hívási konvenció

- **Paraméterek:** a caller push-olja az evaluation stackra a hívás előtt.
- **Frame:** a `call` mikrokódja automatikusan felépíti:
  ```
    return PC
    saved BP
    saved SP
    arg 0
    arg 1
    ...
    local 0
    local 1
    ...
    (eval stack bottom ide nő)
  ```
- **Visszatérési érték:** a `ret` előtt a metódus a return érték push-olja a TOS-ra, a `ret` megtartja azt és a frame-t lebontja.
- **Max frame méret:** 256 bájt (F3-ban), ami max 16 arg + 16 local + 32 eval stack slot.

## Opkód katalógus

Az alábbi 48 opkód képezi a CIL-T0 teljes utasításkészletét. Minden opkód a **standard ECMA-335 bájt-kódolást** használja.

### Jelölések

- **Bájt(ok)** — opkód bájt(ok), a CIL szabvány szerint. `0xFE` prefix esetén két bájt.
- **Operandus** — az opkód után következő immediate bájt(ok), ha van.
- **Hossz** — teljes opkód hossza bájtban.
- **Stack** — stack hatás: `(→ I4)` push egy int32-t, `(I4, I4 → I4)` pop két int32-t, push egyet, `(I4 →)` pop egyet nothing-ra, stb.
- **Ciklus** — előre becsült ciklusszám @ 50 MHz, cache hit mellett.
- **Dek.** — `HW` = hardwired, `μC` = mikrokódolt.
- **Trap** — a lehetséges hardveres trap feltételek.

### 1. Konstans betöltés

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0x14` | `ldnull` | 1 | `(→ I4)` | 1 | HW | Push 0-t (null mint int). |
| `0x15` | `ldc.i4.m1` | 1 | `(→ I4)` | 1 | HW | Push -1. |
| `0x16` | `ldc.i4.0` | 1 | `(→ I4)` | 1 | HW | Push 0. |
| `0x17` | `ldc.i4.1` | 1 | `(→ I4)` | 1 | HW | Push 1. |
| `0x18` | `ldc.i4.2` | 1 | `(→ I4)` | 1 | HW | Push 2. |
| `0x19` | `ldc.i4.3` | 1 | `(→ I4)` | 1 | HW | Push 3. |
| `0x1A` | `ldc.i4.4` | 1 | `(→ I4)` | 1 | HW | Push 4. |
| `0x1B` | `ldc.i4.5` | 1 | `(→ I4)` | 1 | HW | Push 5. |
| `0x1C` | `ldc.i4.6` | 1 | `(→ I4)` | 1 | HW | Push 6. |
| `0x1D` | `ldc.i4.7` | 1 | `(→ I4)` | 1 | HW | Push 7. |
| `0x1E` | `ldc.i4.8` | 1 | `(→ I4)` | 1 | HW | Push 8. |
| `0x1F` | `ldc.i4.s <sb>` | 2 | `(→ I4)` | 1 | HW | Push signed-extended 8-bit immediate. |
| `0x20` | `ldc.i4 <i4>` | 5 | `(→ I4)` | 1 | HW | Push 32-bit immediate. |

**Trap:** Stack overflow (ha az eval stack eléri a max 64 mélységet).

### 2. Lokális változó hozzáférés

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0x06` | `ldloc.0` | 1 | `(→ I4)` | 1 | HW | Push local[0]. |
| `0x07` | `ldloc.1` | 1 | `(→ I4)` | 1 | HW | Push local[1]. |
| `0x08` | `ldloc.2` | 1 | `(→ I4)` | 1 | HW | Push local[2]. |
| `0x09` | `ldloc.3` | 1 | `(→ I4)` | 1 | HW | Push local[3]. |
| `0x11` | `ldloc.s <ub>` | 2 | `(→ I4)` | 1 | HW | Push local[ub], 0 ≤ ub ≤ 15. |
| `0x0A` | `stloc.0` | 1 | `(I4 →)` | 1 | HW | Pop → local[0]. |
| `0x0B` | `stloc.1` | 1 | `(I4 →)` | 1 | HW | Pop → local[1]. |
| `0x0C` | `stloc.2` | 1 | `(I4 →)` | 1 | HW | Pop → local[2]. |
| `0x0D` | `stloc.3` | 1 | `(I4 →)` | 1 | HW | Pop → local[3]. |
| `0x13` | `stloc.s <ub>` | 2 | `(I4 →)` | 1 | HW | Pop → local[ub], 0 ≤ ub ≤ 15. |

**Trap:** Stack underflow (üres stackről pop), Local index out of range (ub ≥ 16 → `INVALID_LOCAL` trap).

### 3. Argumentum hozzáférés

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0x02` | `ldarg.0` | 1 | `(→ I4)` | 1 | HW | Push arg[0]. |
| `0x03` | `ldarg.1` | 1 | `(→ I4)` | 1 | HW | Push arg[1]. |
| `0x04` | `ldarg.2` | 1 | `(→ I4)` | 1 | HW | Push arg[2]. |
| `0x05` | `ldarg.3` | 1 | `(→ I4)` | 1 | HW | Push arg[3]. |
| `0x0E` | `ldarg.s <ub>` | 2 | `(→ I4)` | 1 | HW | Push arg[ub], 0 ≤ ub ≤ 15. |
| `0x10` | `starg.s <ub>` | 2 | `(I4 →)` | 1 | HW | Pop → arg[ub], 0 ≤ ub ≤ 15. |

**Trap:** Stack underflow, `INVALID_ARG` ha ub ≥ 16 vagy ub ≥ tényleges arg count.

### 4. Stack manipuláció

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0x00` | `nop` | 1 | `(→)` | 1 | HW | Semmi. |
| `0x25` | `dup` | 1 | `(I4 → I4, I4)` | 1 | HW | TOS duplikálása. |
| `0x26` | `pop` | 1 | `(I4 →)` | 1 | HW | TOS eldobása. |

**Trap:** Stack overflow (dup), stack underflow (pop, dup).

### 5. Aritmetika (integer)

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0x58` | `add` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 + TOS, wrap. |
| `0x59` | `sub` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 − TOS, wrap. |
| `0x5A` | `mul` | 1 | `(I4, I4 → I4)` | 4–8 | μC | TOS-1 × TOS, iteratív. |
| `0x5B` | `div` | 1 | `(I4, I4 → I4)` | 16–32 | μC | TOS-1 / TOS signed. |
| `0x5D` | `rem` | 1 | `(I4, I4 → I4)` | 16–32 | μC | TOS-1 % TOS signed. |
| `0x65` | `neg` | 1 | `(I4 → I4)` | 1 | HW | −TOS. |
| `0x66` | `not` | 1 | `(I4 → I4)` | 1 | HW | ~TOS. |
| `0x5F` | `and` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 & TOS. |
| `0x60` | `or` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 \| TOS. |
| `0x61` | `xor` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 ^ TOS. |
| `0x62` | `shl` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 << (TOS & 31). |
| `0x63` | `shr` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 >> (TOS & 31), sign-extend. |
| `0x64` | `shr.un` | 1 | `(I4, I4 → I4)` | 1 | HW | TOS-1 >> (TOS & 31), zero-extend. |

**Trap:** Stack underflow, `DIV_BY_ZERO` (ha `div`/`rem` és TOS == 0), `OVERFLOW` (csak `div` esetén, ha TOS-1 == INT_MIN és TOS == -1).

### 6. Összehasonlítás

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0xFE 0x01` | `ceq` | 2 | `(I4, I4 → I4)` | 1 | HW | 1 ha TOS-1 == TOS, else 0. |
| `0xFE 0x02` | `cgt` | 2 | `(I4, I4 → I4)` | 1 | HW | 1 ha TOS-1 > TOS signed. |
| `0xFE 0x03` | `cgt.un` | 2 | `(I4, I4 → I4)` | 1 | HW | 1 ha TOS-1 > TOS unsigned. |
| `0xFE 0x04` | `clt` | 2 | `(I4, I4 → I4)` | 1 | HW | 1 ha TOS-1 < TOS signed. |
| `0xFE 0x05` | `clt.un` | 2 | `(I4, I4 → I4)` | 1 | HW | 1 ha TOS-1 < TOS unsigned. |

**Trap:** Stack underflow.

### 7. Elágazás (rövid és hosszú)

A CIL-T0 csak a **rövid** elágazásokat implementálja F3-ban (8-bit offset), hogy a hardverigényt csökkentse. A **hosszú** változatok (32-bit offset) F4-től elérhetőek.

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0x2B` | `br.s <sb>` | 2 | `(→)` | 2 | HW | PC += sb (signed 8-bit). |
| `0x2C` | `brfalse.s <sb>` | 2 | `(I4 →)` | 2 | HW | ha TOS == 0, PC += sb. |
| `0x2D` | `brtrue.s <sb>` | 2 | `(I4 →)` | 2 | HW | ha TOS != 0, PC += sb. |
| `0x2E` | `beq.s <sb>` | 2 | `(I4, I4 →)` | 2 | HW | ha TOS-1 == TOS, PC += sb. |
| `0x2F` | `bge.s <sb>` | 2 | `(I4, I4 →)` | 2 | HW | ha TOS-1 ≥ TOS, PC += sb. |
| `0x30` | `bgt.s <sb>` | 2 | `(I4, I4 →)` | 2 | HW | ha TOS-1 > TOS, PC += sb. |
| `0x31` | `ble.s <sb>` | 2 | `(I4, I4 →)` | 2 | HW | ha TOS-1 ≤ TOS, PC += sb. |
| `0x32` | `blt.s <sb>` | 2 | `(I4, I4 →)` | 2 | HW | ha TOS-1 < TOS, PC += sb. |
| `0x33` | `bne.un.s <sb>` | 2 | `(I4, I4 →)` | 2 | HW | ha TOS-1 != TOS, PC += sb. |

**Trap:** Stack underflow, `INVALID_BRANCH_TARGET` (ha a cél cím kívül esik a metódus kód-tartományán).

### 8. Hívás és visszatérés

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0x28` | `call <token>` | 5 | `(args → ret)` | 6–10 | μC | Statikus hívás. A token egy RVA-ra mutat a CODE régióban. |
| `0x2A` | `ret` | 1 | `(ret →)` | 4–6 | μC | Visszatérés a caller-hez. |

**CIL-T0 eltérés a standardtól:** Az ECMA-335-ben a `call` tokennek egy metaadat-tábla bejegyzést kell feloldania (MethodDef token). **CIL-T0-ban** nincs metaadat-walker, ezért a **call token közvetlenül egy RVA** (Relative Virtual Address) a CODE régióba. A CIL-T0 bináris formátum (lásd lent) már előre-linkelt RVA-kat tartalmaz. Ezzel a `call` tisztán gépi hívássá egyszerűsödik, és a `metadata walker` elmarad.

**Trap:** Stack underflow (nem elég arg), stack overflow, `INVALID_CALL_TARGET` (ha az RVA kívül esik a CODE régión), max call depth elérve (512).

### 9. Egyéb

| Bájt | Opkód | Hossz | Stack | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|--------|------|--------|
| `0xDD` | `break` | 1 | `(→)` | — | HW | Debug trap. Megáll és UART-on jelez. |

## Opkódok, amik a CIL-T0-ban NEM használhatók

Ha egy opkód bájt-értékkel a dekóder találkozik, ami nincs a fenti táblában, a hardver **`INVALID_OPCODE` trap**-et generál. Ez a biztonsági modell része: egy hamis bináris nem fog „véletlenszerűen" futni.

## Trap (kivétel) típusok

A CIL-T0 a következő hardveres trapokat definiálja:

| Trap # | Név | Leírás |
|--------|-----|--------|
| 0x01 | `STACK_OVERFLOW` | Eval stack eléri a max mélységet (64 slot) |
| 0x02 | `STACK_UNDERFLOW` | Pop üres stackről |
| 0x03 | `INVALID_OPCODE` | Ismeretlen opkód bájt |
| 0x04 | `INVALID_LOCAL` | Local index ≥ 16 vagy ≥ tényleges local count |
| 0x05 | `INVALID_ARG` | Arg index ≥ 16 vagy ≥ tényleges arg count |
| 0x06 | `INVALID_BRANCH_TARGET` | Branch target a metódus kód-tartományán kívül |
| 0x07 | `INVALID_CALL_TARGET` | Call RVA a CODE régión kívül |
| 0x08 | `DIV_BY_ZERO` | `div`/`rem` nulla osztóval |
| 0x09 | `OVERFLOW` | `div` INT_MIN / -1 |
| 0x0A | `CALL_DEPTH_EXCEEDED` | Hívási mélység ≥ 512 |
| 0x0B | `DEBUG_BREAK` | `break` opkód |

**Trap viselkedés F3-ban:** A CPU leáll, a trap számát és a PC-t UART-on kiírja, majd reset-re vár. **F5-ben** a trapok CIL kivételkezelőkké alakulnak át (`throw System.InvalidOperationException`, stb.).

## CIL-T0 bináris formátum

Mivel a standard PE/COFF formátum túl bonyolult a CIL-T0 minimumhoz (nem akarunk metaadat-walkert F3-ba), a CIL-T0 egy **saját, előre-linkelt bináris formátumot** használ:

```
Offset   Méret  Mező
─────────────────────────────────────────
0x00     4      Magic: "T0CL" (0x4C 0x43 0x30 0x54)
0x04     2      Version: 0x0001
0x06     2      Flags: reserved, 0
0x08     4      Entry point RVA (belépési cím a CODE régióban)
0x0C     4      Code segment size bytes
0x10     4      Data segment size bytes
0x14     4      Code CRC32
0x18     4      Data CRC32
0x1C     4      Reserved
─────────────────────────────────────────
0x20     ...    Code segment (CIL bájtok)
         ...    Data segment (konstansok)
```

**Metódus fejléc a kód szegmensen belül:**

```
Offset   Méret  Mező
─────────────────────────────────────────
0x00     1      Magic: 0xFE (standard CIL "fat" header jelző)
0x01     1      arg_count (0..15)
0x02     1      local_count (0..15)
0x03     1      max_stack (0..64)
0x04     2      code_size bytes
0x06     2      Reserved
─────────────────────────────────────────
0x08     ...    CIL opkódok
```

Egy `.t0` fájl tehát **self-contained**: egy header, majd sorban a metódusok. A `call <token>` bájtok után álló 4 bájt a cél metódus **abszolút CODE régió offszetje**, nem PE token.

### Eszköz: `ilasm-t0`

Az F1 fázisban egy kis fordító script (`tools/ilasm-t0.cs`) készül:
- Bemenet: egy `.il` szöveg ilasm formátumban, vagy Roslyn által fordított `.dll` CIL-T0 subset-tel.
- Kimenet: `.t0` bináris a fenti formátumban.
- Ellenőrzi, hogy a bemenet csak CIL-T0 opkódokat használ, és előre linkeli a `call` tokeneket RVA-kká.

## Mikrokód szekvenciák (komplex opkódok)

### `mul` (iteratív szorzás)

```
; Belépés: TOS = b, TOS-1 = a
; Kimenet: TOS-1 = a*b, TOS eldobva

μ01: RESULT ← 0
μ02: if (b == 0) goto μ07
μ03: if (b & 1) RESULT ← RESULT + a
μ04: a ← a << 1
μ05: b ← b >>u 1
μ06: goto μ02
μ07: TOS-1 ← RESULT
μ08: pop
μ09: END
```

~4–8 ciklus, b értékétől függően.

### `div` (restoring division)

```
; Belépés: TOS = divisor, TOS-1 = dividend
; Kimenet: TOS-1 = dividend / divisor

μ01: if (TOS == 0) TRAP #DIV_BY_ZERO
μ02: if (TOS-1 == INT_MIN && TOS == -1) TRAP #OVERFLOW
μ03: sign ← sign(TOS-1) ^ sign(TOS)
μ04: a ← abs(TOS-1), b ← abs(TOS)
μ05: q ← 0, r ← 0
μ06: for i in 31..0:
         r ← (r << 1) | bit(a, i)
         if (r >= b) { r ← r - b; q ← q | (1 << i) }
μ07: if sign: q ← -q
μ08: TOS-1 ← q
μ09: pop
μ10: END
```

~16–32 ciklus.

### `call`

```
; Belépés: TOS..TOS-N = argumentumok (N = callee arg_count-1)
; operand: 4 bájt abszolút RVA a CODE régióban

μ01: TARGET ← FETCH4(PC+1)                         ; 4-bájt RVA
μ02: if TARGET >= CODE_SIZE TRAP #INVALID_CALL_TARGET
μ03: read metódus fejléc @ TARGET:
        arg_count, local_count, max_stack, code_size
μ04: if SP + frame_size > STACK_LIMIT TRAP #STACK_OVERFLOW
μ05: if CALL_DEPTH >= 512 TRAP #CALL_DEPTH_EXCEEDED
μ06: SPILL TOS cache → a stack-be                  ; lokális evalstack mentése
μ07: PUSH(PC + 5)                                  ; return PC
μ08: PUSH(BP)
μ09: PUSH(SP)
μ10: BP ← SP
μ11: reserve frame_size bytes a stacken
μ12: pop args a caller stack-jéből, copy arg area-ra
μ13: zero init locals
μ14: PC ← TARGET + 8 (a fejléc után)
μ15: END
```

~6–10 ciklus, cache hit mellett.

### `ret`

```
; Belépés: TOS = visszatérési érték (opcionális)

μ01: SAVE_RET ← TOS
μ02: SP ← BP
μ03: BP ← POP()                                    ; saved BP
μ04: POP()                                          ; saved SP (eldobva, SP ← BP-ből)
μ05: RETURN_PC ← POP()
μ06: discard callee argumentumai a stackről
μ07: PC ← RETURN_PC
μ08: PUSH(SAVE_RET) ha volt
μ09: RELOAD TOS cache
μ10: END
```

~4–6 ciklus.

## Példa: Fibonacci(n)

C# forrás:

```csharp
static int Fib(int n) {
    if (n < 2) return n;
    return Fib(n - 1) + Fib(n - 2);
}
```

CIL-T0 (absztrakt assembly, ilasm-szerű):

```
.method static int32 Fib(int32 n)
{
    .maxstack 3
    .locals init (int32 V_0)     // nincs használva, de a példa kedvéért

    ldarg.0                       ; 02
    ldc.i4.2                      ; 18
    bge.s L1                      ; 2F 04
    ldarg.0                       ; 02
    ret                           ; 2A
L1:
    ldarg.0                       ; 02
    ldc.i4.1                      ; 17
    sub                           ; 59
    call Fib                      ; 28 <RVA4>
    ldarg.0                       ; 02
    ldc.i4.2                      ; 18
    sub                           ; 59
    call Fib                      ; 28 <RVA4>
    add                           ; 58
    ret                           ; 2A
}
```

**Bájtok** (a `call` tokeneket placeholderrel jelölve `??`):

```
02 18 2F 04 02 2A 02 17 59 28 ?? ?? ?? ?? 02 18 59 28 ?? ?? ?? ?? 58 2A
```

Ez **24 bájt** CIL-T0. Az ugyanez a funkció RISC-V RV32I-ben ~60 bájt. A tömörség előnye látható.

**Végrehajtás Fib(3) esetén, ciklusszám becslés:**
- Fib(3) → 1 direkt branch + 2 call, azon belül Fib(2) és Fib(1)
- Fib(2) → 1 call Fib(1) + 1 call Fib(0)
- Összes: 7 függvényhívás, ~15 összes ALU/branch művelet
- Nagyságrend: ~50–100 ciklus @ 50 MHz = ~1–2 μs
- Ugyanez x86-64 @ 3 GHz JIT-tel: ~100 ns

**Következtetés:** egy stack-gép @ 50 MHz ~10–20× lassabb egy hagyományos CPU-nál Fibonacci-ra. Az IoT use-case-ben viszont a memória fogyasztás és a kód mérete fontosabb, mint a nyers sebesség.

## Becsült hardver méret (Sky130, F3)

| Komponens | Becslés (std cell) |
|-----------|-------------------|
| Length decoder | 200 |
| Hardwired decoder (egyszerű opkódok) | 1500 |
| Microcode ROM (mul, div, call, ret) | 1200 |
| μop sequencer | 400 |
| ALU (32-bit) | 800 |
| Stack cache (4 × 32-bit + spill logic) | 1000 |
| Load/store unit | 600 |
| QSPI controller (kód+adat megosztott) | 1500 |
| UART | 300 |
| Trap / reset logika | 400 |
| Register file (PC, SP, BP, flags) | 300 |
| Glue, clock, reset | 500 |
| **Összesen** | **~8700 std cell** |

Ez **4×2 Tiny Tapeout tile**-ba komfortosan belefér (budget ~10k cell), és hagy tartalékot a verifikációs logikának.

## F1 szimulátor teszt-kötelezettségek

Az F1 C# szimulátor tesztjeinek **minden** opkódra a következőket kell lefedniük:

1. **Happy path** — érvényes input, várt output.
2. **Stack underflow** — üres stackről pop.
3. **Stack overflow** — 64 mélység fölé push.
4. **Trap feltételek** — minden trap típus kiváltható.
5. **Határérték tesztek** — pl. `add` INT_MAX + 1 (wrap), `div` INT_MIN / -1 (overflow trap), `shr` negatív értéken.
6. **Integration teszt** — egy valós program (Fibonacci, GCD, bubble sort) futtatása és eredmény-ellenőrzés.

A tesztek neve formátuma: `[ClassName]_[Opcode]_[Scenario]`, pl. `Executor_Add_WrapsAroundOnOverflow`.

## Hivatkozások

- **ECMA-335** — Common Language Infrastructure spec, 6. kiadás.
- **`docs/architecture.md`** — teljes CLI-CPU architektúra
- **`docs/roadmap.md`** — fázisok és függőségek
- **Sky130 PDK** — https://skywater-pdk.readthedocs.io/
- **Tiny Tapeout** — https://tinytapeout.com/
