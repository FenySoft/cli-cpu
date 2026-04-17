# Quench-RAM — Önműködő, blokkonkénti immutability hardveres memóriacella

> English version: [quench-ram-en.md](quench-ram-en.md)

> Version: 1.1

Ez a dokumentum a **Quench-RAM** memóriacella **architektúráját és ISA-illesztését** írja le: a per-blokk státuszbit szemantikáját, a két hardveres microcode-primitivet (`SEAL`, `RELEASE`), a NAND-flash-szel rokon „erase-on-release" mintát, és a kapcsolatot az ECMA-335 default-initialization szemantikával, az aktor-modell capability-rendszerével és a per-core garbage collector-ral.

> **v1.1 biztonsági javítás:** a `SEAL` és `RELEASE` **nem CIL opkód**, hanem microcode-szintű primitivek, amelyeket jól-meghatározott trigger-események hívnak meg (`SEND`, `newobj`, `newarr`, `GC_SWEEP`, `hot_code_loader`). Ez zárja ki, hogy egy rosszindulatú aktor tetszőleges blokkot seal-eljen vagy release-eljen. Részletek: [Trust boundary](#trust-boundary) szekció.

> **Vízió-szintű dokumentum.** A Quench-RAM az F5 RTL-ben kezdhet megjelenni mint opcionális hardveres réteg az SRAM tömbök fölé, és F6-ban válhat az egész CFPU memóriahierarchia kötelező építőelemévé. Az itt rögzített invariánsok formális verifikációra alkalmasak.

## Tartalom

1. [Motiváció](#motivacio)
2. [Az alapszabály](#alapszabaly)
3. [Állapotgép és invariáns](#allapotgep)
4. [Microcode-primitivek és trigger-események](#isa-primitivek)
5. [Trust boundary](#trust-boundary)
6. [Hardveres implementáció](#hardver)
6. [Kapcsolat az ECMA-335 default-init szemantikával](#ecma335)
7. [Szinergia a per-core GC-vel](#gc-szinergia)
8. [Szinergia az aktor-modell capability-rendszerével](#aktor-szinergia)
9. [Biztonsági garanciák](#biztonsag)
10. [Formális verifikációs profil](#formalis)
11. [Granularitás és terület-overhead](#granularitas)
12. [Kapcsolódó technológiák](#rokon)
13. [Nyitott kérdések](#nyitott)
14. [Bevezetés a fejlesztési fázisokba](#fazisok)
15. [Changelog](#changelog)

## Motiváció <a name="motivacio"></a>

A modern CPU-architektúrák **memóriabiztonsági hibáinak** legnagyobb része három kategóriába esik:

- **Use-after-free (CWE-416)** — egy felszabadított memóriaterületet újra olvasnak/írnak, miközben más kontextus már új célra használja
- **Information leak freed memory (CWE-244, CWE-226)** — egy újraallokált blokk az előző használat adatait tartalmazza (Heartbleed-szerű)
- **Cold boot key recovery** — kikapcsolt eszköz DRAM/SRAM-jából titkok visszaolvashatók

Mind a három **ugyanannak a hiányosságnak** a tünete: **a memória felszabadítása szoftveres flag flippelés**, nem fizikai esemény. A Linux/Windows/macOS rendszerek "free()" műveletét bárki kihagyhatja, szabotálhatja vagy elfelejtheti.

A Quench-RAM erre a problémára **fizikai választ ad**: a felszabadítás nem egy bit egy táblázatban, hanem **egy atomi hardveres esemény**, amely a blokk minden bitjét kötelezően nullára kényszeríti **ugyanabban a ciklusban**, amelyikben a státuszbit visszaáll.

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

## Microcode-primitivek és trigger-események <a name="isa-primitivek"></a>

A `SEAL` és `RELEASE` **NEM CIL opkódok** — nem hívhatók közvetlenül CIL kódból. Helyettük **hardveres microcode-primitivek**, amelyeket **jól-meghatározott ISA-szintű események** triggerelnek. Ez zárja ki, hogy egy rosszindulatú aktor tetszőleges blokkot seal-eljen vagy release-eljen (lásd [Trust boundary](#trust-boundary)).

### `SEAL addr` — microcode primitiv

```
SEAL addr        ; státusz: 0 → 1   (atomi)
```

- **Effektus:** a blokk státuszbitje 0-ról 1-re vált. Az adat változatlan marad.
- **Idempotens:** ha a blokk már sealed, no-op (nincs trap).
- **Triggerek (az egyetlen módok, amiken keresztül meghívódhat):**
  - `newobj` / `newarr` microcode az objektum-header régióját sealeli init-only mezők beírása után
  - `SEND mailbox_ref, block_addr` microcode sealeli a payload-ot atomi módon a cap-transzferrel együtt
  - `hot_code_loader` aktor AuthCode-verify után sealeli a CODE régiót (lásd `docs/authcode-hu.md`)
- **CIL alkalmazásból:** semmilyen úton nem elérhető. Nincs `[SealAttribute]`, nincs `Asm.Seal(...)` API.

### `RELEASE addr` — microcode primitiv

```
RELEASE addr     ; státusz: 1 → 0,  data ← 0^N   (atomi, 1 ciklus)
```

- **Effektus:** a státuszbit visszaáll 0-ra **és** az összes adatbit nullára kényszerül **ugyanabban a ciklusban**.
- **Memory ordering:** a RELEASE egy **release barrier** — az utána következő allokáció garantáltan a frissen wipe-olt blokkot kapja.
- **Triggerek (az egyetlen módok):**
  - `GC_SWEEP` ISA-opkód — kizárólag a **hívó aktor saját heap-jén** dolgozik (per-core SRAM isolation); az unreached sealed blokkokat release-eli
  - `hot_code_loader` aktor — ha unload-ol egy CODE régiót
- **CIL alkalmazásból:** szintén nem közvetlenül. Egy aktor csak a saját heap-jén `GC_SWEEP`-et indíthat, ami csak a már elérhetetlen blokkjait release-eli. Más aktor blokkjait **fizikailag nem tudja érinteni** (shared-nothing).

### Miért így

A korábbi verzió (v1.0) a SEAL-t és RELEASE-t **közvetlen CIL opkódként** írta le, ami egy támadási vektort nyitott: egy rosszindulatú aktor, aki valahogy cap-et szerez egy másik aktor sealed blokkjára, RELEASE-elhette volna, felülírhatta volna, majd újra SEAL-elhette volna — közben a "sealed" státusz látszólag érintetlen maradt volna. Az új modellben ez **fizikailag lehetetlen**: a SEAL és RELEASE nem érhető el tetszőleges kontextusból, csak a jól-meghatározott trigger-események veszik őket igénybe.

### Nincs külön `WIPE` primitiv

Az előzetes tervekben szerepelt egy külön `WIPE` primitiv a "felszabadítás-előtti tisztítás" céljára. A jelenlegi modellben **erre nincs szükség**, mert a RELEASE atomi módon végrehajtja a wipe-ot. Két előny: (1) nincs köztes „sealed-de-tisztított" furcsa állapot; (2) két primitiv a három helyett, tehát a formális verifikáció dolga is könnyebb.

## Trust boundary <a name="trust-boundary"></a>

A Quench-RAM biztonsága **nem privilégium-szeparációra** épül (nincs kernel mode vs. user mode — a Neuron OS explicit elveti ezt, lásd [`vision-hu.md#2-nem-monolit-kernel--helyette-aktor-hierarchia`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#2-nem-monolit-kernel--helyette-aktor-hierarchia)). Helyette **két meglévő mechanizmus kombinációjára**:

### 1. Microcode-only primitivek (SEAL, RELEASE)

Mivel ezek nem hívhatók CIL alkalmazás-szintről, egy rosszindulatú aktor **nem tudja direkten** triggerelni őket. Csak a runtime (microcode) hívja meg őket, a jól-meghatározott trigger-eseményekre reagálva.

### 2. Per-aktor heap isolation (shared-nothing)

Ez **már létezik** a Neuron OS-ben (366-369. sor). Minden aktor saját per-core SRAM heap-en él, saját capability-rendszerrel. Következmény:

| Támadás-kísérlet | Miért bukik |
|-------------------|-------------|
| Malicious aktor `GC_SWEEP`-et hív | csak a **saját heap-jén** dolgozik → a saját szemetét takarítja, másokét nem éri el |
| Malicious aktor más aktor blokkjára akar cap-et szerezni | A capability tag HMAC-elt, hamisíthatatlan — router ellenőrzi (398. sor) |
| Malicious aktor kódot ír, ami SEAL-t vagy RELEASE-t hív | A linker (`cli-cpu-link`) nem engedi le — nincs ilyen CIL opkód |
| Malicious aktor hot_code_loader-t kompromittál | hot_code_loader maga **aláírt, verified aktor** (AuthCode), kódját nem lehet tamperelni |

**Eredmény:** a trust-boundary a **runtime maga** (~néhány ezer sor microcode), nem az alkalmazás-kód (potenciálisan millió sor CIL). Ez seL4 / CHERI-stílusú minimizált TCB (Trusted Computing Base).

## Hardveres implementáció <a name="hardver"></a>

A megvalósítás **egyetlen ciklusban** elvégezhető:

```
RELEASE(addr):
  ┌─ status_bit[addr] ← 0
  ├─ row_select[addr] ← active
  ├─ all_bitlines    ← 0           ◄── párhuzamosan az összes oszlop
  └─ commit clock edge
```

A kulcs egyetlen extra hardveres jel: a **„broadcast clear"** signál a row decoder-ből, ami a normál `wordline + bitline_input` mechanizmus helyett **pull-to-ground**-ra kapcsolja az összes bitline-t a kiválasztott sorra. Ez a technika **a legtöbb modern SRAM-ban már ott van** built-in self-test (BIST) céljára — csak az ISA számára elérhetővé kell tenni.

### Memória-technológia szerinti megfelelőségek

| Technológia | RELEASE megvalósítás | Megjegyzés |
|-------------|----------------------|------------|
| 6T SRAM | broadcast bitline-clear, 1 ciklus | BIST hardver már jellemzően ott van |
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

A broadcast-clear áramkör **maga elenyésző** — egyetlen extra wordline-szerű vezeték per sor, és egy kis dekóder-logika.

**Összesen:** ~0.5% chipterület-overhead a Quench-RAM teljes integrációért, beleértve a status-bit storage-ot és a clear-broadcast vezetékeket.

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
A nem-jelölt objektumokra a GC **`RELEASE` opkódot ad ki**. Ennyi.

```csharp
// Pszeudokód a per-core GC sweep-jében
foreach (var obj in heap.Blocks)
{
    if (!obj.IsMarked)
    {
        Asm.RELEASE(obj.Address);   // 1 ciklus, atomi: status=0 + data=0
    }
}
```

### Allokáció

A bump allocator **csak `status=0 + data=0`** blokkokat ad ki. Mivel az invariáns szerint **minden status=0 blokk uniform-zero**, az allokátornak nincs feladata a tartalom inicializálásával.

### Mit nyer a rendszer

| Aspektus | Hagyományos GC | Quench-RAM GC |
|----------|---------------|----------------|
| Sweep fázis műveletei objektumonként | mark-clear, freelist update, esetleg compaction | egyetlen RELEASE opkód |
| Zero-fill a felszabadítás után | szoftveresen ciklusban | hardveres, atomi |
| Felejtős GC-bug (zero-fill kihagyva) | gyakori CVE-forrás | **fizikailag lehetetlen** |
| GC pausek méréshetősége | komplex (heap-traversal idő) | egyszerű (RELEASE-ek száma × 1 ciklus) |
| Per-core párhuzamos GC | nehéz (lock-free freelist) | **triviális** (csak lokális RELEASE-ek) |

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
| Double-free | CWE-415 | Sebezhető | **Trap** — második RELEASE no-op trap |
| Information leak in freed memory | CWE-244, CWE-226 | Heartbleed-szerű, gyakori | **Konstrukció szerint kizárva** — RELEASE = wipe |
| Uninitialized memory read | CWE-457 | Gyakori (régi C/C++) | **Kizárva** — minden alloc bizonyítottan zero-init |
| Cold boot key recovery | — | DRAM-ból visszaolvasható | **Kizárva** — sealed kulcs csak RELEASE-szel szabadul, az pedig wipe |
| Sensitive data in swap | CWE-200 | OS-függő | **Kizárva** — nincs swap (per-core SRAM) + sealed nem swappable |
| Capability tag forging | — | RAM patcheléssel lehetséges | **Kizárva** — sealed régióban tárolva |

### Ami nem védett

Őszinteség kedvéért a Quench-RAM **nem véd** a következők ellen:

- **Side-channel támadások** — egy SEAL/RELEASE opkód időzítése detektálható; ha ez érzékeny (pl. kriptografikus kontextusban), constant-time runtime kell
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

RELEASE b:    pre:  status(b) = 1  ∧  hold(release_cap, b)
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
- ISA-primitivekkel közvetlenül elérhető
- Atomi RELEASE = wipe + free egyetlen ciklusban
- Konstrukciós zero-init garancia minden allokációra
- Formális verifikációra alkalmas minimális szemantika

## Nyitott kérdések <a name="nyitott"></a>

A doksi az **architekturális irányt** rögzíti; a következő részleteket az F5 RTL-tervezés során kell véglegesíteni:

### 1. SEAL idempotenciája
**Jelenlegi javaslat:** idempotens (második SEAL no-op).
**Alternatíva:** trap a második SEAL-re, hogy a programozói hibák hamarabb látszódjanak.
**Döntés:** F5 RTL prototípus után, mérés alapján.

### 2. Granularitás konfigurálhatósága
**Jelenlegi javaslat:** régiónként fix granularitás (lásd 11. szekció).
**Alternatíva:** runtime-ban konfigurálható per-aktor.
**Döntés:** valószínűleg fix marad, mert a runtime-konfiguráció jelentős komplexitást ad a routerhez.

### 3. Release-cap delegálhatósága
**Jelenlegi javaslat:** a release-cap a SEAL pillanatában a tulajdonos aktorhoz és a supervisor-hoz kerül.
**Alternatíva:** a tulajdonos delegálhatja egy ideiglenes „cleaner" aktornak (pl. egy időzített GC-trigger).
**Döntés:** delegálható, de a delegate maga **nem** delegálhatja tovább — egylépéses.

### 4. ECC integráció a status bittel
**Jelenlegi javaslat:** a status bit ugyanabban az ECC-szóban él, mint a hozzá tartozó adat.
**Alternatíva:** külön ECC-védett kis status-array.
**Döntés:** együttes ECC, mert egy status-bit flip + adat-flip kombináció így detektálható.

### 5. Cache-koherencia F6+ Rich core-on
**Jelenlegi javaslat:** sealed blokkokat **soha nem** evict-eljük — read-only cache-ben örökre élhetnek.
**Alternatíva:** szabványos LRU, periodikus re-fetch.
**Döntés:** sealed = no-evict, mert ez ingyen optimization, és a cache koherencia szempontjából egyszerűbb.

### 6. Power-loss recovery NVRAM esetén
**Jelenlegi javaslat:** ha a RELEASE félbeszakad, a status=1 állapotban marad → safe default (sealed = adat megmarad).
**Alternatíva:** tranzakciós journal a sealed-régióban.
**Döntés:** a safe-default elegendő tipikus felhasználásra; tranzakciós journal csak F7+ enterprise variánsban.

## Bevezetés a fejlesztési fázisokba <a name="fazisok"></a>

A Quench-RAM **nem feltétel** az F0-F4 fázisokhoz; ezek a meglévő SRAM-modellel működnek tovább. A bevezetés **fokozatos**:

| Fázis | Quench-RAM szerepe |
|-------|---------------------|
| F0–F2 (szimulátor) | szoftveres emuláció a `TCpu`-ban: extra status-bit minden blokkhoz, RELEASE szoftveresen wipe-ol; opcionális, kapcsolóval bekapcsolható |
| F3 (Tiny Tapeout) | nincs hardveres Quench-RAM (terület korlát), de a CIL-T0 ISA spec **már tartalmazza** a SEAL/RELEASE opkódokat, amelyek szoftveresen emulálódnak microcode-ban |
| F4 (multi-core szim) | szoftveres emuláció minden core-on, méréseket kapunk a tipikus SEAL/RELEASE arányról |
| **F5 (RTL prototípus)** | **első hardveres implementáció** egy 64 byte cache-line granularitású Quench-RAM tömbön; mérjük a terület-overhead-et és a power-cost-ot |
| F6 (ChipIgnite tape-out) | **kötelező hardveres feature** minden DATA és MAILBOX régióban; F6 Cognitive Fabric One az első valós Quench-RAM chip |
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
| 1.0 | 2026-04-16 | Kezdeti verziózott kiadás. SEAL + RELEASE két-opkódos modell, atomi wipe-on-release, ECMA-335 default-init kompatibilitás, integráció a per-core GC-vel és aktor-capability-rendszerrel. |
| 1.1 | 2026-04-16 | **Biztonsági javítás:** a SEAL és RELEASE NEM CIL opkódok, hanem microcode-primitivek, amelyeket csak jól-meghatározott trigger-események (`SEND`, `newobj`, `GC_SWEEP`, `hot_code_loader`) hívhatnak meg. Új szekció: [Trust boundary](#trust-boundary). A mechanism a per-aktor heap isolation-ra (shared-nothing) épül, nem új privilégium-bit-re. |
