# CLI-CPU — Architektúra Áttekintés

Ez a dokumentum a CLI-CPU **mikroarchitektúráját** írja le magas szinten: a stack-gép modellt, a pipeline-t, a memória térképet, a dekódolási stratégiát, a GC és kivételkezelés hardveres támogatását, valamint az elődprojektek (picoJava, Jazelle, Transmeta) közül átvett technikákat.

> **Megjegyzés:** Ez az architektúra fokozatosan épül fel az F0–F6 fázisokban. Az itt leírt teljes funkciókészlet **F6-ra** készül el (eFabless ChipIgnite). A **Tiny Tapeout (F3)** csak a CIL-T0 subset-et valósítja meg, amit egy külön dokumentum (`ISA-CIL-T0.md`) ír le.

## Tervezési alapelvek

1. **A CIL a natív ISA.** A CPU fetch egysége közvetlenül a Roslyn/ilasm által kibocsátott CIL bájtokat olvassa. Nincs JIT, nincs AOT, nincs interpreter réteg. A CIL bájtok a memóriában **változatlanok** maradnak.
2. **Stack-gép, Top-of-Stack Caching-gel.** Kifelé tiszta ECMA-335 evaluation stack; belül a stack felső 4–8 eleme fizikai regiszterekben él, a többi RAM-ba spillel. Ez a picoJava és a HotSpot tanulsága.
3. **Harvard modell külső memóriával.** Külön QSPI kód-flash és külön QSPI PSRAM adatnak. A chip-en belüli SRAM kizárólag gyorsítótár.
4. **Hibrid dekódolás.** Egyszerű opkódok (~75%) közvetlen hardverrel, 1 ciklus. Komplex opkódok (~25%) mikrokód ROM-on keresztül, több ciklus.
5. **Managed memory safety a szilíciumban.** A GC write barrier, a stack bounds check, a branch target validation, a type check — mind hardveres mellékhatás, nem szoftveres runtime feladat.
6. **IoT-first energia profil.** Agresszív clock-gating és power-gating. Minden fel nem használt egység hideg.

## Blokk diagram (teljes CLI-CPU, F6 cél)

```
                         ┌─────────────────────────────────────────┐
                         │               CLI-CPU                   │
                         │                                         │
  ┌──────────────┐       │  ┌────────────────────────────────────┐ │
  │ QSPI Flash   │◄──────┼─►│         I$  (CIL bytecode cache)   │ │
  │ (kód)        │       │  │         4 KB, 2-way associative    │ │
  └──────────────┘       │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  Prefetch Buffer (16 bájt)         │ │
                         │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  Length Decoder                    │ │
                         │  │  (1. bájt → teljes opkód hossz)    │ │
                         │  └──────────────┬─────────────────────┘ │
                         │                 │                       │
                         │                 ▼                       │
                         │  ┌────────────────────────────────────┐ │
                         │  │  μop Cache (256 × 8 μop) ◄────────┐│ │
                         │  │  hit? ──► kikapcsolt dekóder      ││ │
                         │  └──────────────┬─────────────────┬──┘│ │
                         │                 │ miss            │   │ │
                         │                 ▼                 │   │ │
                         │  ┌──────────────────────┐        │   │ │
                         │  │  Hardwired Decoder   │──┐     │   │ │
                         │  │  (triviális opkódok) │  │     │   │ │
                         │  └──────────────────────┘  │     │   │ │
                         │  ┌──────────────────────┐  │     │   │ │
                         │  │  Microcode ROM/SRAM  │──┤     │   │ │
                         │  │  (komplex opkódok)   │  │     │   │ │
                         │  └──────────────────────┘  │     │   │ │
                         │                            ▼     │   │ │
                         │  ┌────────────────────────────┐  │   │ │
                         │  │    μop Sequencer           │──┘   │ │
                         │  └──────────────┬─────────────┘      │ │
                         │                 │                    │ │
                         │                 ▼                    │ │
                         │  ┌────────────────────────────────┐  │ │
                         │  │        Execute Stage           │  │ │
                         │  │  ┌──────┐ ┌──────┐ ┌────────┐  │  │ │
                         │  │  │ ALU  │ │ FPU  │ │ Branch │  │  │ │
                         │  │  │32/64 │ │R4/R8 │ │  Unit  │  │  │ │
                         │  │  └──────┘ └──────┘ └────────┘  │  │ │
                         │  │  ┌───────────────────────────┐ │  │ │
                         │  │  │   Stack Cache (TOS..TOS-7)│ │  │ │
                         │  │  └───────────────────────────┘ │  │ │
                         │  │  ┌───────────────────────────┐ │  │ │
                         │  │  │   Shadow RegFile (exc)    │ │  │ │
                         │  │  └───────────────────────────┘ │  │ │
                         │  └──────────────┬─────────────────┘  │ │
                         │                 │                    │ │
                         │                 ▼                    │ │
                         │  ┌────────────────────────────────┐  │ │
                         │  │   Load/Store Unit              │  │ │
                         │  │   + Gated Store Buffer         │  │ │
                         │  │   + GC Write Barrier           │  │ │
                         │  └──────────────┬─────────────────┘  │ │
                         │                 │                    │ │
                         │                 ▼                    │ │
                         │  ┌────────────────────────────────┐  │ │
                         │  │ D$ (heap + locals + eval-stack) │  │ │
                         │  │ 4 KB, kártyatábla bitekkel     │  │ │
                         │  └──────────────┬─────────────────┘  │ │
                         │                 │                    │ │
  ┌──────────────┐       │                 ▼                    │ │
  │ QSPI PSRAM   │◄──────┼───────── Memory Controller ──────────┘ │
  │ (heap+stack) │       │                                        │
  └──────────────┘       │                                        │
                         │  ┌────────────────────────────────┐    │
                         │  │   Metadata Walker Coproc.      │    │
                         │  │   (PE/COFF tábla feloldás)     │    │
                         │  └────────────────────────────────┘    │
                         │  ┌────────────────────────────────┐    │
                         │  │   GC Assist Unit               │    │
                         │  │   (bump alloc, card mark)      │    │
                         │  └────────────────────────────────┘    │
                         │  ┌────────────────────────────────┐    │
                         │  │   Exception Unwinder           │    │
                         │  │   (shadow regfile rollback)    │    │
                         │  └────────────────────────────────┘    │
                         └─────────────────────────────────────────┘
```

## Pipeline

A CLI-CPU **klasszikus 5-fokozatú in-order pipeline-t** használ, a stack-gép szemantikához igazítva:

```
 IF  → FETCH:    Prefetch bufferből bájtok, I$-hez QSPI backing
 ID  → DECODE:   Length decoder + hardwired/mikrokód elágazás
 EX  → EXECUTE:  ALU/FPU/Branch, stack cache-en dolgozik
 MEM → MEMORY:   Load/store, gated buffer, GC barrier
 WB  → WRITEBACK: Stack cache frissítés, PC update
```

Nincs superscalar, nincs out-of-order végrehajtás (F0–F6). Ez két okból tudatos döntés:

1. **Terület:** Sky130-on egy OoO mag magasabb terület-büdzsét igényelne, mint amire számíthatunk még ChipIgnite-on is. Az in-order pipeline kompakt.
2. **Determinizmus:** IoT és biztonsági profil egyaránt determinisztikus végrehajtási időt igényel. OoO és spekuláció Spectre-szerű oldalcsatornákat nyit, amit egy „biztonság-first" CIL CPU-n kerülni akarunk.

A **μop cache** viszont jelentősen csökkenti a dekódolási overhead-et a forró loopokon, tehát az effektív IPC ~1 marad, de alacsony energián.

## Memória modell

### Cím tér

A CLI-CPU 32-bites virtuális címteret használ, logikailag négy régióra osztva:

| Régió | Cím tartomány | Tartalom | Backing |
|-------|---------------|----------|---------|
| **CODE** | `0x0000_0000` – `0x3FFF_FFFF` | CIL bytecode + PE/COFF metaadat táblák | QSPI Flash, csak olvasható |
| **HEAP** | `0x4000_0000` – `0x7FFF_FFFF` | Managed objektum heap (GC) | QSPI PSRAM, olvas/ír |
| **STACK** | `0x8000_0000` – `0x8FFF_FFFF` | Evaluation stack spill + lokális változók + argumentumok + frame-ek | QSPI PSRAM |
| **MMIO** | `0xF000_0000` – `0xFFFF_FFFF` | Perifériák: UART, GPIO, timer, irq controller | On-chip |

### GC kártyatábla

A HEAP régióhoz tartozik egy **kártyatábla**: minden 512 bájt heap adatra 1 bit jelöli, hogy történt-e referencia-írás a régióba. A write barrier hardveresen frissíti. Az F4+ fázisban a GC mikrokód ennek alapján dönti el, melyik kártyát kell végigjárnia.

### Stack struktúra

A CLI-CPU-n a stack **háromszintű**:

1. **Top-of-Stack Cache (TOS cache)** — 8 db 32-bit regiszter a chip-en. A stack felső 8 eleme itt él. Minden ALU művelet ezen dolgozik, **nem nyúl RAM-hoz**.
2. **L1 D-cache** — 4 KB on-chip SRAM, spillezett stack frame-ek, lokális változók, heap hot line-ok.
3. **QSPI PSRAM** — a teljes stack backing, ~8 MB.

A TOS cache felé és felülről spillt automatikusan a hardver intéz. A programozó (és a fordító) számára **egyszerű, korlátlan mélységű stack** látszik.

### Frame felépítés

Egy metódushívás frame-je a következőt tartalmazza (felülről lefelé):

```
 magas cím
  ┌───────────────────────┐
  │   return PC           │   ← PC+len(call utasítás)
  │   saved frame pointer │
  │   saved stack pointer │
  ├───────────────────────┤
  │   arg 0               │   ← metódus paraméterei (caller pushed)
  │   arg 1               │
  │   ...                 │
  ├───────────────────────┤
  │   local 0             │   ← .locals init
  │   local 1             │
  │   ...                 │
  ├───────────────────────┤
  │   eval stack bottom   │   ← ez innen spillel a TOS cache
  │   ...                 │
  │   eval stack top      │
  └───────────────────────┘
 alacsony cím
```

A `call` mikrokód szekvenciája ezt automatikusan felépíti, a `ret` pedig lebontja.

## Dekódolási stratégia

Részletesen lásd `ISA-CIL-T0.md`, de a stratégia magja:

### Hossz-dekóder

A CIL változó hosszú utasításai **első bájt alapján egyértelműen determinisztikusak** (kivéve a `switch` opkódot, ami a 2. bájttól származtatja a hosszát). Egy 256 bejegyzéses ROM-ban van az első-bájt → hossz tábla:

```
0x00 (nop)      → 1 bájt
0x02 (ldarg.0)  → 1 bájt
0x06 (ldloc.0)  → 1 bájt
...
0x1F (ldc.i4.s) → 2 bájt
0x20 (ldc.i4)   → 5 bájt
...
0x2B (br.s)     → 2 bájt
0x38 (br)       → 5 bájt
...
0xFE (prefix)   → 2 + (ROM2 lookup szerint)
...
```

Prefix-es opkódokra (0xFE) egy második 256 bejegyzéses ROM is van.

### Hardwired vs mikrokódolt osztályozás

~75% hardwired, ~25% mikrokódolt. A hardwired csoport a következő opkód családokat tartalmazza:

- Triviális stack: `nop`, `dup`, `pop`
- Konstans: `ldc.i4.*`, `ldc.i8`, `ldc.r4`, `ldc.r8`
- Lokálisok / argumentumok: `ldloc.*`, `stloc.*`, `ldarg.*`, `starg.*`
- Egyszerű ALU: `add`, `sub`, `and`, `or`, `xor`, `neg`, `not`, `shl`, `shr`, `shr.un`
- Összehasonlítás: `ceq`, `cgt*`, `clt*`
- Rövid elágazás: `br.s`, `brtrue.s`, `brfalse.s`, `beq.s`, stb.
- Egyszerű memória: `ldind.*`, `stind.*`

A mikrokódolt csoport:

- `mul`, `div`, `rem` (iteratív implementáció)
- 64-bit integer aritmetika
- FP aritmetika (FPU sequencer)
- `call`, `callvirt`, `ret`
- `newobj`, `newarr`, `box`, `unbox`
- `isinst`, `castclass`
- `ldfld`, `stfld`, `ldelem.*`, `stelem.*`
- `ldtoken`, `ldftn`, `ldvirtftn`
- `throw`, `rethrow`, `leave`, `endfinally`
- `switch`

## μop-ok

A CLI-CPU belső mikro-utasítás formátuma (F2-ben véglegesítendő, előzetes vázlat):

```
 Mező     | Méret | Leírás
──────────┼───────┼─────────────────────────────────────────
 OP       | 6 bit | mikrokód opcode (pl. TOS_ADD, LOAD, BRANCH)
 DST      | 4 bit | cél: TOS, TOS-1, ..., LOCAL[i], ARG[i]
 SRC1     | 4 bit | forrás 1
 SRC2     | 4 bit | forrás 2
 FLAGS    | 6 bit | uses_sp, writes_flags, last_of_op, trap_enable, ...
 IMM      | 8 bit | opcionális immediate (a CIL bájtokból)
──────────┼───────┼─────────────────────────────────────────
           32 bit
```

Egy CIL `add` = 1 μop (`OP=TOS_ADD, DST=TOS-1, SRC1=TOS-1, SRC2=TOS, FLAGS=pop1 | last`).

Egy CIL `callvirt` = ~8-10 μop (lásd `ISA-CIL-T0.md` részletes trace).

## Kivételkezelés

**Shadow Register File + Checkpoint** (Transmeta-inspiráció):

- A `try` belépéskor a mikrokód egy `SAVE_CHECKPOINT` μop-ot emittál, amely a TOS cache teljes tartalmát, a SP-t, a BP-t, a PC-t **egy ciklus alatt** átmásolja egy árnyék regiszter file-ba.
- A `try` normál kilépéskor (`leave`) a checkpoint eldobható (`DROP_CHECKPOINT` μop).
- `throw` esetén a mikrokód végigjárja a metódus exception tábláját (a PE/COFF metaadatból), megkeresi a megfelelő `catch`/`filter` handlert, és ha talál:
  - `RESTORE_CHECKPOINT` μop visszaállítja a TOS cache-t
  - A throwed object referencia kerül a TOS-ra
  - PC ugrik a handler első opkódjára
- Ha nincs handler a metódusban, a mikrokód `ret`-et emittál a caller felé és megismétli a keresést.

Ez **drámaian gyorsabb**, mint a hagyományos unwind-tábla stepping, mert a mikrokód a hardveres shadow file-t használja, nem kell a stack-et sorban bontania.

## GC (Garbage Collection)

**Generational bump-allocator + stop-the-world mark-sweep** a legegyszerűbb implementáció, ami F4-ben lép be.

### Allokáció

A `newobj` / `newarr` / `box` mikrokódja:

```
 TOS_SIZE  ← objektum_méret (a típusból vagy a tömb hosszából)
 NEW_ADDR  ← HEAP_TOP
 HEAP_TOP ← HEAP_TOP + TOS_SIZE
 if HEAP_TOP > HEAP_LIMIT → TRAP #GC
 store type_ptr at NEW_ADDR
 TOS ← NEW_ADDR
```

~5-8 ciklus, ha nincs GC trap. GC trap esetén a mikrokód meghívja a GC szubrutint (ami szintén mikrokódban vagy egy kis „house-keeping" koprocesszoron fut).

### Write barrier

A `stfld` mikrokódja (ha a mező reference típusú):

```
 STORE    TOS, [TOS-1 + field_offset]
 CARD     ← (TOS-1 + field_offset) >> 9    ; kártya index
 CARD_TBL[CARD] ← 1                        ; kártya jelölés
```

Egyetlen plusz ciklus az egyszerű `stfld`-hez képest. **Hardveresen ingyen** a managed memory safety-hez képest.

### Gated Store Buffer

Az F4+ mikroarchitektúrában a write barrier kártyatábla-frissítései egy **kis store buffer-ben** gyűjtődnek, és csak commit pontoknál (metódus kilépés, `volatile.` prefix) íródnak vissza a D-cache-be. Ez a Transmeta-inspirált optimalizáció a write barrier amortizált költségét **~0.3 ciklusra** csökkenti.

## Metaadat Walker

A CIL metaadat-tokenek (pl. `MethodDef 0x06000042`) a PE/COFF metaadat táblákba mutatnak. A CLI-CPU-n ezek feloldása a **Metadata Walker koprocesszor** feladata (F4-től):

1. A CIL opkód a tokent push-olja egy kis FIFO-ba
2. A Walker elkezdi a PE/COFF táblák járását (Method table, Type table, Field table, stb.)
3. A végeredmény egy **közvetlen pointer** az objektum típusleírójára / metódus belépési pontjára / mező offszetjére
4. A Walker egy **kis TLB-t** használ a gyakran előforduló tokenek gyorsítására

**Fontos:** ez NEM változtatja meg a CIL bájtokat a memóriában. A walker csak egy „címfeloldó szolgáltatás", a kód változatlanul fut tovább.

## Prior art és átvett technikák

A CLI-CPU nem az első bytecode-natív CPU, és érdemes megtanulni mindegyik elődtől.

### Sun picoJava (1997, 1999)

**Mit csinált jól:** Természetes stack-gép Java bytecode-hoz. Top-of-Stack Caching a felső ~4 elemre. Hardveres tömb-bounds-check. Egyszerű, elegáns mikroarchitektúra.

**Miért bukott el:** A sima ARM + HotSpot JIT gyorsabb volt, és ahogy a félvezető-skálázás évtizedeken át tartott, az általános célú CPU + szoftveres runtime nem-várt mértékben utolérte a dedikált hardvert. A Sun nem tudta versenyképesen árazni.

**Mit veszünk át:**
- **Top-of-Stack Caching** — alapvető, átvéve. 4–8 elem.
- **Hardveres tömb-bounds-check** — a biztonság-first profilhoz.
- **Elegáns egyszerűség** — nem próbálunk OoO-t vagy superscalar-t.

### ARM Jazelle (2001)

**Mit csinált jól:** Egy ARM magon belüli **Java bytecode végrehajtási mód** (nem külön CPU). Az ARM decoder egy bit-kapcsolóval átkapcsol Java bytecode-ra, és a legfontosabb ~140 opkódot közvetlenül hardveresen futtatja. A komplex opkódok trap-elnek szoftveres handlerbe.

**Miért érdekes:** Ez a **hibrid** modell — nem akarunk minden opkódot hardverben megvalósítani, a ritka / komplex opkódoknál trap-elhetünk mikrokódba vagy egy kis koprocesszorra.

**Mit veszünk át:**
- **Ritka opkódok trap-elése** a metadata walker-re és a GC koprocesszorra, nem teljes mikrokód ROM implementáció.
- **Mod kapcsoló** — az F4+ verzióban lehet egy „CIL-T0 kompatibilitási mód" és egy „teljes CIL mód".

### Transmeta Crusoe / Efficeon (2000, 2003)

**Mit csinált jól:** Belső VLIW mag, **szoftveres** x86 → VLIW fordítás (Code Morphing Software), trace cache, shadow register file + checkpoint rollback, gated store buffer, writable microcode, agresszív power-gating.

**Miért bukott el:** A szoftveres DBT (Dynamic Binary Translation) warmup lassú volt, az Intel Pentium M (Dothan) megérkezése elvette a fogyasztási USP-t, a szoftveres komplexitás óriási kockázat volt.

**Mit veszünk át (és mit NEM):**

| Technika | Átvesszük? | Hol |
|----------|-----------|-----|
| Code Morphing Software (DBT) | **NEM** | Ellentmond az „CIL = natív ISA" alapelvnek |
| Belső VLIW mag | **NEM** | Stack-gép természetesebb CIL-hez |
| μop cache / trace cache | **IGEN** | F4+, forró loopokon energia-spórolás |
| Shadow register file + checkpoint | **IGEN** | F5 exception handling |
| Gated store buffer | **IGEN** | F4 GC write barrier batch |
| Writable microcode SRAM | **IGEN** | F6 ChipIgnite, firmware-frissíthető opkódok |
| Agresszív power-gating | **IGEN** | F0-tól végig, IoT profil |

### RISC-V

**Nem elődünk**, de referencia architektúra. A RISC-V egy tisztán regiszter-alapú RISC, ami pont az **ellentéte** a stack-gép CLI-CPU-nak. Viszont:

- **OpenLane2 / Sky130 / Caravel tooling** — ezt a RISC-V közösségtől tanuljuk
- **Nyílt forrású szellem** — minden RTL, doksi, teszt public lesz
- **Custom extension pattern** — Ha valaha kellene egy RISC-V mag a CLI-CPU mellé (pl. a GC koprocesszornak vagy a boot-loadernek), ott egy minimális RV32I mag jó választás

## Power management

A CLI-CPU **négy power domain**-re osztott (F6 cél):

1. **Core domain** — fetch, decode, execute, stack cache. Mindig él, amíg a CPU dolgozik.
2. **FPU domain** — csak FP opkód észlelésekor kap áramot. Integer loopokon hideg.
3. **GC / metadata domain** — a walker koprocesszor és a GC assist. Csak allokáció vagy metaadat miss esetén aktív.
4. **I/O domain** — QSPI kontrollerek, UART, GPIO. WFI (wait-for-interrupt) alatt lehalkul.

Clock-gating minden domainben, power-gating a 2., 3., 4. domainben.

## Biztonsági tulajdonságok

A CLI-CPU hardveresen kikényszeríti a következőket:

1. **Stack overflow / underflow trap** — minden pop/push ellenőrzi a stack pointer határait.
2. **Branch target validation** — minden branch cél a CODE régión belüli, és egy „legal branch target" bitmap (F5+) megmondja, hogy valódi opkód-kezdet-e.
3. **Type safety** — `isinst`/`castclass` hardveres típusleíró-lánc járás, nincs tetszőleges pointer cast.
4. **Array bounds check** — minden `ldelem`/`stelem` ellenőrzi az indexet a tömb hossza ellen.
5. **Null check** — minden `ldfld`/`stfld`/`callvirt` hardveresen ellenőrzi, hogy a receiver nem null.
6. **Write barrier** — minden reference-típusú `stfld`/`stelem.ref` hardveresen frissíti a GC kártyatáblát; nem lehet elfelejteni.
7. **No raw pointer arithmetic** — a CIL-ben nincs `add` két reference-re. A HW letrap-eli, ha valaki ilyet próbál (`unverifiable code` → trap).
8. **No self-modifying code** — a CODE régió QSPI flash-en van, csak olvasható hardveresen.

Az **F0 CIL-T0** subset már ezek többségét megvalósítja, csak a reference/objektum-specifikus ellenőrzéseket nem (mert F0-ban nincs objektum).

## Következő lépés

A `ISA-CIL-T0.md` dokumentum adja a konkrét CIL-T0 subset teljes opkód-specifikációját, kódolási táblákat, stack-effekteket, ciklusszámokat és trap feltételeket. **Ez az F1 C# szimulátor alapja** — minden ottani tesztnek közvetlenül hivatkoznia kell az ISA-CIL-T0 spec egy-egy pontjára.
