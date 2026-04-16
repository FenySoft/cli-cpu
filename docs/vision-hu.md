# Cognitive Fabric — Vízió: A Shared-Nothing Jövő

> English version: [vision-en.md](vision-en.md)

Ez a dokumentum azt vizsgálja, mi történik, ha a **Cognitive Fabric Processing Unit (CFPU)** hardvermodelljéhez **az egész szoftver stack-et újratervezzük** — operációs rendszer, GUI, adatbázis, hálózat, programozási modell. Nem a mai szoftverrel mérjük a hardvert, hanem a hardverhez tervezzük a szoftvert.

> *A CFPU a Cognitive Fabric architektúra hivatalos megnevezése. A **CLI-CPU** ennek első nyílt forráskódú referencia implementációja — részletek: [FAQ #1](faq-hu.md#1-mi-a-cfpu-és-mi-a-kapcsolata-a-cli-cpu-val).*

> **Joe Armstrong, az Erlang atyja, 2014-ben:**
> *„A jelenlegi szoftver-rendszerek alapjaiban rossz modellekre épülnek. Szükség van egy olyan hardverre, ahol minden core egy aktor."*

---

## A mai szoftver: egy hardver korlátainak lenyomata

A mai szoftver-architektúra nem természeti törvény — egy adott hardver korlátainak következménye:

| Mai konvenció | Miért létezik | A valódi ok |
|---|---|---|
| **Központi kernel** | Valakinek koordinálnia kell a megosztott erőforrásokat | Mert **shared memory van** |
| **Mutex / lock** | Két thread ne írja ugyanazt az adatot | Mert **shared memory van** |
| **Egyetlen UI thread** | A GUI framework nem thread-safe | Mert **shared memory van** |
| **B-tree index** | Gyors keresés egyetlen diszken | Mert **egyetlen tároló van** |
| **Async/await** | Ne blokkolj thread-et I/O-ra várva | Mert **kevés thread van** |
| **Virtuális memória** | Processz izoláció | Mert **shared memory van** |
| **GPU** | A CPU nem tud elég pixelt rajzolni | Mert **kevés core van** |

**Ha eltávolítjuk a shared memory-t, és 1000+ core-t adunk: ezek a konvenciók mind feleslegessé válnak.**

---

## 1. A jövő operációs rendszere — Nincs kernel

### Ma: kernel mint központi diktátor

```
┌─────────────────────────────────────┐
│           User Space                │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐    │
│  │App 1│ │App 2│ │App 3│ │App 4│    │
│  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘    │
│─────┼───────┼───────┼───────┼───────│ ← syscall határ (drága!)
│     ▼       ▼       ▼       ▼       │
│  ┌─────────────────────────────┐    │
│  │          KERNEL             │    │
│  │  scheduler, VFS, TCP/IP,    │    │
│  │  memory manager, driver...  │    │
│  │  EGYETLEN HATALMAS PROGRAM  │    │
│  │  AMI MINDENT KOORDINÁL      │    │
│  └─────────────────────────────┘    │
│           Kernel Space              │
└─────────────────────────────────────┘

A kernel azért kell, mert valakinek ŐRKÖDNIE kell
a shared memory felett. Ez 50+ év komplexitás.
Linux kernel: ~30 millió sor kód.
```

### Neuron OS: egyenrangú aktorok, hardveres izoláció

```
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│Core 0│ │Core 1│ │Core 2│ │Core 3│ │Core 4│ │Core 5│
│      │ │      │ │      │ │      │ │      │ │      │
│ sup. │→│ app  │→│ app  │→│ uart │→│ file │→│ net  │
│      │ │ aktor│ │ aktor│ │device│ │device│ │device│
└──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘
   └────────┴────────┴────────┴────────┴────────┘
                  Mailbox Router
              (NINCS kernel, nincs syscall)

Nincs "kernel tér" vs "user tér" — mert nincs shared memory
amit védeni kellene. Minden aktor FIZIKAILAG izolált.
Az izoláció nem szoftveres (MMU + page table) → HARDVERES.
```

### Mit nyer ez?

| Szempont | Ma (Linux/Windows/macOS) | Neuron OS |
|---|---|---|
| Syscall overhead | ~1-5 µs (mode switch) | **~5-20 ns** (mailbox üzenet) |
| Kernel bug hatása | Rendszerösszeomlás | Supervisor **újraindítja** a hibás aktort |
| Kernel méret | ~30M sor (Linux) | **~5K sor** Neuron OS core |
| Izoláció típusa | Szoftveres (MMU + page table) | **Hardveres** (fizikai SRAM) |
| Hot code reload | Lehetetlen (kernel újraindítás) | **Natív** — aktor kód futás közben cserélhető |
| Boot idő | ~1-30 másodperc | **~1-10 µs** (nincs init, nincs driver scan) |

**A Linux kernel 30 millió sora azért létezik, mert a shared memory-t szoftveresen kell védeni.** Ha a hardver garantálja az izolációt, a kernel **feladata eltűnik**.

Részletek: [`docs/neuron-os-hu.md`](neuron-os-hu.md).

---

## 2. A jövő GUI-ja — Nincs egyetlen UI thread

### Ma: minden egy thread-en, ha lassú → minden akadozik

Minden GUI framework (WPF, SwiftUI, Flutter, Qt, Avalonia) egyetlen fő thread-re épül:

```
  ┌──────────────────────────────┐
  │     EGYETLEN UI THREAD       │  ← MINDEN itt történik
  │                              │
  │  • Event dispatch            │
  │  • Layout számítás           │
  │  • Adat binding              │
  │  • Animáció tick             │
  │  • Rendering parancsok       │
  │                              │
  │  Ha BÁRMI lassú → az EGÉSZ   │
  │  UI akadozik (16ms budget!)  │
  └──────────┬───────────────────┘
             ▼
  ┌──────────────────────────────┐
  │          GPU                 │
  │  Raszterizálás, kompozíció   │
  └──────────────────────────────┘
```

**Miért egyetlen thread?** Mert a scene graph (a widgetek fája) **shared mutable state** — ha két thread egyszerre módosítja, elszáll. Mutex-szel védeni túl lassú lenne. Ezért mindenki kitalálta a `Dispatcher.Invoke()` / `InvokeOnMainThread()` / `runOnUiThread()` anti-pattern-t.

### Actor GUI: minden widget egy aktor

```
  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
  │Toolbar │  │Sidebar │  │Content │  │Status  │
  │ aktor  │  │ aktor  │  │ aktor  │  │ aktor  │
  │        │  │        │  │        │  │        │
  │ saját  │  │ saját  │  │ saját  │  │ saját  │
  │ layout │  │ layout │  │ layout │  │ layout │
  │ render │  │ render │  │ render │  │ render │
  └───┬────┘  └───┬────┘  └───┬────┘  └───┬────┘
      │           │           │           │
      └─────┬─────┴─────┬─────┘           │
            ▼           ▼                 ▼
  ┌──────────────────────────────────────────┐
  │         Compositor aktor                 │
  │  (összeilleszti a régiókat, ~1 core)     │
  └──────────────────────────────────────────┘

Nincs UI thread bottleneck. Minden widget PÁRHUZAMOSAN
számítja a layout-ját és rendereli a saját régióját.
```

### A gyakorlatban

| Ma (egyetlen UI thread) | Actor GUI |
|---|---|
| 60 FPS = 16ms / frame **mindenre** | 60 FPS = 16ms / frame **régiónként** |
| Komplex lista (10K elem) → scroll akadozik | Minden elem saját aktor → **párhuzamos layout** |
| Animáció + adat betöltés → UI fagy | Animáció aktor **független** az adat aktortól |
| `Dispatcher.Invoke()` anti-pattern | **Nem létezik** — nincs "fő thread" |
| GPU szükséges a raszterizáláshoz | **1000 Nano core** maga a "GPU" — vektor rendering actor hálóban |

### GPU nélküli rendering — a számok

Ma a GPU azért kell, mert egyetlen CPU core nem tud elég pixelt rajzolni 16ms alatt. De mi van, ha 1000 core rajzol, mindegyik a képernyő egy darabját?

```
1920×1080 = ~2M pixel / frame
1000 Nano core = ~2000 pixel / core / frame

2000 pixel × 32 bit szín = ~8 KB feldolgozás
@ 3 GHz × 0.4 IPC = ~1.2 GIPS → ~6.7 µs / core

16ms frame budget-ből ~7 µs-t használ = ~0.04%
Bőven belefér. GPU nélkül, szoftveres renderinggel,
de HARDVERES párhuzamosítással.
```

Ez nem azt jelenti, hogy a GPU felesleges — textúrázás, 3D, ML inferencia arra továbbra is kell. De **2D vektor GUI** (ahogy minden üzleti alkalmazás, OS felület, dashboard kinéz) → **GPU nélkül, Nano core actor hálóval megoldható**.

---

## 3. A jövő adatbázisa — Nincs lock, nincs B-tree

### Ma: shared buffer pool, lock-ok mindenhol

```
┌─────────────────────────────────┐
│        Shared Buffer Pool       │  ← MINDEN tranzakció ide ír
│  ┌─────┐ ┌─────┐ ┌─────┐        │
│  │Page1│ │Page2│ │Page3│ ...    │  B-tree lapok, közös memóriában
│  └──┬──┘ └──┬──┘ └──┬──┘        │
│     │ LOCK  │ LOCK  │ LOCK      │  ← MVCC / 2PL / mutex
│  ┌──┴───────┴───────┴───┐       │
│  │  WAL (Write Ahead    │       │
│  │  Log) — szekvenciális│       │
│  │  írás egyetlen fájlba│       │
│  └──────────────────────┘       │
└─────────────────────────────────┘

A teljesítmény korlátja: LOCK CONTENTION a buffer pool-ban.
A WAL egyetlen szekvenciális stream → bottleneck.
```

### Actor adatbázis: minden partíció egy aktor

```
  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
  │ users   │  │ orders  │  │ products│  │ logs    │
  │ aktor   │  │ aktor   │  │ aktor   │  │ aktor   │
  │         │  │         │  │         │  │         │
  │ privát  │  │ privát  │  │ privát  │  │ privát  │
  │ SRAM    │  │ SRAM    │  │ SRAM    │  │ SRAM    │
  │ index   │  │ index   │  │ index   │  │ index   │
  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘
       │            │            │            │
       └──── query aktor ←── SQL parser aktor
              (JOIN = üzenet a két tábla aktor között)

NINCS lock — minden tábla aktor szekvenciálisan dolgozza
fel a saját üzeneteit. Konzisztencia = üzenet-sorrend.
NINCS WAL — az üzenetnapló MAGA az event log.
```

### Mit nyer ez?

| Szempont | Mai RDBMS (PostgreSQL) | Actor DB |
|---|---|---|
| INSERT latency | ~5-50 µs (WAL + buffer lock + fsync) | **~50-500 ns** (SRAM írás) |
| Lock contention | Romlik core-számmal | **0** — nincs shared state |
| Horizontális skálázás | Komplex (replikáció, sharding) | **Triviális** — új partíció = új aktor |
| Event sourcing | Külön framework (EventStore, Marten) | **Natív** — az üzenetnapló az adat |
| CQRS | Architekturális pattern, szoftveres | **Természetes** — read aktor + write aktor |
| JOIN | Shared buffer pool-on | **Üzenet** a tábla aktorok között, pipeline-olt |
| Replikáció | WAL shipping, komplex | **Üzenet forwarding** — az aktor üzeneteit másolja |

**A relációs modell nem hal meg** — a lekérdezési nyelv (SQL) és a relációs algebra értékes. Ami meghal, az a **shared buffer pool + lock + WAL** implementáció. Az actor modell **ugyanazt a relációs szemantikát** tudja, lock nélkül.

---

## 4. A jövő hálózata — Nincs kernel TCP/IP stack

### Ma: 80% overhead a kernelben

```
Alkalmazás
    ↓ syscall (~1-5 µs)
Kernel socket layer
    ↓ copy (~0.5-2 µs)
TCP/IP stack (kernel)
    ↓ copy (~0.5-2 µs)
NIC driver
    ↓
Hardver

Egy csomag feldolgozása: ~3-10 µs
Ebből ~80% a kernel overhead (mode switch, copy, lock).
```

### Actor hálózat: minden protokoll réteg egy aktor

```
┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────┐
│ NIC     │→ │ TCP     │→ │ HTTP     │→ │ App      │
│ device  │  │ aktor   │  │ parser   │  │ handler  │
│ aktor   │  │         │  │ aktor    │  │ aktor    │
└─────────┘  └─────────┘  └──────────┘  └──────────┘
    Mailbox →   Mailbox →   Mailbox →   Mailbox

Egy csomag feldolgozása: ~20-100 ns (4× mailbox hop)
Nincs syscall, nincs copy, nincs kernel.
Minden réteg egy aktor, pipeline-olt.
```

Ez az **Erlang/BEAM telecom modell, de hardverben**. Az Ericsson AXD 301 switch (1998) Erlang-ban 99.9999999% (kilenc kilences) uptime-ot ért el — szoftveresen, Erlang VM-ben, x86 felett. A CLI-CPU ugyanezt a modellt valósítja meg hardveresen, ~100× gyorsabban.

### A teljesítmény-különbség

| | x86 + Linux kernel TCP/IP | CLI-CPU actor pipeline |
|---|---|---|
| Csomag latency | ~3-10 µs | **~20-100 ns** |
| Csomag throughput (1 core) | ~1-5M pkt/s (DPDK nélkül) | **~30-100M pkt/s** |
| Kernel bypass (DPDK) szükséges? | Igen, komplex | **Nincs kernel, nincs mit bypass-olni** |

---

## 5. A jövő programozási modellje — Nincs async/await

### Ma: a „function color" probléma

```csharp
// A modern C# fejlesztés legnagyobb fájdalma
async Task<User> GetUserAsync(int id)
{
    var data = await _db.QueryAsync("SELECT...");
    var profile = await _cache.GetAsync(data.Key);
    return new User(data, profile);
}

// Ha BÁRMELYIK hívó elfelejti az await-et → bug
// Ha BÁRMELYIK réteget sync-ről async-re váltod
//   → MINDEN hívót át kell írni
// Két világ: sync és async — nem kompatibilisek
// Ez a "What Color is Your Function?" probléma (Bob Nystrom, 2015)
```

### Actor modell: nincs function color

```csharp
// Minden üzenet, minden szinkron az aktoron belül
class UserActor : Actor
{
    void OnGetUser(int id, ActorRef replyTo)
    {
        var data = Ask(dbActor, new Query("SELECT..."));
        var profile = Ask(cacheActor, new Get(data.Key));
        replyTo.Tell(new User(data, profile));
    }
}

// Nincs async/await — NINCS function color probléma.
// Minden hívás szinkron az aktoron BELÜL.
// A párhuzamosság az aktorok KÖZÖTT van.
// Nincs race condition — az aktor egyszerre egy üzenetet dolgoz fel.
```

**Miért működik ez?** Mert az `Ask()` **nem blokkolja a core-t** — a scheduler átkapcsol egy másik aktorra, amíg a válasz meg nem érkezik. A váltás költsége ~10-60 ciklus, nem ~1-5 µs.

### A programozási modell összehasonlítása

| Szempont | Mai C# (async/await) | Actor modell (Neuron OS) |
|---|---|---|
| Párhuzamosság egysége | Thread / Task | **Aktor** |
| Szinkronizáció | lock, Mutex, SemaphoreSlim | **Nincs** — üzenet |
| Megosztott állapot | Explicit védelem (lock) | **Nincs** — privát state |
| Async/await kell? | Igen, mindenhol | **Nem létezik** |
| Race condition | Lehetséges, nehéz debugolni | **Lehetetlen** |
| Deadlock | Lehetséges (lock sorrend) | **Lehetetlen** (nincs lock) |
| Tesztelhetőség | Mock-ok, integration tesztek | **Determinisztikus message replay** |

---

## 6. A nagy kép — a rétegek eltűnése

```
Mai világ (7 réteg):                 CLI-CPU világ (1 réteg):

┌─────────────────────┐             ┌─────────────────────┐
│ App (C#/Java/Go)    │             │                     │
│ async/await         │             │  Aktorok (C#)       │
├─────────────────────┤             │  szinkron üzenetek  │
│ Framework (ASP.NET) │             │                     │
│ thread pool         │             │  ← nincs határ      │
├─────────────────────┤             │  minden aktor       │
│ OS kernel (Linux)   │             │  egyenrangú         │
│ syscall, scheduler  │             │                     │
├─────────────────────┤             │  nincs kernel       │
│ TCP/IP stack        │             │  nincs syscall      │
│ socket API          │             │  nincs scheduler    │
├─────────────────────┤             │  (HW FIFO poll)     │
│ Filesystem (ext4)   │             │                     │
│ B-tree, WAL, lock   │             │  nincs lock         │
├─────────────────────┤             │  nincs B-tree       │
│ Hardver (x86)       │             │  nincs WAL          │
│ shared memory       │             │  nincs cache koher. │
│ cache koherencia    │             │  nincs VMM          │
│ MMU, TLB            │             │                     │
└─────────────────────┘             └─────────────────────┘

7 réteg, mindegyik                  1 réteg:
saját komplexitással,               aktorok üzeneteket küldenek.
interfészekkel, overhead-del.       A hardver natívan támogatja.
```

Minden réteghatár egy **absztrakciós adó**: syscall overhead, copy overhead, lock contention, context switch. A CLI-CPU-n ezek a határok **eltűnnek**, mert az egyetlen primitív — az üzenet — a hardverben él.

---

## 7. A fordított mérőszámok

Ahol ma a CLI-CPU hátrányban van, ott a szoftver stack újratervezése **megfordítja az előnyt**:

| Terület | Ma: CLI-CPU hátrány | Átgondolt szoftverrel: CLI-CPU ELŐNY |
|---|---|---|
| **Desktop app** | ~20× lassabb single-thread | Actor GUI: **párhuzamos layout/render**, nincs UI thread bottleneck |
| **Adatbázis** | Nincs shared memory SQL-hez | Actor DB: **lock-free**, ~100× gyorsabb INSERT, natív event sourcing |
| **Web szerver** | Kevés IPC | 1 request = 1 aktor: **~80M req/s** actor pipeline-ban |
| **Fájlrendszer** | Nincs block device driver | Minden fájl/dir egy aktor: **párhuzamos I/O**, nincs VFS lock |
| **Hálózat** | Nincs kernel TCP/IP | Actor pipeline: **~100× kevesebb latency**, nincs kernel copy |
| **Fejlesztés** | Ismeretlen platform | **Nincs async/await**, nincs lock, nincs race condition — **egyszerűbb kód** |

---

## 8. Miért nem csinálta meg ezt eddig senki?

**Mert nem volt hozzá hardver.**

Az ötlet nem új — az Erlang/BEAM 1986 óta az actor modellt használja, és az Ericsson telecom infrastruktúrája bizonyította, hogy működik. De az Erlang **szoftveresen**, x86 felett fut — a shared-memory overhead-et fizeti.

Az akadémiai kísérletek (MIT Alewife, Stanford DASH, Tilera TILE-Gx) megmutatták, hogy a sok-magos, message-passing architektúra lehetséges — de mind **regiszter gépek** voltak, nem managed runtime-ok, és a programozási modelljük C/C++ maradt.

A CLI-CPU az első kísérlet, ahol:
1. **A hardver natívan actor-modellt támogat** (mailbox FIFO, sleep/wake, shared-nothing)
2. **A programozási nyelv managed** (CIL/.NET — GC, type safety, verifikáció)
3. **Az egész stack újratervezhető** (Neuron OS, actor GUI, actor DB — nem x86-ot emulálunk)

Ez a három elem együtt **nem létezett eddig** — és a vízió azon áll, hogy **együtt kell, hogy legyen mind a három**, különben visszacsúszunk a shared-memory modellbe.

---

## 9. Az út

A vízió nem egyszerre valósul meg. A fejlesztési fázisok (`docs/roadmap-hu.md`) fokozatosan építik fel:

| Fázis | Szoftver vízió elem | Állapot |
|---|---|---|
| **F1-F1.5** | C# referencia szimulátor + linker + runner | **KÉSZ** |
| **F2** | RTL — a hardver megszületik | Következő |
| **F3** | Tiny Tapeout — első fizikai chip | — |
| **F4** | Multi-core FPGA — első actor rendszer, scheduler + router | — |
| **F5** | Rich core — teljes C#, heterogén Nano+Rich | — |
| **F6** | Cognitive Fabric — 32-48 core FPGA-n, a vízió demonstrálható | — |
| **F7** | Neuron OS SDK — az első fejlesztők actor GUI-t, actor DB-t írhatnak | — |

Az F7 után a vízió elemei **fokozatosan** épülnek: actor GUI toolkit, actor adatbázis motor, actor hálózati stack. Mindegyik **C#-ban**, a Neuron OS API-ra épülve, és mindegyik **nyílt forráskódú**.

A cél nem az, hogy lecseréljük a Linuxot vagy a PostgreSQL-t — hanem hogy egy **új kategóriát** teremtsünk, ahol az actor modell a természetes primitív, és a fejlesztők C#-ban a hardverhez illeszkedő szoftvert írhatnak.

---

## Hivatkozások

- [`docs/architecture-hu.md`](architecture-hu.md) — mikroarchitektúra, pipeline, memória modell, heterogén Nano+Rich design
- [`docs/neuron-os-hu.md`](neuron-os-hu.md) — a Neuron OS részletes víziója, aktor API, supervisor fa, scheduler, hot code reload
- [`docs/roadmap-hu.md`](roadmap-hu.md) — F0-F7 fázisterv
- [`docs/faq-hu.md`](faq-hu.md) — FAQ 5-7: CPU összehasonlítás, ütemezési költségek, igazságos összevetés
- [`docs/security-hu.md`](security-hu.md) — biztonsági modell, formális verifikáció terv
- [`docs/secure-element-hu.md`](secure-element-hu.md) — Secure Edition, multi-domain hardware isolation
