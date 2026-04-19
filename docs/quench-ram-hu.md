# Quench-RAM — Önműködő, blokkonkénti immutability hardveres memóriacella

> English version: [quench-ram-en.md](quench-ram-en.md)

> Version: 1.3

Ez a dokumentum a **Quench-RAM** memóriacella **architektúráját és ISA-illesztését** írja le: a per-blokk státuszbit szemantikáját, a két hardveres állapotgép-műveletet (`SEAL`, `RELEASE`), a NAND-flash-szel rokon „erase-on-release" mintát, és a kapcsolatot az ECMA-335 default-initialization szemantikával, az aktor-modell capability-rendszerével és a per-core garbage collector-ral.

> **Vízió-szintű dokumentum.** A Quench-RAM az F5 RTL-ben kezdhet megjelenni mint opcionális hardveres réteg az SRAM tömbök fölé, és F6-ban válhat az egész CFPU memóriahierarchia kötelező építőelemévé. Az itt rögzített invariánsok formális verifikációra alkalmasak.

## Tartalom

1. [Motiváció](#motivacio)
2. [Az alapszabály](#alapszabaly)
3. [Állapotgép és invariáns](#allapotgep)
4. [Hardveres állapotgép-műveletek és trigger-események](#isa-primitivek)
5. [Trust boundary](#trust-boundary)
6. [Hardveres implementáció](#hardver)
6. [Kapcsolat az ECMA-335 default-init szemantikával](#ecma335)
7. [Szinergia a per-core GC-vel](#gc-szinergia)
8. [Szinergia az aktor-modell capability-rendszerével](#aktor-szinergia)
9. [Biztonsági garanciák](#biztonsag)
10. [Formális verifikációs profil](#formalis)
11. [Granularitás és terület-overhead](#granularitas)
12. [Kapcsolódó technológiák](#rokon)
13. [Bevezetés a fejlesztési fázisokba](#fazisok)
14. [Changelog](#changelog)

## Motiváció <a name="motivacio"></a>

A Quench-RAM **elsődleges célja** két architektúrális garancia hardveres kikényszerítése:

1. **A Seal Core által hitelesített kód nem módosítható.** A verified CIL binary a CODE régióba kerül és SEAL-elődik — innentől a futó core sem tudja átírni a saját kódját. Ez a secure boot garancia runtime kiterjesztése. A Core-on belül **csak a CODE régióra** kell SEAL védelem, mert az adatterületet a CIL típusrendszer védi, más aktor pedig fizikailag nem fér hozzá (shared-nothing SRAM).

2. **A külső QRAM-ban tárolt adat nem manipulálható a Core-on kívülről.** Amikor egy core adatot ír külső QRAM-ba (swap-out, perzisztencia), az adat SEAL-elt — a külső buszról nem módosítható. Az adat csak a Core-ba visszatöltve, RELEASE után (atomi wipe) és újraallokálás után lesz ismét írható. Így a shared-nothing modell a chipen **kívül** is **fizikailag kikényszerített**, nem csak konvenció.

### Másodlagos előnyök

A SEAL/RELEASE modell egyúttal **három klasszikus memóriabiztonsági hibaosztályt** is eliminál:

- **Use-after-free (CWE-416)** — egy felszabadított memóriaterületet újra olvasnak/írnak, miközben más kontextus már új célra használja
- **Information leak freed memory (CWE-244, CWE-226)** — egy újraallokált blokk az előző használat adatait tartalmazza (Heartbleed-szerű)
- **Cold boot key recovery** — kikapcsolt eszköz DRAM/SRAM-jából titkok visszaolvashatók

Mind a három **ugyanannak a hiányosságnak** a tünete: **a memória felszabadítása szoftveres flag flippelés**, nem fizikai esemény. A Quench-RAM erre **fizikai választ ad**: a felszabadítás nem egy bit egy táblázatban, hanem **egy atomi hardveres esemény**, amely a blokk minden bitjét kötelezően nullára kényszeríti **ugyanabban a ciklusban**, amelyikben a státuszbit visszaáll.

A koncepció a **NAND flash erase szemantikájának általánosítása** általános RAM-ra, finomabb granularitással és a CIL-T0 ISA-ba integrálva.

## Az alapszabály <a name="alapszabaly"></a>

Minden Quench-RAM blokk rendelkezik **egyetlen extra státuszbittel** a hasznos adat mellett. A bit jelentése:

| Státuszbit | Jelentés | Engedélyezett művelet |
|-----------|----------|------------------------|
| 0 | mutable, normál RAM | olvasás, írás, allokáció |
| 1 | sealed (committed, immutable) | csak olvasás |

A két állapot közötti átmenet **csak két pontosan meghatározott úton** történhet:

- **`SEAL`** — `0 → 1` átmenet. A jelenlegi adat „lefoglalódik", többé nem módosítható.
- **`RELEASE`** — `1 → 0` átmenet. A státuszbit visszaáll, **és ugyanabban az atomi műveletben** az összes adatbit nullára kényszerül.

Más állapotátmenet **nem létezik**. A blokk soha nem juthat olyan állapotba, ahol „sealed-de-uniform" vagy „released-de-szennyezett" lenne.

## Állapotgép és invariáns <a name="allapotgep"></a>

```
                        SEAL                       RELEASE
   ┌──────────────┐  ──────────►  ┌──────────────┐  ──────────────────►  ┌──────────────┐
   │ status = 0   │               │ status = 1   │   atomic, 1 ciklus    │ status = 0   │
   │ data = bármi │               │ data = comm. │  ─────────────────►   │ data = 0...0 │
   │ (writable)   │               │ (immutable)  │   data ← 0^N           │ (re-alloc.)  │
   └──────────────┘               └──────────────┘                        └──────────────┘
          ▲                                                                       │
          │                                                                       │
          └───────────────────────────────────────────────────────────────────────┘
                              allokátor: csak status=0 + data=0 blokkot ad ki
```

A rendszer egyetlen invariánsa, amely minden ciklus után igaz:

> **`status = 0` ⟹ `data = 0...0` minden allokálható blokkban.**
>
> Egy frissen allokált blokk **garantáltan zero-initialized**, mert a felszabadítás eseménye **definíció szerint** ilyenné teszi.

Ez az invariáns a **formális verifikáció** szempontjából minimális: egyetlen predikátum, nincs diszjunkció, nincs futásidőben ellenőrizendő property — pusztán egy konstrukciós garancia.

## Hardveres állapotgép-műveletek és trigger-események <a name="isa-primitivek"></a>

A `SEAL` és `RELEASE` **hardveres állapotgép-műveletek (HW FSM)**, amelyeket **jól-meghatározott ISA-szintű események** triggerelnek. CIL kódból közvetlenül nem hívhatók — ez zárja ki, hogy egy rosszindulatú aktor tetszőleges blokkot seal-eljen vagy release-eljen (lásd [Trust boundary](#trust-boundary)).

### `SEAL addr` — HW FSM művelet

```
SEAL addr        ; státusz: 0 → 1   (atomi)
```

- **Effektus:** a blokk státuszbitje 0-ról 1-re vált. Az adat változatlan marad.
- **Idempotens:** ha a blokk már sealed, no-op (nincs trap).
- **Triggerek (az egyetlen módok, amiken keresztül meghívódhat):**
  - **CODE régió SEAL** — a Seal Core boot-kor, vagy a `hot_code_loader` AuthCode-verify után sealeli a CODE régiót (lásd `docs/authcode-hu.md`). A Core-on belül **csak a CODE régióra** kell SEAL, mert az adatterületet a CIL típusrendszer védi, más aktor pedig fizikailag nem fér hozzá (shared-nothing SRAM).
  - **SEND** — `SEND mailbox_ref, block_addr` végrehajtása során a hardver automatikusan sealeli a payload-ot, mert az adat kilép a Core SRAM határából.
  - **Swap-out** — DMA evict során, amikor a Core adat külső QRAM-ba kerül. A SEAL védi a buszról történő manipuláció ellen.
- **CIL alkalmazásból:** semmilyen úton nem elérhető. Nincs `[SealAttribute]`, nincs `Asm.Seal(...)` API.

### `RELEASE addr` — HW FSM művelet

```
RELEASE addr     ; státusz: 1 → 0,  data ← 0^N   (atomi, 1 ciklus)
```

- **Effektus:** a státuszbit visszaáll 0-ra **és** az összes adatbit nullára kényszerül **ugyanabban a ciklusban**.
- **Memory ordering:** a RELEASE egy **release barrier** — az utána következő allokáció garantáltan a frissen wipe-olt blokkot kapja.
- **Triggerek (az egyetlen módok):**
  - **GC_SWEEP** — kizárólag a **hívó aktor saját heap-jén** dolgozik (per-core SRAM isolation); az unreachable blokkokat release-eli.
  - **hot_code_loader** — CODE régió unload-jakor.
  - **Swap-in** — külső QRAM-ból visszatöltéskor. A RELEASE atomi wipe-pal törli a régi tartalmat, utána az adat **mutable**-ként másolódik a Core SRAM-ba (nem SEAL-elődik, mert a Core-on belül a CIL típusrendszer véd).
- **CIL alkalmazásból:** nem közvetlenül elérhető. Egy aktor csak a saját heap-jén indíthat `GC_SWEEP`-et, ami csak a már elérhetetlen blokkjait release-eli. Más aktor blokkjait **fizikailag nem tudja érinteni** (shared-nothing).

### Az alapelv: SEAL a Core határán

A SEAL védelem ott szükséges, ahol az adat **elhagyja a Core izolált SRAM-ját**:

| Irány | SEAL/RELEASE | Miért |
|-------|-------------|-------|
| Core → mailbox (SEND) | **SEAL** | payload kilép a Core-ból, hálózaton halad |
| Core → külső QRAM (swap-out) | **SEAL** | adat buszon elérhető, manipulálható lenne |
| Seal Core → CODE régió (boot/hot load) | **SEAL** | verified kód immutable marad |
| Külső QRAM → Core (swap-in) | **RELEASE** | régi tartalom törlése, adat mutable-ként visszatöltődik |
| GC sweep (Core-on belül) | **RELEASE** | unreachable blokkok felszabadítása |
| CODE régió unload | **RELEASE** | régi kód törlése |

A Core-on **belül** az adatterületen nincs SEAL — a CIL típusrendszer biztosítja az integritást (TypeToken, CapabilityTag stb. `readonly` mezők), és más aktor fizikailag nem fér hozzá a Core SRAM-jához.

## Trust boundary <a name="trust-boundary"></a>

A Quench-RAM biztonsága **nem privilégium-szeparációra** épül (nincs kernel mode vs. user mode — a Neuron OS explicit elveti ezt, lásd [`vision-hu.md#2-nem-monolit-kernel--helyette-aktor-hierarchia`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#2-nem-monolit-kernel--helyette-aktor-hierarchia)). Helyette **két meglévő mechanizmus kombinációjára**:

### 1. Kizárólag hardveres állapotgép-műveletek (SEAL, RELEASE)

Mivel ezek nem hívhatók CIL alkalmazás-szintről, egy rosszindulatú aktor **nem tudja direkten** triggerelni őket. A hardver automatikusan hajtja végre őket, a jól-meghatározott trigger-eseményekre reagálva.

### 2. Per-aktor heap isolation (shared-nothing)

Ez **már létezik** a Neuron OS-ben (366-369. sor). Minden aktor saját per-core SRAM heap-en él, saját capability-rendszerrel. Következmény:

| Támadás-kísérlet | Miért bukik |
|-------------------|-------------|
| Rosszindulatú aktor `GC_SWEEP`-et hív | csak a **saját heap-jén** dolgozik → a saját szemetét takarítja, másokét nem éri el |
| Rosszindulatú aktor más aktor blokkjára akar cap-et szerezni | A capability tag HMAC-elt, hamisíthatatlan — router ellenőrzi (398. sor) |
| Rosszindulatú aktor kódot ír, ami SEAL-t vagy RELEASE-t hív | A linker (`cli-cpu-link`) nem engedi le — nincs ilyen CIL opkód |
| Rosszindulatú aktor hot_code_loader-t kompromittál | hot_code_loader maga **aláírt, verified aktor** (AuthCode), kódját nem lehet tamperelni |

**Eredmény:** a trust-boundary a **hardveres állapotgép maga** (~néhány ezer kapu HW FSM), nem az alkalmazás-kód (potenciálisan millió sor CIL). Ez seL4 / CHERI-stílusú minimizált TCB (Trusted Computing Base).

## Hardveres implementáció <a name="hardver"></a>

A megvalósítás **egyetlen ciklusban** elvégezhető:

```
RELEASE(addr):
  ┌─ status_bit[addr] ← 0
  ├─ row_select[addr] ← active
  ├─ all_bitlines    ← 0           ◄── párhuzamosan az összes oszlop
  └─ commit clock edge
```

A kulcs egyetlen extra hardveres jel: a **„row-selective clear"** signál a row decoder-ből, ami a normál `wordline + bitline_input` mechanizmus helyett **pull-to-ground**-ra kapcsolja az összes bitline-t a kiválasztott sorra.

> **Fontos különbség a BIST broadcast-tól:** A modern SRAM-okban megtalálható BIST broadcast-clear az **egész SRAM bankot** törli egyszerre — ez nem azonos a Quench-RAM által igényelt **sor-szelektív** (row-selective) clear-rel, ahol egyetlen blokk nullázódik a többitől függetlenül. A Quench-RAM tehát **nem a meglévő BIST áramkör újrahasznosítása**, hanem annak **finomabb granularitású változata**: a row decoder szelektíven aktiválja a clear-jelet egyetlen sorra (vagy sor-csoportra), miközben a többi sor érintetlen marad. Ez **custom SRAM design-t igényel** — a standard SRAM makrók (pl. OpenRAM generált blokkok) nem támogatják ezt a funkciót gyárilag.

### Memória-technológia szerinti megfelelőségek

| Technológia | RELEASE megvalósítás | Megjegyzés |
|-------------|----------------------|------------|
| 6T SRAM | row-selective bitline-clear, 1 ciklus | custom SRAM cella szükséges (a BIST broadcast-clear nem sor-szelektív) |
| 8T/10T SRAM | dedikált clear-port | terület-pozitív, de gyorsabb |
| eMRAM | single-step "reset to AP state" | természetesen polaritásos |
| eFRAM | bipoláris pulse, ~5-10 ns | kompatibilis, de lassabb |
| PCM | crystalline reset | egy fok lassabb, energia-magas |
| eFlash NAND | nincs Quench-RAM ott — flash maga már ilyen | a Quench-RAM-ot **fölötte** absztrakcióként jelenik meg |

### Becsült terület-overhead

| Granularitás | Status bit overhead az adathoz képest | Megjegyzés |
|--------------|----------------------------------------|------------|
| 4 KB page | 0.003% | OS-szintű page protection-ra |
| 256 byte blokk | 0.05% | tipikus CIL objektum-méret |
| 64 byte cache line | 0.2% | cache-illesztett |
| 16 byte mini-blokk | 0.8% | finom granularitású capability tag-ekhez |

A row-selective clear áramkör **maga elenyésző** — egyetlen extra wordline-szerű vezeték per sor, és egy kis dekóder-logika. A fő költség nem az áramkör, hanem a **custom SRAM cella tervezése**: a status bit hozzáadása és a szelektív clear-logika integrálása a cella-szintű layout-ba gyártóspecifikus munka, amelyet az open PDK-k (pl. Sky130 + OpenRAM) nem támogatnak gyárilag.

**Összesen:** ~0.5% chipterület-overhead a Quench-RAM teljes integrációért, beleértve a status-bit storage-ot és a row-selective clear vezetékeket.

## Kapcsolat az ECMA-335 default-init szemantikával <a name="ecma335"></a>

Az ECMA-335 (a CLI bytecode szabvány) **kötelezően előírja**, hogy minden managed objektum mezője a típusa **`default(T)`** értékével inicializálódjon az allokáció után:

| Típus | `default(T)` |
|-------|--------------|
| `int`, `long`, `byte`, `bool`, `enum` | 0 / false |
| `float`, `double` | 0.0 |
| reference type | `null` |
| `struct` | minden mező rekurzívan default |

**Mind nullák.** Egyetlen kivétel sincs.

A Quench-RAM RELEASE szemantikája **pontosan ezt a feltételt teljesíti hardveresen**. Egy frissen allokált CIL objektum mezői **nem igényelnek** szoftveres zero-init lépést — a memória **már** zero-initialized a megelőző RELEASE eseménynek köszönhetően.

### Konkrét teljesítmény-nyereség

A jelenlegi .NET runtime-ban a `newobj` és `newarr` opkódok **explicit zero-init lépést** igényelnek, ami nagy objektumoknál (pl. 4 KB-os struct array) **több száz ciklust** vesz igénybe. A Quench-RAM-on ez a lépés **eltűnik**:

```
// Hagyományos CPU-n:
newarr int32[1024]:
  - allokáció:        ~5 ciklus
  - zero-init 4 KB:   ~250 ciklus  ◄── eltűnik Quench-RAM-on
  - return ref:       ~1 ciklus
                      ─────────
                      ~256 ciklus

// Quench-RAM-on (CIL-T0):
newarr int32[1024]:
  - allokáció:        ~5 ciklus
  - zero-init:        0 (már zero a RELEASE óta)
  - return ref:       ~1 ciklus
                      ─────────
                      ~6 ciklus     ◄── ~40× gyorsabb nagy alloc-okra
```

### Invariáns megerősítés

> **Quench-RAM + ECMA-335 = zero-init garancia minden CIL allokációra, futási idő hozzáadása nélkül.**

Ez egyszerre **biztonsági** és **teljesítmény** előny, ami egyetlen megoldásból fakad — ritka kombináció a hardveres tervezésben.

## Szinergia a per-core GC-vel <a name="gc-szinergia"></a>

A [`NeuronOS/vision-hu.md#per-core-privát-gc`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#per-core-privát-gc) rögzíti, hogy minden Rich core saját **bump allocator + mark-sweep GC**-vel rendelkezik. A Quench-RAM ezt a GC-t **drámaian leegyszerűsíti**:

### Mark fázis
Változatlan: a GC bejárja a referencia-gráfot, és minden elérhető objektumot megjelöl.

### Sweep fázis
A nem-jelölt objektumokra a GC **`GC_SWEEP` triggereli a hardveres RELEASE-t**. Ennyi.

```
// A per-core GC sweep logikája
foreach (var obj in heap.Blocks)
{
    if (!obj.IsMarked)
    {
        // A GC_SWEEP HW FSM automatikusan RELEASE-eli: status=0 + data=0, 1 ciklus, atomi
    }
}
```

### Allokáció

A bump allocator **csak `status=0 + data=0`** blokkokat ad ki. Mivel az invariáns szerint **minden status=0 blokk uniform-zero**, az allokátornak nincs feladata a tartalom inicializálásával.

### Mit nyer a rendszer

| Aspektus | Hagyományos GC | Quench-RAM GC |
|----------|---------------|----------------|
| Sweep fázis műveletei objektumonként | mark-clear, freelist update, esetleg compaction | egyetlen RELEASE (HW FSM) |
| Zero-fill a felszabadítás után | szoftveresen ciklusban | hardveres, atomi |
| Felejtős GC-bug (zero-fill kihagyva) | gyakori CVE-forrás | **fizikailag lehetetlen** |
| GC pausek méréshetősége | komplex (heap-traversal idő) | egyszerű (RELEASE műveletek száma × 1 ciklus) |
| Per-core párhuzamos GC | nehéz (lock-free freelist) | **triviális** (csak lokális RELEASE műveletek) |

### Pinning ingyen

A „pinned object" fogalma a hagyományos .NET GC-ben: olyan objektum, amit a GC nem mozgathat (pl. interop-hoz). A Quench-RAM-on **minden sealed objektum automatikusan pinned**, mert a tartalma immutable. Ez az interop-réteg számára természetes garancia.

## Szinergia az aktor-modell capability-rendszerével <a name="aktor-szinergia"></a>

A [`NeuronOS/vision-hu.md#a-capability-fogalma`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#a-capability-fogalma) szakaszban definiált `ActorRef` egy capability-token. A Quench-RAM ezt **fizikailag védhetővé teszi**:

```csharp
public readonly struct ActorRef
{
    public int  CoreId;
    public int  MailboxIndex;
    public long CapabilityTag;   // HMAC-szerű, csak a registry írhatja
    public int  Permissions;
}
```

Egy `ActorRef` instance, amelyet egy **sealed Quench-RAM blokkban** tárolunk, **tamper-proof a hardver szintjén**:

- A capability tag-et nem lehet utólag átírni — a blokk sealed
- Egy aktor-bug, amely megpróbál egy másik aktor capability-jét hamisítani, **fizikailag képtelen** rá (a SEAL után írási kísérlet trap-et generál)
- A capability registry maga (`capability_registry`, lásd 243. sor) is sealed blokkokban tárolja a kibocsátott tag-eket

### Hibrid objektum-layout

Egy CIL objektum kétféle régióra bontható:

```
┌──────────────────────────────────────────────┐
│ SEALED régió (status=1, immutable):          │
│   TypeToken      ─┐                           │
│   ObjectId       ─├── identitás, capability   │
│   CapabilityTag  ─┘                           │
│   init-only mezők (readonly properties)       │
├──────────────────────────────────────────────┤
│ MUTABLE régió (status=0):                    │
│   változó mezők (mutable state)              │
│   GC mark bit, generation                    │
└──────────────────────────────────────────────┘
```

A linker (`cli-cpu-link`) build-time eldönti minden mezőről, hogy melyik régióba kerül, az `init` és `readonly` jelek alapján:

- C# `init` és `readonly` mezők → SEALED régió
- Mutable mezők → MUTABLE régió
- Az objektum referencia (`ActorRef`) **mindig** SEALED régióra mutat

### Mit nyer a rendszer

- **Type confusion fizikai kizárása:** a `TypeToken` sealed; egy memory-corruption bug nem tudja hamisítani
- **Capability forging fizikai kizárása:** a `CapabilityTag` sealed; nem írható át
- **Object identity stabilitása:** az `ObjectId` sealed; egy GC mozgatás után is konzisztens marad

## Biztonsági garanciák <a name="biztonsag"></a>

A Quench-RAM **hét új attack-class** ellen ad fizikai szintű védelmet, amelyeket a `docs/security-hu.md` jelenlegi táblázata vagy nem említ, vagy csak részben:

| Támadás-osztály | CWE | Hagyományos CPU | Quench-RAM-mal |
|----------------|-----|-----------------|----------------|
| Use-after-free | CWE-416 | Sebezhető | **Fizikailag kizárva** — re-alloc csak uniform blokkból |
| Double-free | CWE-415 | Sebezhető | **Trap** — második RELEASE no-op (idempotens) |
| Information leak in freed memory | CWE-244, CWE-226 | Heartbleed-szerű, gyakori | **Konstrukció szerint kizárva** — RELEASE = atomi wipe |
| Uninitialized memory read | CWE-457 | Gyakori (régi C/C++) | **Kizárva** — minden alloc bizonyítottan zero-init |
| Cold boot key recovery | — | DRAM-ból visszaolvasható | **Kizárva** — sealed kulcs csak RELEASE-szel szabadul, az pedig wipe |
| Sensitive data in swap | CWE-200 | OS-függő | **Kizárva** — nincs swap (per-core SRAM) + sealed nem swappable |
| Capability tag forging | — | RAM patcheléssel lehetséges | **Kizárva** — sealed régióban tárolva |

### Ami nem védett

Őszinteség kedvéért a Quench-RAM **nem véd** a következők ellen:

- **Side-channel támadások** — egy SEAL/RELEASE művelet időzítése detektálható; ha ez érzékeny (pl. kriptografikus kontextusban), constant-time runtime kell
- **Fizikai támadás** (FIB, probing) — a tamper-resistance külön tervezési réteg, lásd `docs/secure-element-hu.md`
- **Spoofing a wake-up jelben** — a status bit egy SEU (single-event upset) áldozata lehet, ECC védelem kell köré
- **GC-overrun DoS** — egy aktor szándékosan gyorsan SEAL-RELEASE ciklusban dolgozhat, ami a GC-t terheli; rate limiting szükséges

## Formális verifikációs profil <a name="formalis"></a>

A Quench-RAM ISA-szemantikája **kifejezetten formális verifikációra szabva**. A teljes leírás egyetlen invariáns + két állapotátmeneti szabály:

```
Invariáns:    ∀ blokk b. status(b) = 0 ⟹ ∀ bit i ∈ b. data(b, i) = 0

SEAL b:       pre:  status(b) = 0
              post: status(b) = 1  ∧  data(b) változatlan

              pre:  status(b) = 1
              post: no-op (idempotens)

RELEASE b:    pre:  status(b) = 1  ∧  triggered_by(GC_SWEEP ∨ hot_code_unload)
              post: status(b) = 0  ∧  ∀ bit i. data(b, i) = 0
```

Ez **háromsoros operacionális szemantika** Coq, Isabelle/HOL, Lean 4 vagy F\* eszközben pár száz sor formális kódra fordul. Az invariáns megőrződése minden átmenet után **közvetlenül levezethető** a szabályokból.

A `docs/security-hu.md` 184. sorában rögzített F5 ütemterv (refinement bizonyítás az RTL ellen) **közvetlenül alkalmazható** a Quench-RAM hardveres implementációjára.

## Granularitás és terület-overhead <a name="granularitas"></a>

A Quench-RAM blokk-méret döntő hatással van a felhasználási mintákra. A négy releváns granularitás:

### 4 KB page
- **Felhasználás:** OS-szintű memory protection, virtuális memória nélküli rendszerekben
- **Overhead:** 0.003%
- **Hátrány:** túl durva tipikus CIL objektumokhoz; egy 16 byte-os object pinningja egy egész 4 KB page-et fixál

### 256 byte blokk
- **Felhasználás:** tipikus CIL objektum-méret, jó kompromisszum
- **Overhead:** 0.05%
- **Előny:** a legtöbb objektum egy blokkba fér; a sealed/mutable szétválás könnyen menedzselhető

### 64 byte cache line
- **Felhasználás:** F6+ Rich core-okon, ahol cache van
- **Overhead:** 0.2%
- **Előny:** cache-koherens RELEASE természetes; finom-szemcsés sealing

### 16 byte mini-blokk
- **Felhasználás:** capability tag tárolás, kis structok
- **Overhead:** 0.8%
- **Hátrány:** sok status bit, komplexebb decoder

### Javasolt heterogén megoldás

Egy F6 Rich core **több granularitást** támogathat egyidejűleg, különböző memóriaregiókkal:

| Régió | Granularitás | Felhasználás |
|-------|--------------|---------------|
| `CODE` | n/a | mindig sealed boot-tól (külön QSPI flash, R/O) |
| `DATA-fine` | 16 byte | capability registry, ActorRef pool |
| `DATA-medium` | 256 byte | aktor state objektumok |
| `STACK` | n/a | nincs Quench-RAM (per-frame allokáció gyors) |
| `MAILBOX` | 64 byte | sealed üzenet-payload-ok |

A Nano core (F4) egyszerűbb: csak **256 byte blokk** granularitás, mert az egyszerűségre tervezve.

## Kapcsolódó technológiák <a name="rokon"></a>

A Quench-RAM **nem az első próbálkozás** ezekre a problémákra; a következő rendszerek részmegoldásokat adnak:

| Rendszer | Megfelelő funkció | Mit nem ad |
|----------|---------------------|------------|
| **NAND Flash erase** | block-level wipe + immutability | nem hardveres ISA-primitiv, granularitás durva |
| **CHERI sealed capabilities** | sealed pointerek immutability | a memória maga nem wipe-olódik release-kor |
| **ARM MTE (Memory Tagging)** | 4-bit color tag per region | nem immutability, nem auto-wipe |
| **Intel CET shadow stack** | write-once stack régió | speciális célú, nem általános |
| **Trusted Platform Module monotonic counters** | write-once számláló | egyetlen érték, nem általános memória |
| **Forth `here`/`forget` modell** | append-only dictionary | szoftveres, nem hardveres kényszerítés |
| **Erlang persistent_term** | immutable runtime constant | szoftveres, BEAM-szintű |

A Quench-RAM **egyedi kombinációja**:

- Hardveres szinten kényszerített
- ISA-szintű trigger-eseményekhez kötött (nem tetszőlegesen hívható)
- Atomi RELEASE = wipe + free egyetlen ciklusban
- Konstrukciós zero-init garancia minden allokációra
- Formális verifikációra alkalmas minimális szemantika

## Bevezetés a fejlesztési fázisokba <a name="fazisok"></a>

A Quench-RAM **nem feltétel** az F0-F4 fázisokhoz; ezek a meglévő SRAM-modellel működnek tovább. A bevezetés **fokozatos**:

| Fázis | Quench-RAM szerepe |
|-------|---------------------|
| F0–F2 (szimulátor) | szoftveres emuláció a `TCpu`-ban: extra status-bit minden blokkhoz, RELEASE szoftveresen wipe-ol; opcionális, kapcsolóval bekapcsolható |
| F3 (Tiny Tapeout) | nincs hardveres Quench-RAM (terület korlát), de a szimulátor **már tartalmazza** a SEAL/RELEASE HW FSM logikát szoftveres emulációban |
| F4 (multi-core szim) | szoftveres emuláció minden core-on, méréseket kapunk a tipikus SEAL/RELEASE arányról |
| **F5 (RTL prototípus)** | **FPGA demonstráció**: a Quench-RAM logika FPGA BRAM-ban valósul meg (status bit + szelektív clear egyszerűen implementálható FPGA-n, nincs PDK-specifikus SRAM cella korlát); ASIC target-en (Sky130) a SEAL/RELEASE **szoftveres emulációban marad**, mert a custom SRAM cella tervezése open PDK-ban még nem elérhető |
| **F6 (ChipIgnite tape-out)** | **első szilícium implementáció**: a ChipIgnite/Efabless flow-ban custom SRAM cellák tervezhetők; **kötelező hardveres feature** minden DATA és MAILBOX régióban; F6 Cognitive Fabric One az első valós Quench-RAM chip |
| F6.5 (Secure Edition) | finomabb granularitás (16 byte) a kapcsolódó capability registry-hez |
| F7 (silicon iter 2) | esetleges NVRAM integráció (eMRAM/eFRAM), tranzakciós journal opciók |

## Referencia hivatkozások

- `docs/architecture-hu.md` — a CFPU mikroarchitektúrája, ahova a Quench-RAM beilleszkedik
- `docs/security-hu.md` — biztonsági modell, amit a Quench-RAM kibővít
- [`NeuronOS/docs/vision-hu.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md) — a per-core GC és capability registry, amelyek a Quench-RAM-ot használják
- `docs/secure-element-hu.md` — F6.5 Secure Edition, ahol a finom-szemcsés Quench-RAM kötelező

## Changelog <a name="changelog"></a>

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.3 | 2026-04-19 | SEAL triggerek pontosítása: Core-on belül csak CODE régióra kell SEAL (adatot a CIL típusrendszer védi). Swap-out SEAL és swap-in RELEASE hozzáadva. Elsődleges motiváció átírva (CODE immutability + külső QRAM védelem). |
| 1.2 | 2026-04-19 | Row-selective clear pontosítás (nem BIST broadcast). F5: FPGA demo, F6: első szilícium. |
| 1.1 | 2026-04-16 | Trust boundary szekció. SEAL/RELEASE HW FSM műveletként definiálva, per-aktor heap isolation. |
| 1.0 | 2026-04-16 | Kezdeti kiadás. SEAL + RELEASE modell, ECMA-335 default-init, per-core GC integráció. |
