# CIL-T0 — ISA Specifikáció

> English version: [ISA-CIL-T0-en.md](ISA-CIL-T0-en.md)

> Version: 1.0

Ez a dokumentum a **CIL-T0** subset-et specifikálja, amely a CLI-CPU első megvalósított utasításkészlete, és amely **Tiny Tapeout-on (F3)** gyártásra kerül.

## Áttekintés

A CIL-T0 az ECMA-335 CIL **szigorú, bitről-bitre kompatibilis részhalmaza**. Minden CIL-T0 opkód a standard CIL opkód ugyanazt a bájt-kódolást használja, ugyanazzal a stack-szemantikával. Ez azt jelenti, hogy egy CIL-T0 programot **bármely szabványos CIL disassemblerrel** (pl. `ildasm`, `dnSpy`) meg lehet nézni, és **bármely szabványos CIL runtime** (CoreCLR, Mono, nanoFramework) futtatni tudná — de ez fordítva nem igaz: egy CoreCLR alatt futó tetszőleges .NET program nem fog futni CIL-T0-n, mert a legtöbb valódi program objektumokat, stringeket, virtuális hívásokat, kivételeket használ, amiket a CIL-T0 **nem implementál**.

### Célkitűzések

1. **Minimális** — elférjen egy Tiny Tapeout 12–16 tile budget-ben (~12K–16K gate, ~1K gate/tile).
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

A CIL-T0-ra a `docs/architecture-hu.md` memória modelljének **szűkített változata** érvényes:

| Régió | Cím tartomány | Tartalom | Backing | Méret (F3) |
|-------|---------------|----------|---------|------------|
| **CODE** | `0x0000_0000` – `0x000F_FFFF` | CIL bytecode (.cil-t0 bináris formátum) | QSPI Flash | 1 MB |
| **DATA** | `0x1000_0000` – `0x1003_FFFF` | `.data` szegmens (konstansok, statikus mezők) | QSPI Flash / PSRAM | 256 KB |
| **STACK** | `0x2000_0000` – `0x2000_3FFF` | Eval stack + lokálisok + arg-ok + frame-ek | QSPI PSRAM | 16 KB |
| **MMIO** | `0xF000_0000` – `0xFFFF_FFFF` | UART, **Mailbox**, GPIO, timer | On-chip | — |

**Nincs HEAP** a CIL-T0-ban, mert nincs `newobj`/`newarr`.

### MMIO régió részletes térképe

A `0xF000_0000` kezdetű MMIO régió blokkokra van osztva. F3-ban csak az UART és a Mailbox van implementálva, a többi helyfoglalás a jövő fázisokra:

| Cím | Méret | Blokk | Fázis |
|-----|-------|-------|-------|
| `0xF000_0000` – `0xF000_00FF` | 256 B | UART (TX/RX/status/control) | F3 |
| `0xF000_0100` – `0xF000_01FF` | 256 B | **Mailbox (inbox + outbox)** | **F3** |
| `0xF000_0200` – `0xF000_02FF` | 256 B | GPIO (reserved) | F4 |
| `0xF000_0300` – `0xF000_03FF` | 256 B | Timer / clock (reserved) | F4 |
| `0xF000_0400` – `0xFFFF_FFFF` | — | Reserved | F5+ |

## Mailbox interface (F3)

A CLI-CPU **már az F3 Tiny Tapeout chipen** tartalmaz egy **32-bites mailbox interfészt**, amely lehetővé teszi, hogy a chip **üzeneteket kapjon** a külvilágból és **üzeneteket küldjön** vissza, eseményvezérelt módon. Ez az első olyan interfész, ami a **cognitive fabric** pozicionálást megalapozza — F3 egymagos, de már a „hálózatba illeszthető csomópont" szerepét tölti be.

### Tervezési elvek

1. **Nincs új opkód.** A mailbox az MMIO régióban él, a meglévő `ldind.i4` (load indirect) és `stind.i4` (store indirect) opkódokkal érhető el. Ezzel a CIL-T0 opkód-készlet **48 opkódon marad**, és szigorúan ECMA-335 kompatibilis.
2. **Szimmetrikus inbox és outbox.** Mindkét FIFO **8 mélységű**, 32-bit széles bejegyzésekkel. Ez 8 „spike" burst-öt tud buffer-elni mindkét irányban üzenetvesztés nélkül.
3. **F3-ban külső bridge** (UART/FTDI) közvetíti az üzeneteket a host és a chip között. **F4-ben** ugyanezek a regiszterek a hardveres router-re csatlakoznak, és a `target` mező kap értelmet (cél core index).
4. **Trap támogatás.** Ha a program megpróbál üres inbox-ról olvasni vagy tele outbox-ra írni, a hardver `STATUS` regiszter-en jelzi; opcionálisan **interrupt/wake-from-sleep** is generálható (F4+).

### Regiszter térkép

| Cím | Reg | R/W | Leírás |
|-----|-----|-----|--------|
| `0xF000_0100` | `MB_STATUS` | R | **Status**: bit 0 = inbox has message, bit 1 = inbox full, bit 2 = outbox empty, bit 3 = outbox full, bit 4 = inbox overflow sticky, bit 5 = outbox overflow sticky, bit 6–7 = reserved, bit 8–11 = inbox count (0–8), bit 12–15 = outbox count (0–8) |
| `0xF000_0104` | `MB_DATA` | R/W | **Data**: olvasás → pop az inbox FIFO tetejéről; írás → push az outbox FIFO aljára |
| `0xF000_0108` | `MB_TARGET` | R/W | **Target**: az **utolsó** outbox push célcímzettje. F3-ban: 0 = külső (UART bridge), minden más érték reserved. F4+: a cél core index (0–N–1) |
| `0xF000_010C` | `MB_SOURCE` | R | **Source**: az **utolsó** inbox pop forrása. F3-ban mindig 0 (külső). F4+: a küldő core index |
| `0xF000_0110` | `MB_CTRL` | R/W | **Control**: bit 0 = clear inbox overflow sticky, bit 1 = clear outbox overflow sticky, bit 2 = enable inbox-wake interrupt (F4+), bit 3 = flush outbox (resync F3 UART bridge), bit 4–31 = reserved |
| `0xF000_0114` – `0xF000_01FF` | — | — | Reserved |

### Használati példa CIL-T0-ban

Ez a minta egy egyszerű „echo neuron": vár egy bejövő üzenetet, hozzáad 1-et, és visszaküldi.

```
; receive_add_send() — végtelen ciklus
.method static void receive_add_send()
{
    .maxstack 3
    .locals init (int32 V_msg)

POLL:
    ldc.i4      0xF0000100                 ; MB_STATUS cím
    ldind.i4                                ; status érték a TOS-ra
    ldc.i4.1                                ; bit 0 maszk (inbox has message)
    and
    brfalse.s   POLL                        ; ha nincs üzenet, vár

    ; --- üzenet olvasás ---
    ldc.i4      0xF0000104                 ; MB_DATA cím
    ldind.i4                                ; pop inbox → TOS
    ldc.i4.1
    add                                     ; +1
    stloc.0                                 ; V_msg = beérkezett+1

    ; --- target beállítás (F3: 0 = külső) ---
    ldc.i4      0xF0000108                 ; MB_TARGET cím
    ldc.i4.0
    stind.i4

    ; --- outbox push ---
    ldc.i4      0xF0000104                 ; MB_DATA cím
    ldloc.0
    stind.i4                                ; push outbox

    br.s        POLL
}
```

Ez a néhány soros CIL-T0 **már F3 szilíciumon futtatható**, és **bemutatja a cognitive fabric koncepciót**: egy külső teszt-host UART-on üzenetet küld, a chip feldolgozza CIL programmal, és visszaküldi. Ez az első „kezedben tartható, hálózatba kapcsolt neuron" demó.

### Trap-kiegészítés

A jelenlegi trap-listához (lásd fentebb) F3-ban hozzáadódik egy opcionális trap:

| Trap # | Név | Leírás |
|--------|-----|--------|
| 0x0C | `MAILBOX_OVERFLOW` | Akkor, ha a program írást próbál tele outbox-ra és a `MB_CTRL` nem engedélyezi a drop viselkedést (F4+ beállítható) |

F3-ban alapértelmezésben **a túlcsordulás csak sticky bit-et állít**, nem trap-el — a mintakód ezt `MB_STATUS` polling-gal kezelheti.

### Hardveres méret-becslés

A mailbox blokk becsült mérete Sky130-on:

| Komponens | Std cell |
|-----------|----------|
| 8 × 32-bit inbox FIFO | ~120 |
| 8 × 32-bit outbox FIFO | ~120 |
| Status/Ctrl regiszterek + dekódolás | ~80 |
| UART bridge (F3) | ~50 (már meglévő UART-ból megosztva) |
| **Mailbox összesen** | **~370** |

Ez **~4% növekedés** a CIL-T0 ~8700 std cell budget-jén, és **elfér** a 12–16 Tiny Tapeout tile konfigurációban. **A teljes becsült F3 méret most ~9100 std cell.**

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
- **μstep** — microcode ROM lépésszám (`o_nsteps`): hány ROM-lookup szükséges a sequencer-ben. Ez a szám **determinisztikus és cocotb-vel tesztelt** (`rtl/tb/test_microcode.py`).
- **Ciklus** — teljes végrehajtási idő órajelciklusban @ 50 MHz, TOS cache hit mellett. Az `μstep + ALU latencia + pipeline flush` összege. A `mul`/`div`/`rem` az ALU belső iteratív logikája miatt hosszabb. Branch opkódoknál a „taken" eset +1 pipeline flush ciklust ad.
- **Dek.** — `HW` = hardwired (1 μstep), `μC` = mikrokódolt (>1 μstep vagy ALU iteráció).
- **Trap** — a lehetséges hardveres trap feltételek.

### 1. Konstans betöltés

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x14` | `ldnull` | 1 | `(→ I4)` | 1 | 1 | HW | Push 0-t (null mint int). |
| `0x15` | `ldc.i4.m1` | 1 | `(→ I4)` | 1 | 1 | HW | Push -1. |
| `0x16` | `ldc.i4.0` | 1 | `(→ I4)` | 1 | 1 | HW | Push 0. |
| `0x17` | `ldc.i4.1` | 1 | `(→ I4)` | 1 | 1 | HW | Push 1. |
| `0x18` | `ldc.i4.2` | 1 | `(→ I4)` | 1 | 1 | HW | Push 2. |
| `0x19` | `ldc.i4.3` | 1 | `(→ I4)` | 1 | 1 | HW | Push 3. |
| `0x1A` | `ldc.i4.4` | 1 | `(→ I4)` | 1 | 1 | HW | Push 4. |
| `0x1B` | `ldc.i4.5` | 1 | `(→ I4)` | 1 | 1 | HW | Push 5. |
| `0x1C` | `ldc.i4.6` | 1 | `(→ I4)` | 1 | 1 | HW | Push 6. |
| `0x1D` | `ldc.i4.7` | 1 | `(→ I4)` | 1 | 1 | HW | Push 7. |
| `0x1E` | `ldc.i4.8` | 1 | `(→ I4)` | 1 | 1 | HW | Push 8. |
| `0x1F` | `ldc.i4.s <sb>` | 2 | `(→ I4)` | 1 | 1 | HW | Push signed-extended 8-bit immediate. |
| `0x20` | `ldc.i4 <i4>` | 5 | `(→ I4)` | 1 | 1 | HW | Push 32-bit immediate. |

**Trap:** Stack overflow (ha az eval stack eléri a max 64 mélységet).

### 2. Lokális változó hozzáférés

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x06` | `ldloc.0` | 1 | `(→ I4)` | 1 | 1 | HW | Push local[0]. |
| `0x07` | `ldloc.1` | 1 | `(→ I4)` | 1 | 1 | HW | Push local[1]. |
| `0x08` | `ldloc.2` | 1 | `(→ I4)` | 1 | 1 | HW | Push local[2]. |
| `0x09` | `ldloc.3` | 1 | `(→ I4)` | 1 | 1 | HW | Push local[3]. |
| `0x11` | `ldloc.s <ub>` | 2 | `(→ I4)` | 1 | 1 | HW | Push local[ub], 0 ≤ ub ≤ 15. |
| `0x0A` | `stloc.0` | 1 | `(I4 →)` | 1 | 1 | HW | Pop → local[0]. |
| `0x0B` | `stloc.1` | 1 | `(I4 →)` | 1 | 1 | HW | Pop → local[1]. |
| `0x0C` | `stloc.2` | 1 | `(I4 →)` | 1 | 1 | HW | Pop → local[2]. |
| `0x0D` | `stloc.3` | 1 | `(I4 →)` | 1 | 1 | HW | Pop → local[3]. |
| `0x13` | `stloc.s <ub>` | 2 | `(I4 →)` | 1 | 1 | HW | Pop → local[ub], 0 ≤ ub ≤ 15. |

**Trap:** Stack underflow (üres stackről pop), Local index out of range (ub ≥ 16 → `INVALID_LOCAL` trap).

### 3. Argumentum hozzáférés

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x02` | `ldarg.0` | 1 | `(→ I4)` | 1 | 1 | HW | Push arg[0]. |
| `0x03` | `ldarg.1` | 1 | `(→ I4)` | 1 | 1 | HW | Push arg[1]. |
| `0x04` | `ldarg.2` | 1 | `(→ I4)` | 1 | 1 | HW | Push arg[2]. |
| `0x05` | `ldarg.3` | 1 | `(→ I4)` | 1 | 1 | HW | Push arg[3]. |
| `0x0E` | `ldarg.s <ub>` | 2 | `(→ I4)` | 1 | 1 | HW | Push arg[ub], 0 ≤ ub ≤ 15. |
| `0x10` | `starg.s <ub>` | 2 | `(I4 →)` | 1 | 1 | HW | Pop → arg[ub], 0 ≤ ub ≤ 15. |

**Trap:** Stack underflow, `INVALID_ARG` ha ub ≥ 16 vagy ub ≥ tényleges arg count.

### 4. Stack manipuláció

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x00` | `nop` | 1 | `(→)` | 1 | 1 | HW | Semmi. |
| `0x25` | `dup` | 1 | `(I4 → I4, I4)` | 1 | 1 | HW | TOS duplikálása. |
| `0x26` | `pop` | 1 | `(I4 →)` | 1 | 1 | HW | TOS eldobása. |

**Trap:** Stack overflow (dup), stack underflow (pop, dup).

### 5. Aritmetika (integer)

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x58` | `add` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 + TOS, wrap. |
| `0x59` | `sub` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 − TOS, wrap. |
| `0x5A` | `mul` | 1 | `(I4, I4 → I4)` | 1 | 4–8 | μC | TOS-1 × TOS. ALU iteratív szorzó (shift-add), 3–7 ciklus ALU latencia. |
| `0x5B` | `div` | 1 | `(I4, I4 → I4)` | 1 | 16–32 | μC | TOS-1 / TOS signed. ALU restoring osztó (32 iteráció), 15–31 ciklus ALU latencia. |
| `0x5D` | `rem` | 1 | `(I4, I4 → I4)` | 1 | 16–32 | μC | TOS-1 % TOS signed. ALU restoring maradék, 15–31 ciklus ALU latencia. |
| `0x65` | `neg` | 1 | `(I4 → I4)` | 1 | 1 | HW | −TOS. |
| `0x66` | `not` | 1 | `(I4 → I4)` | 1 | 1 | HW | ~TOS. |
| `0x5F` | `and` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 & TOS. |
| `0x60` | `or` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 \| TOS. |
| `0x61` | `xor` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 ^ TOS. |
| `0x62` | `shl` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 << (TOS & 31). |
| `0x63` | `shr` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 >> (TOS & 31), sign-extend. |
| `0x64` | `shr.un` | 1 | `(I4, I4 → I4)` | 1 | 1 | HW | TOS-1 >> (TOS & 31), zero-extend. |

**Trap:** Stack underflow, `DIV_BY_ZERO` (ha `div`/`rem` és TOS == 0), `OVERFLOW` (csak `div` esetén, ha TOS-1 == INT_MIN és TOS == -1).

### 6. Összehasonlítás

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0xFE 0x01` | `ceq` | 2 | `(I4, I4 → I4)` | 1 | 1 | HW | 1 ha TOS-1 == TOS, else 0. |
| `0xFE 0x02` | `cgt` | 2 | `(I4, I4 → I4)` | 1 | 1 | HW | 1 ha TOS-1 > TOS signed. |
| `0xFE 0x03` | `cgt.un` | 2 | `(I4, I4 → I4)` | 1 | 1 | HW | 1 ha TOS-1 > TOS unsigned. |
| `0xFE 0x04` | `clt` | 2 | `(I4, I4 → I4)` | 1 | 1 | HW | 1 ha TOS-1 < TOS signed. |
| `0xFE 0x05` | `clt.un` | 2 | `(I4, I4 → I4)` | 1 | 1 | HW | 1 ha TOS-1 < TOS unsigned. |

**Trap:** Stack underflow.

### 7. Elágazás (rövid és hosszú)

A CIL-T0 csak a **rövid** elágazásokat implementálja F3-ban (8-bit offset), hogy a hardverigényt csökkentse. A **hosszú** változatok (32-bit offset) F4-től elérhetőek.

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x2B` | `br.s <sb>` | 2 | `(→)` | 1 | 1+1 | HW | PC += sb (signed 8-bit). +1 pipeline flush. |
| `0x2C` | `brfalse.s <sb>` | 2 | `(I4 →)` | 1 | 1/1+1 | HW | ha TOS == 0, PC += sb. Taken: +1 flush. |
| `0x2D` | `brtrue.s <sb>` | 2 | `(I4 →)` | 1 | 1/1+1 | HW | ha TOS != 0, PC += sb. Taken: +1 flush. |
| `0x2E` | `beq.s <sb>` | 2 | `(I4, I4 →)` | 1 | 1/1+1 | HW | ha TOS-1 == TOS, PC += sb. ALU ceq + cond. |
| `0x2F` | `bge.s <sb>` | 2 | `(I4, I4 →)` | 1 | 1/1+1 | HW | ha TOS-1 ≥ TOS, PC += sb. ALU clt + !cond. |
| `0x30` | `bgt.s <sb>` | 2 | `(I4, I4 →)` | 1 | 1/1+1 | HW | ha TOS-1 > TOS, PC += sb. ALU cgt + cond. |
| `0x31` | `ble.s <sb>` | 2 | `(I4, I4 →)` | 1 | 1/1+1 | HW | ha TOS-1 ≤ TOS, PC += sb. ALU cgt + !cond. |
| `0x32` | `blt.s <sb>` | 2 | `(I4, I4 →)` | 1 | 1/1+1 | HW | ha TOS-1 < TOS, PC += sb. ALU clt + cond. |
| `0x33` | `bne.un.s <sb>` | 2 | `(I4, I4 →)` | 1 | 1/1+1 | HW | ha TOS-1 != TOS, PC += sb. ALU ceq + !cond. |

**Trap:** Stack underflow, `INVALID_BRANCH_TARGET` (ha a cél cím kívül esik a metódus kód-tartományán).

### 8. Hívás és visszatérés

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x28` | `call <token>` | 5 | `(args → ret)` | 2 | 2+N | μC | Statikus hívás. 2 ROM lépés + N arg pop (sequencer loop). N = callee arg_count. |
| `0x2A` | `ret` | 1 | `(ret →)` | 2 | 2 | μC | Visszatérés. Step 0: feltételes pop (cond_pop), step 1: frame_pop/halt + PC=ret. |

**CIL-T0 eltérés a standardtól:** Az ECMA-335-ben a `call` tokennek egy metaadat-tábla bejegyzést kell feloldania (MethodDef token). **CIL-T0-ban** nincs metaadat-walker, ezért a **call token közvetlenül egy RVA** (Relative Virtual Address) a CODE régióba. A CIL-T0 bináris formátum (lásd lent) már előre-linkelt RVA-kat tartalmaz. Ezzel a `call` tisztán gépi hívássá egyszerűsödik, és a `metadata walker` elmarad.

**Trap:** Stack underflow (nem elég arg), stack overflow, `INVALID_CALL_TARGET` (ha az RVA kívül esik a CODE régión), max call depth elérve (512).

### 9. Indirekt memóriahozzáférés

A CIL-T0 a 32-bites integer indirekt load/store opkódokat implementálja, amelyek a `DATA` és `MMIO` régiókat (illetve az F1 szimulátorban a megadott data memory tömböt) érik el. A bájt-értékek **szigorúan az ECMA-335 Partition III** szerintiek, így egy szabványos CIL disassembler is felismeri őket.

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0x4A` | `ldind.i4` | 1 | `(I4 → I4)` | 1 | 1–3 | HW | TOS = cím; pop, olvas egy 32-bit LE int-et a data memory-ból, push az eredményt. +QSPI/PSRAM latencia. |
| `0x54` | `stind.i4` | 1 | `(I4, I4 →)` | 1 | 1–3 | HW | TOS = érték, TOS-1 = cím; pop érték, pop cím, ír egy 32-bit LE int-et a data memory-ba. +QSPI/PSRAM latencia. |

**Trap:** Stack underflow, `INVALID_MEMORY_ACCESS` (ha a cím a data memory tartományán kívül esik vagy nincs data memory rendelve a CPU-hoz). Ez a trap az F2 RTL-ben a hardveres memory controller hibájának felel meg.

### 10. Egyéb

| Bájt | Opkód | Hossz | Stack | μstep | Ciklus | Dek. | Leírás |
|------|-------|-------|-------|-------|--------|------|--------|
| `0xDD` | `break` | 1 | `(→)` | 1 | 1 | HW | Debug trap. Megáll és UART-on jelez. |

**CIL-T0 eltérés a standardtól:** Az ECMA-335-ben a `break` opkód byte értéke `0x01`. A CIL-T0 viszont a `0xDD`-t használja, mert a `0x01` az F2/F3 dekóder szempontjából a `nop` (`0x00`) szomszédja, és szándékosan a "ritka, debug-only" tartományba toltuk, hogy a forró opkódoktól dekóderben elválasztható legyen. Ez egy **tudatos eltérés**, amelyet a CIL-T0 → standard CIL fordítók (`ilasm-t0`) automatikusan kezelnek.

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
| 0x0C | `INVALID_MEMORY_ACCESS` | `ldind.i4` / `stind.i4` cím a data memory tartományán kívül vagy nincs data memory |

**Trap viselkedés F3-ban:** A CPU leáll, a trap számát és a PC-t UART-on kiírja, majd reset-re vár. **F5-ben** a trapok CIL kivételkezelőkké alakulnak át (`throw System.InvalidOperationException`, stb.).

### Trap sorrend (precedencia)

Több trap-feltétel egyidejű teljesülése esetén a CIL-T0 hardver és a szimulátor a következő, **rögzített** sorrendben dönt. Ez a sorrend visszafelé kompatibilis az F2 cocotb testbench-csel.

1. **`INVALID_OPCODE`** — a dekóder először az opkód érvényességét és az operandus jelenlétét ellenőrzi (truncated operand is `INVALID_OPCODE`-ot ad). Ha ez a trap aktiválódik, semmilyen másik feltételt nem értékelünk ki, mert még az utasítás logikai dekódolása sem fejeződött be.
2. **Index-ellenőrzések (`INVALID_LOCAL`, `INVALID_ARG`)** — a `stloc.s` / `starg.s` / `ldloc.s` / `ldarg.s` opkódoknál az index ellenőrzése **megelőzi** a stack-hozzáférést. Tehát ha az index érvénytelen ÉS a stack üres egyszerre, akkor `INVALID_LOCAL` (vagy `INVALID_ARG`) az aktiváló trap, NEM `STACK_UNDERFLOW`.
3. **`STACK_UNDERFLOW` / `STACK_OVERFLOW`** — az operandusok stack-ről való kivétele után, illetve a push-olás előtt értékeljük.
4. **Aritmetika trap-ek (`DIV_BY_ZERO`, `OVERFLOW`)** — a `div`/`rem` esetén csak az operandusok sikeres kivétele után ellenőrizzük az osztó nullaértékét, illetve az `INT_MIN / -1` overflow-t.
5. **`INVALID_BRANCH_TARGET`** — a feltételes branch-ek esetén csak a feltétel kiértékelése után, és csak ha a branch ténylegesen aktivizálódik. Egy nem-aktiváló branch sose dob `INVALID_BRANCH_TARGET`-et, még akkor sem, ha a target érvénytelen lenne.

**Index validation precedes stack access; invalid index takes precedence over stack underflow.**

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

## F1 referencia implementációs megjegyzések

Az F1 C# szimulátor (`src/CilCpu.Sim`) az ebben a dokumentumban rögzített viselkedést **megfigyelhetően ekvivalens** módon valósítja meg, de a belső adatszerkezetekben néhány tudatos eltérést alkalmaz. Ezek **nem szabványsértések**, mert a CIL-T0 ISA a megfigyelhető viselkedést (stack érték, trap, return value, PC) specifikálja, nem pedig a belső megvalósítást. Az F2 RTL-nek továbbra is választása lehet a két megközelítés között, amíg a viselkedés bit-pontosan megegyezik a szimulátoréval.

### Per-frame evaluation stack

A `call` mikrokódja (lásd fentebb) a "SPILL TOS cache → a stack-be" lépést írja, ami **megosztott** evaluation stack modellt sugall: minden frame egy közös 64 mélységű stack-en dolgozik, és call-nál a callee az aktuális SP felett kap új tartományt.

Az **F1 referencia szimulátor ezzel szemben per-frame evaluation stacket használ**: minden `TFrame` saját 64 mélységű `TEvaluationStack`-et kap. A `call` egyszerűen pop-olja az argumentumokat a caller eval stackjéből, és a callee egy üres eval stack-kel indul. A `ret` a callee eval stack tetejéről veszi a return value-t és push-olja a caller-éra.

**Megfigyelhető ekvivalencia.** A két modell végrehajtási nyoma (PC, frame argumentumok, lokálisok, return value, trap pillanat) **bit-pontosan megegyezik** minden olyan programra, amely nem támaszkodik a caller eval stackjének TOS-on túli (azaz nem-argumentum) értékeinek "látszására" a callee-ban — ami egyébként szabványsértő CIL is lenne. A spec mindkét viselkedést megengedi.

**Trap szigorúbb a per-frame modellben.** A `STACK_OVERFLOW` trap a per-frame szimulátorban hamarabb sülhet ki, mint a megosztott modellben: egy adott frame eval stackje **önmagában** legfeljebb 64 mély lehet, nem pedig "ami a megosztott 64-ből még megmaradt". Ez **szigorúbb**, nem lazább, ezért minden, ami a szimulátoron lefut, az F2 megosztott modellen is le fog futni.

**F2 RTL döntés.** Az F2 RTL implementáció szabadon választhat a két modell között. Ha a megosztott megközelítést választja (a mikrokód-szöveg szerint), a cocotb golden vector test bench-ekben a `STACK_OVERFLOW` precedenciát finomhangolhatóvá kell tenni egy konfigurációs flag mögé, hogy a két aranypélda végrehajtási nyom továbbra is megegyezzen.

### `Peek` API a CPU-n

A `TCpu.Peek(int)` egy debug/teszt API, amely a CPU jelenlegi top-frame eval stackjéből olvas. Üres call stack esetén (azaz `Execute` hívása előtt) `InvalidOperationException`-t dob, **nem CIL trap**-et, mert a Peek nem egy CIL-T0 opkód művelete. Ez a viselkedés rögzített és tesztelt.

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

Ez **12–16 Tiny Tapeout tile**-ba komfortosan belefér (~1K gate/tile, ~12K–16K gate budget), és hagy tartalékot a routing overhead-re és verifikációs logikának.

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
- **`docs/architecture-hu.md`** — teljes CLI-CPU architektúra
- **`docs/roadmap-hu.md`** — fázisok és függőségek
- **Sky130 PDK** — https://skywater-pdk.readthedocs.io/
- **Tiny Tapeout** — https://tinytapeout.com/

---

## Órajelciklus modell (F2.2b)

A CIL-T0 utasítások végrehajtási idejét három tényező határozza meg:

1. **μstep** — a microcode ROM lépésszáma (`o_nsteps`). Ez **determinisztikus** és a `rtl/tb/test_microcode.py` cocotb tesztekkel verifikált. A legtöbb opkód 1 μstep; a `call` és `ret` 2 μstep.

2. **ALU latencia** — az ALU belső iteratív logikájának ciklusigénye. Az egyszerű műveletek (add, sub, and, or, xor, shl, shr, neg, not, ceq, cgt, clt) 0 extra ciklust adnak (kombinációs ALU). A `mul` 3–7 ciklust ad (shift-add szorzó), a `div`/`rem` 15–31 ciklust (restoring osztó, 32 iteráció).

3. **Pipeline és memória hatás** — branch opkódoknál a „taken" eset +1 pipeline flush ciklust ad. Az `ldind.i4`/`stind.i4` opkódoknál a QSPI/PSRAM latencia +0–2 ciklust adhat (on-chip SRAM: 0; QSPI flash: 1–2).

**Képlet:** `Σ ciklus = μstep + ALU latencia + pipeline flush + memória latencia`

### Összefoglaló táblázat (48 opkód)

| Kategória | Opkódok | μstep | Σ ciklus | Megjegyzés |
|-----------|---------|-------|----------|------------|
| Konstans load | ldnull, ldc.i4.* | 1 | 1 | — |
| Lokális/arg load | ldloc.*, ldarg.* | 1 | 1 | TOS cache hit |
| Lokális/arg store | stloc.*, starg.s | 1 | 1 | — |
| Stack manip. | nop, dup, pop | 1 | 1 | — |
| ALU egyszerű | add, sub, and, or, xor, shl, shr, shr.un, neg, not | 1 | 1 | kombinációs ALU |
| ALU szorzás | mul | 1 | 4–8 | iteratív shift-add |
| ALU osztás | div, rem | 1 | 16–32 | restoring divider |
| Összehasonlítás | ceq, cgt, cgt.un, clt, clt.un | 1 | 1 | — |
| Branch feltétlen | br.s | 1 | 1+1 | +1 pipeline flush |
| Branch 1-értékű | brfalse.s, brtrue.s | 1 | 1/1+1 | +1 ha taken |
| Branch 2-értékű | beq.s..bne.un.s | 1 | 1/1+1 | ALU cmp + cond |
| Indirekt load | ldind.i4 | 1 | 1–3 | +QSPI/PSRAM lat. |
| Indirekt store | stind.i4 | 1 | 1–3 | +QSPI/PSRAM lat. |
| Call | call | 2 | 2+N | N = arg count |
| Return | ret | 2 | 2 | cond_pop + frame |
| Debug | break | 1 | 1 | trap, CPU áll |

**Forrás:** `rtl/src/cilcpu_microcode.v` — a μstep értékek az `o_nsteps` kimenetből olvashatók, és a `rtl/tb/test_microcode.py` cocotb tesztekkel vannak verifikálva (24 teszt, 0 hiba).

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.1 | 2026-04-17 | F2.2b μstep + órajelciklus dokumentáció minden opkódhoz |
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
