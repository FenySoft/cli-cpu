# Neuron OS — a CLI-CPU aktor-alapú operációs rendszere

> **Vízió dokumentum.** Ez az OS hosszú távú terve, amely F4 multi-core szimulátorral kezd kibontakozni, F5-F6 hardverrel éri el az első valós használhatóságot, és F7-ben lép ki kiforrott fejlesztői platform szinten.
>
> **A tartalom iránytű, nem végleges spec.** A részleteket menet közben, az F4–F6 tapasztalatok alapján finomítjuk. A cél itt az, hogy a tervezési döntések **irányt kapjanak**, és ne minden F4 iterációnál újra vitatkozzunk az alapelvekről.

> English version: [neuron-os-en.md](neuron-os-en.md)

> Version: 1.0

## Filozófia — az Unix örökség leváltása, az Erlang vízió megvalósítása

A **Neuron OS** célja egy olyan operációs rendszer megvalósítása, amelyben **minden entitás aktor**, és a kommunikáció **kizárólag üzenetküldéssel** történik. De ez nem csak egy alternatív megközelítés a Linux mellett — ez **egy új paradigma, amely hosszú távon a jelenlegi OS-ek által hordozott 1970-es évek öröklött döntéseit váltja fel**.

### A Linux és a Unix örökség — miért elavult alap

A Linux **1991-ben** született, a Unix pedig **1970-ben**. A kernel-tervezési döntéseket olyan **korban** hozták, amikor:

- **Egy CPU** volt a szerverben, egy magos
- **Kevés memória** állt rendelkezésre (KB-os nagyságrendben)
- **Drága hardver** kényszerített minimalizmust
- **Nem létezett hálózat** a mai értelemben
- **Nem volt kompakt biztonsági fenyegetettség** (nincs internet, nincs AI, nincs supply chain támadás)
- **Egyetlen felhasználó per gép** modell dominált
- **Shared memory olcsó volt**, message passing drága
- **Jelenlegi típusú párhuzamosság** (1000+ core, NUMA, distributed) nem létezett

Ezekre a feltételekre tervezték a **fork/exec/fd/signal/shared memory + mutex/POSIX permissions** modellt. **Ez az évtizedes múltra visszatekintő tervezés** hordozza magában a mai CPU-architektúrák **legtöbb sérülékenységét és korlátját**:

- **Monolit kernel** — 40 millió sor C kód, évi 500+ CVE, egyetlen driver bug → teljes rendszer crash
- **Shared memory + mutex** — race condition-ök, dead lock-ok, Spectre/Meltdown cache támadások
- **fork/exec** — nehéz context, drága rendszerhívás
- **POSIX permission modell** — 1970-es évek gondolkodása, minden globális névtér
- **Kernel / user mode switch** — drága, minden rendszerhívás ~1000+ ciklus overhead
- **Signal handler-ek** — nem újrabelépő, race condition-t kódolnak a szemantikába
- **Fájlrendszer mint univerzális absztrakció** — minden egy bájt-stream, ami nem illik sok modern adatstruktúrához
- **Shared library loading** — DLL hell, ABI bugok, supply chain támadások
- **systemd + cgroups + namespaces + containers** — réteges rárakott bonyolítás, mert az alap nem elég

**Ezek a problémák nem javíthatók patch-ekkel.** Architekturálisak, és ahogy a hardver változik (több core, több memória, gyorsabb hálózat, komolyabb biztonsági fenyegetettség, AI-s kód-generálás), **egyre fájdalmasabbak**. A Linux mérnökei folyamatosan küzdenek velük (kopyonwrite, rcu, lockless algoritmusok, eBPF, seccomp, io_uring), de **az alapvető paradigma nem változtatható**, mert a backward compatibility követelménye köti.

### A Neuron OS mint tiszta lapról indulás

A Neuron OS-t **modern korban** tervezzük, modern feltételekre:

- **Sok core** (10k+ lesz) — nem shared memory-val, hanem shared-nothing-gel
- **AI-s fenyegetettség** — hardveres memory safety, capability-based security
- **Distributed systems alapértelmezésben** — location transparency a lokális és remote között
- **Magas elvárás a fault tolerance iránt** — let it crash + supervision 40+ éve bizonyított Erlang-ban
- **Immutable adatok és funkcionális paradigma** — nem shared mutation, hanem üzenet-passing
- **Type safety alapértelmezésben** — nem választható add-on, hanem hardveres garancia
- **Hot code loading** — zero downtime, nem reboot patch ciklusok

Ez nem „még egy OS" — ez **egy új paradigma**, amely arra épül, amit az **Erlang/OTP 40 éve bizonyít** (fault tolerance, actor model, supervision), **a seL4 formálisan igazol** (capability security, mikrokernel), **a CHERI hardveresen kikényszerít** (capability enforcement), **a Singularity (Microsoft Research) megmutatott** (type-safe OS), és **a QNX kereskedelmileg demonstrált** (determinisztikus message-passing). **Mindezt egyetlen rendszerbe integrálva, hardveres támogatással**, ami eddig nem létezett.

### Miért most, és miért ez a pillanat

Eddig az aktor-alapú OS-ek **marginális nikében** maradtak, mert a szoftveres implementáció lassabb volt a hagyományos shared-memory OS-eknél. Joe Armstrong (Erlang atyja) 2014-es „The Mess We're In" előadásában pontosan erről beszélt: **szükség van egy olyan hardverre, amelynek architektúrája natívan aktor-orientált**. Akkor nem létezett ilyen — a nyílt forrású chip tervezés, a Tiny Tapeout, az eFabless Caravel mind 2020 után jelent meg.

**Ma van.** A CLI-CPU cognitive fabric architektúrája az első olyan **hardveres alap**, ahol az aktor modell **nem szoftveres overhead, hanem az architektúra alapja**:

- Minden core **fizikailag elszigetelt** saját SRAM-mal — nincs shared memory trükk
- A core-ok közötti üzenetküldés **hardveres mailbox FIFO-kon** megy, nem szoftveres queue-kon
- A context switch **~5-8 ciklus** (csak a TOS cache és a PC), nem 500-2000
- A supervisor trap **hardveres interrupt vonalon** érkezik egy másik core-nak, nem signal-alapú
- A capability model **hardveresen** kikényszerített, nem szoftveres check

Ebben az architektúrában **az aktor modell legnagyobb hátránya (a performance overhead) eltűnik**, és ami marad, az minden előnye — **sokkal erősebben, mint amit a Linux valaha is nyújthat** a backward compatibility terhe alatt.

A Neuron OS tehát **nem a Linux mellérakódik**, hanem **a Linux utóda**. Ahogy az x86 leváltotta a mainframe-et, a mobile leváltotta a desktopot, a cloud leváltotta a fizikai szervert — **a Cognitive Fabric + Neuron OS leváltja a shared-memory + Linux kombinációt** a most formálódó AI-vezérelt, biztonság-kritikus, masszívan elosztott korszakban.

## Tervezési alapelvek

### 1. Everything is an actor

Nincs kivétel. A kernel maga aktorok hierarchiája. A device driverek aktorok. A fájlrendszer aktorok. Minden alkalmazás aktor. Ha valami állapottal rendelkezik és üzeneteket dolgoz fel, akkor **aktor**.

Ez **drasztikusan egyszerűsíti** a rendszert: egyetlen alapvető absztrakciót kell értenie egy fejlesztőnek, és **ugyanaz az eszköz** szól a kernel programozáshoz, az alkalmazás fejlesztéshez, és a distributed rendszerhez.

### 2. No shared memory, ever

A core-ok között **nincs és sosem lesz** megosztott memória. Minden aktor saját privát SRAM-ban él, és az adatok **csak üzenetekkel** kerülhetnek egyik aktorhoz a másikhoz. Ez nem teljesítmény-korlát, hanem **architektúra-biztonság**.

Az üzenetek **immutable value type-ok** (CIL `struct`-ok vagy immutable osztályok), amelyeket a runtime másol (vagy zero-copy továbbít ugyanazon a core-on belül). **Nincs aliasing**, nincs data race.

### 3. Let it crash — strukturált fault tolerance

Egyetlen aktor sem **védekezik** minden lehetséges hibára. Ha hiba történik, **meghal**, és a **supervisor** dönti el, mi legyen: restart, escalate, vagy leállás. Ez az Erlang OTP modell, 40+ éven át bizonyítva telekommunikációs, pénzügyi és kritikus infrastruktúra környezetben.

A Neuron OS-ben ez **minden szinten** érvényes, a legkisebb device driver-től a legfelsőbb alkalmazás-aktorig.

### 4. Supervision hierarchia

Minden aktornak van egy **supervisor-a**. A supervisor egy másik aktor (az első aktornak egy primer „root supervisor", amit a boot loader hoz létre). A supervisor-gyermek kapcsolat egy **fát** alkot:

```
            root_supervisor
                 │
       ┌─────────┼─────────┐
       │         │         │
   device_sup   app_sup   net_sup
     │            │         │
   ┌─┴─┐       ┌──┴──┐   ┌──┴──┐
 uart gpio   neural worker tcp  ble
```

Egy hiba **csak a saját supervisor-fájának aljáig terjed**, és ott megáll. Ha egy levél aktor hibázik, csak azt indítjuk újra. Ha egy belső csomópont hibázik, az egész alszerkezet újraindul. Ha a `root_supervisor` hibázik, a rendszer reboot-ol — de ez ritka, mert ő nagyon egyszerű.

### 5. Location transparency

Egy aktor referencia **nem árulja el**, hogy a target lokális (ugyanezen a core-on), másik core-on, vagy másik chipen van. Ugyanaz a `send(actor_ref, msg)` működik minden esetben, és a router (hardveres + szoftveres) eldönti, hová kerül az üzenet.

**Következmény:**
- Az aktorok **futás közben áthelyezhetők** core-ok között (load balancing)
- Egyetlen Neuron OS **több chipre is elterjedhet** (F7+ elosztott)
- A lokális és elosztott rendszer **ugyanazt a kódot** futtatja

### 6. Capability-based security

Egy aktor **csak akkor** tud üzenetet küldeni egy másiknak, ha ismeri a referenciáját. A referencia egy **capability** — birtoklás = jogosultság. Nincs globális névtér (mint a Unix `/dev/sda`), nincs „root" mindenható felhasználó.

Ez a CHERI és a seL4 biztonsági modellje, amit a Neuron OS natívan használ, **mert a hardver (CLI-CPU) eleve shared-nothing**.

### 7. Hot code loading

Egy **futó rendszerbe új CIL kódot lehet tölteni** leállás nélkül. Egy aktor fogadhatja az utolsó üzenetet a `v1` verzióval, és a következőt a `v2` verzióval — **a supervisor** koordinálja az átállást. Ez az Erlang OTP 40 éves funkciója, amit a Neuron OS natívan támogat.

A **writable microcode SRAM** (F6+ Rich core) lehetővé teszi, hogy **új opkód-szemantikát is** felülíjrunk futás közben, ha szükséges — pl. hibafixet push-olni egy élő rendszerbe.

### 8. Determinism by default

A Neuron OS alapértelmezésben **determinisztikus**: ugyanaz a bemenet-sorozat ugyanazt az állapotot eredményezi. Ez:
- Reprodukálható bug-okat ad
- **Message replay** alapú debuggolást tesz lehetővé
- Formális verifikációra alkalmas
- Tanúsítható (IEC 61508, ISO 26262) rendszerekhez illeszkedik

Nem-determinisztikus viselkedés **explicit** — időzítés, véletlen szám, külső I/O — és mindig látható a kódban.

## A Linux öröklött problémái és a Neuron OS válasza

Ez az a szekció, amely konkrét összehasonlítással mutatja, miért **nem a Linux mellett** akarunk létezni, hanem **a Linux örökségét felváltani** a modern követelményekre szabott alapokon.

| Probléma-kategória | Linux (Unix-örökség) | Neuron OS |
|-------------------|----------------------|-----------|
| **Kernel architektúra** | Monolit kernel, ~40 M sor C, egyetlen driver bug = system crash | Mikrokernel aktor-hierarchia, ~1-2k sor kernel, driver crash = supervisor restart |
| **Biztonsági incidensek** | ~500+ CVE/év, kernel exploitok gyakoriak (Dirty Pipe, Dirty COW, stb.) | Architekturálisan kizárt ROP/JOP/buffer overflow/JIT spray, formálisan verifikálható |
| **Concurrency modell** | pthread + mutex + shared memory → race conditions, dead locks, memory corruption | Aktor modell, immutable messages, **architekturálisan race-free** |
| **Skálázódás sok magra** | Lock contention, RCU komplexitás, NUMA effects, 128+ core-ra nehéz | **Lineáris** skálázódás, nincs lock, nincs cache coherency traffic |
| **Hibakezelés** | Kernel panic → reboot, segfault → crash, supervisor systemd rárakott | Let it crash + supervision tree, 9-nines availability (Erlang bizonyítja) |
| **Distributed systems** | POSIX ≠ network API, két különböző programozási modell, Docker/K8s rárakott | **Location transparency** natívan — lokális és remote ugyanaz a kód |
| **Frissítés** | Restart szükséges, kernel live patching komplex és korlátozott | **Hot code loading** leállás nélkül, Erlang-stílusban |
| **Driver modell** | Kernel módban, bug = kernel crash | User-space aktor, crash = supervisor restart |
| **Memory safety** | Manual (C), unsafe by default, Rust az új remény, de a meglévő 30 M sor C marad | **Per-aktor GC, type-safe by default, architekturálisan garantált** |
| **Namespace modell** | Globális (/dev/sda, fájlrendszer, PID tábla) | **Capability-based** — nincs globális névtér, birtoklás = jogosultság |
| **Kernel/user mode** | Expensive context switch (~1000+ ciklus per syscall) | **Nincs kernel/user mód** — minden aktor, hardveres isolation |
| **POSIX permission** | 1970-es gondolkodás (user, group, other, rwx) | Capability (fine-grained, delegálhat, revokálható, HMAC-aláírt) |
| **IPC primitívek** | 7+ mechanizmus (pipes, sockets, shared memory, message queues, signals, semaphores, futex) | **Egyetlen** primitiv — mailbox üzenetküldés (minden másra lebontható) |
| **Fájlrendszer** | Univerzális absztrakció (bytes stream), de nem illik minden adatstruktúrához | Aktor-alapú storage service, strukturált |
| **Shared library** | DLL hell, ABI bug, supply chain támadás (log4j, xz-utils) | Hot code loading aktor-szinten, mindegyik önálló, tree-shaken |
| **Container technológia** | Docker/K8s rárakott réteg a namespace+cgroups-re | Natív aktor isolation, nincs szükség containerekre |
| **Determinizmus** | Nem-determinisztikus (ütemező, kernel preempció, cache viselkedés) | **Determinisztikus** alapértelmezésben |
| **Formális verifikáció** | Gyakorlatilag lehetetlen a méret és komplexitás miatt | **Megvalósítható** (seL4 bizonyítja), a CLI-CPU ISA formálisan leírható |
| **Biztonsági tanúsítás** | Lehetséges, de 10+ év egy EAL-5+ Linux disztribúciónak | Natívan tanúsítható (IEC 61508, ISO 26262, DO-178C, IEC 62304) |
| **Történeti gyökér** | Multics 1964, Unix 1970, Linux 1991 | 2020+, minden modern tanulsággal (Erlang 1986, seL4 2009, Singularity 2003) |

**Ez nem kisebb optimalizáció** a Linux modellén — **ez egy alapvetően más paradigma**, amely olyan problémákat old meg, amiket a Linux architektúrálisan nem tud.

### Mit tanulunk a Linux sikeréből

Legyünk őszinték: a Linux **hatalmas siker**. Évi $15+ milliárd vállalati ökoszisztéma, futtat minden modern felhőt, minden Android telefont, minden szupercsomópontot. Ezt **nem lehet figyelmen kívül hagyni**, és a Neuron OS-nek sem szabad azt hinnie, hogy egy éjszaka alatt leváltjuk.

Amit tanulunk a Linux sikeréből:
- **Nyílt forráskód** — közösségi fejlesztés, átlátható döntések
- **Permissive licenc** — Apache 2.0 vagy MIT, nem szigorú GPL
- **Modularitás** — minden komponens cserélhető
- **Jó dokumentáció** — a Linux-kernel docs évek óta javult
- **Eszköz-ökoszisztéma** — fordítók, debuggerek, profilok, testers
- **Hardver támogatás** — sok driver, sok platform

A Neuron OS **minden ilyenre** törekszik, de **más alapokon**.

### Mi lesz a Linux-szal?

A Neuron OS **nem akarja, hogy a Linux egyik napról a másikra eltűnjön**. A valós átmenet hosszú távú, talán **10-20 év**:

| Időszak | Linux pozíciója | Neuron OS pozíciója |
|---------|-----------------|---------------------|
| **2026-2030** | Uralkodó mindenhol | F1-F6 fejlesztés, F6 első szilícium, Cognitive Fabric bizonyítás, beágyazott niche |
| **2030-2035** | Uralkodó desktop, server, mobile-on; regulated industries-ben kihívásokkal | Kereskedelmi termékek specifikus vertikumokban: AI safety, kritikus infra, automotive, medical |
| **2035-2040** | Konzervatív cloud, legacy | Új cloud architektúrák Cognitive Fabric-on (aktor-alapú hyperscalerek); edge computing domináns |
| **2040-2050** | Legacy support | Új rendszerek alapértelmezett platformja, a Linux szerepét betölti a Neuron OS |

**Ez nem garancia**, csak egy lehetséges jövőkép. De **világosan fogalmazzunk**: a cél nem a Linux **mellett élés**, hanem a **Linux utódjának szerepének betöltése** egy hosszú, szerves átmenet során. Ahogy az x86 leváltotta a mainframe-et (1980-2000), ahogy a mobile leváltotta a desktopot (2007-2020), ahogy a cloud leváltotta az on-prem-et (2010-2025) — **a Cognitive Fabric + Neuron OS lesz a következő leváltási ciklus**, amely 2026-tól indul.

## Rendszerarchitektúra — aktorok hierarchiájaként

A Neuron OS **nem kernel/user mód** felosztású rendszer. Nincs kernel tér és user tér elkülönítés, mert **a hardveres isolation** (shared-nothing multi-core) már garantálja azt, amit más OS-ek a kernel/user mód switch-csel oldanak meg. Ehelyett **privilégium-szintek aktor-kapcsolatokkal** vannak kifejezve: egy aktor akkor tud egy privilegált műveletet (pl. DMA, hálózati hardver) használni, ha ismeri a **device aktor** referenciáját.

### Boot időbeli aktor-hierarchia

```
  [bootloader]         — a Rich core flash-ről fut, R/O CIL kód
       │
       ▼  létrehozza
  [root_supervisor]    — az első aktor, ami fut
       │
       ▼  létrehozza a kernel aktorokat
  ┌────┴────────────────────────────┐
  │                                 │
[kernel_core_sup]            [kernel_io_sup]
  │                                 │
  ├─ [scheduler]                    ├─ [uart_device]
  ├─ [router]                       ├─ [gpio_device]
  ├─ [memory_manager]               ├─ [timer_device]
  ├─ [capability_registry]          └─ [flash_device]
  └─ [hot_code_loader]
       │
       ▼  amikor az application aktorokat elindítjuk
  [app_supervisor]
       │
  ┌────┴────────────────────────┐
[neural_worker_sup]         [network_sup]
  │                             │
  ├─ [neuron_0001]             ├─ [tcp_manager]
  ├─ [neuron_0002]             ├─ [udp_manager]
  ├─ ... (pl. 48 db neuron)    └─ [ble_manager]
  └─ [neuron_coordinator]
```

### Kernel aktorok (root level)

Ezek a Neuron OS „kernelje", de nem kernel módban, hanem **néhány Rich core-on futó speciális aktor**:

1. **`root_supervisor`** — az első aktor, a többi szülője. Nagyon egyszerű, csak restart logika. Soha nem hibázik, mert nincs mit tennie rosszul.
2. **`scheduler`** — eldönti, melyik aktor melyik core-on fut. Nem preemptív (az aktorok kooperatívan adják át a vezérlést, üzenet-feldolgozási határokon), **de a supervisor képes leállítani** egy beragadt aktort.
3. **`router`** — a szoftveres kiegészítő a hardveres mailbox router felett. Globális címekre fordítja a logical aktor referenciákat (fizikai core + mailbox offszet). Load balancing, migration.
4. **`memory_manager`** — bár minden core-nak saját SRAM-ja van, a Rich core-ok heap-je közös allokációs pool-ból jön. A memory manager ennek a poolnak az adminisztrátora.
5. **`capability_registry`** — az aktor referencia → capability kapcsolatok nyilvántartása. Egy aktor csak akkor kaphat referencia, ha a registry kibocsát neki egyet.
6. **`hot_code_loader`** — új CIL binárisokat fogad (pl. flash frissítésből vagy hálózatról), ellenőrzi őket (verifikálja, hogy csak az engedélyezett opkódok vannak benne), és betölti őket futó aktorokba.

Minden kernel aktor **egyetlen core-on** fut (Rich), és **szupervised** a `root_supervisor` által.

### Device aktorok

Minden hardveres periféria egy **device aktor**, amely az adott periféria MMIO régióját kezeli. Az alkalmazások **nem férnek közvetlenül** a hardverhez, csak a device aktor üzenetein keresztül.

```
[uart_device] actor:
  - saját mailbox (bejövő: alkalmazás kéri az írást/olvasást)
  - kezeli a 0xF0000000-F00000FF UART MMIO-t
  - két gyermek aktor: uart_tx, uart_rx
  - supervisor: kernel_io_sup
```

A capability: **ha egy alkalmazás birtokolja** a `uart_device` referenciát, akkor tud UART-ra írni. Különben **nincs módja**, hogy UART-ot érintsen.

## Aktor életciklus

Egy aktor életének fázisai:

### 1. Create
A szülő aktor `spawn(child_code, init_state)` üzenetet küld a `scheduler`-nek. A scheduler:
- Kiválaszt egy core-t (load balance alapján)
- A core-ra betölti a CIL kódot (már ott, ha statikusan linkelt; egyébként hot code loader)
- Inicializálja az aktor állapotát a megadott kezdőértékkel
- Capability-t bocsát ki az új aktor-nak
- **Referenciát ad vissza** a szülőnek

### 2. Start
Az aktor belép a `main loop`-ba:
```csharp
while (running) {
    var msg = WaitForMessage();  // alvás, ha üres mailbox
    state = HandleMessage(msg, state);
    if (state.ShouldStop) running = false;
}
```
A `WaitForMessage()` hardveres wait-for-interrupt, tehát a core **fizikailag alszik**, ha nincs üzenet.

### 3. Run
Az aktor üzeneteket dolgoz fel, állapotot változtat, más aktoroknak üzen. **Kooperatív multitasking**: a scheduler **nem** szakítja félbe az üzenet-feldolgozást (kivéve, ha egy watchdog timer triggerel).

### 4. Suspend (opcionális)
A scheduler képes **áthelyezni** egy aktort egyik core-ról másikra (load balancing). Ez:
- Megvárja, amíg az aktor befejezi a jelenlegi üzenetet
- Szerializálja az állapotot
- Új core-on rekonstruálja
- A router frissíti a referenciát

### 5. Migrate (Nano → Rich)
Ha egy Nano core aktor olyan műveletet igényel, ami csak Rich core-on megy (pl. objektum allokáció, kivétel, FP), **migrálhat**. Két módon:
- **Explicit migráció**: az aktor kód `MigrateToRich()` hívást tesz, és az állapota átkerül egy Rich core-ra
- **Trap-alapú migráció**: egy Nano core `UNSUPPORTED_OPCODE` trap-et lő, a trap handler egy Rich core-ra migrálja az állapotot

A második csak **vészhelyzeti**, a tervezés arra törekszik, hogy a kód **eleve** a megfelelő core típusra legyen jelölve (`[RunsOn]` attribútum).

### 6. Stop
Az aktor saját maga dönthet a leállásról (normál kilépés), vagy a supervisor állíthatja le (explicit stop). Mindkét esetben:
- A mailbox maradék üzenetei **deadletter queue-ba** kerülnek (opcionálisan a supervisor-hoz)
- Az állapot felszabadul
- A capability visszavonódik
- A szülőt értesíti a scheduler (lehetővé téve a respawn-t)

### 7. Crash + Restart
Ha az aktor hibát okoz (`OVERFLOW` trap, `NULL_REFERENCE` trap, stb.), a hardveres exception unwinder **értesíti a supervisor-t** egy hardveres interrupt vonalon. A supervisor:
- Megkapja a `{crashed, actor_ref, reason}` üzenetet
- Dönt: **restart** (ugyanabba az állapotba, mint a spawn), **escalate** (a saját supervisor-ához), vagy **stop** (végleges leállás)

Az Erlang OTP négyféle restart stratégiát definiál: `one_for_one`, `one_for_all`, `rest_for_one`, `simple_one_for_one`. A Neuron OS ugyanezeket támogatja.

## Message routing

### Szintek

A üzenet eljuthat a célhoz **négy úton**, egyre drágábban:

1. **Lokális** (ugyanazon a core-on, ugyanazon az aktoron belüli belső üzenetek) — ~1–3 ciklus, zero copy
2. **Inter-core** (ugyanazon a chipen, másik core-on) — ~10–20 ciklus, hardveres mailbox FIFO-n át
3. **Inter-chip** (elosztott, másik Neuron OS node-on) — ~100–1000 ciklus, egy dedikált network aktoron keresztül
4. **Wide area** (interneten át egy másik földrajzi node-hoz) — ~ms, szintén network aktoron át

A router **transparensen** kezeli mind a négyet. A fejlesztő ugyanazt a `send(ref, msg)` hívást használja.

### Üzenet szerkezet

```csharp
public struct Message {
    public int  MessageId;       // globálisan unique
    public int  SenderActorRef;  // ki küldi
    public int  ReceiverActorRef;// kinek
    public int  MessageKind;     // mi a típusa (struct hash)
    public long Timestamp;       // mikor küldve (determinism)
    public int  PayloadSize;     // payload mérete byte-ban
    // + payload bytes
}
```

A payload **immutable value type**, CIL `struct` vagy immutable osztály. A fejlesztő **nem küldhet** mutable object referenciát, mert a fordító (`cli-cpu-link`) build-time ellenőrzi.

### Priority vs FIFO

A mailbox alapértelmezésben **FIFO** — az üzenetek érkezési sorrendben dolgozódnak fel. De egy aktor explicit **prioritásos** mailbox-ot is választhat, ahol magas prioritású üzenetek (pl. `system_shutdown`, `supervisor_kill`) átugorhatják a sort. Ez **opt-in**, nem default.

### Backpressure

Ha egy mailbox telítődik (a hardveres FIFO 8 mélységű F3-ban, ~64 mélységű F6-ban), a küldő **blokkolódik** (vagy `SendError` trap-et kap, ha `try_send`-et használt). Ez **természetes flow control**, nincs szükség explicit rate limit-re.

## Memóriakezelés

### Per-core privát SRAM

Minden core **saját 16–256 KB SRAM-mal** rendelkezik, amely **csak az adott core-nak** látszik. A core saját:
- Eval stack
- Lokális változók
- Frame-ek (hívásonként)
- Heap (Rich core-on, Nano core-on nincs)

A core-ok **nem látják egymás memóriáját**. A „megosztás" csak üzenetkopírozással lehetséges.

### Per-core privát GC

A Rich core-oknak saját **bump allocator + mark-sweep GC**-juk van. **Nincs globális GC**, **nincs stop-the-world az egész chipre**. Ha egy core GC-t futtat, a többi core ettől **teljesen függetlenül** dolgozik.

Ez a shared-nothing modell **egyik legnagyobb egyszerűsítése**. Az Akka.NET-ben a globális .NET GC a szűk keresztmetszet magas terhelésen; a Neuron OS-en **ez a probléma nem létezik**.

### Zero-copy üzenet (lokális)

Ha egy aktor üzenetet küld egy másik aktoron belül **ugyanazon a core-on**, a runtime észlelheti ezt és **zero-copy** módon továbbítja (csak a pointer-t adja át). A cél aktor a saját view-jában látja az üzenetet.

**Inter-core esetén** a runtime **kopírozza** az üzenetet a küldő core SRAM-jából a fogadó core SRAM-jába a mailbox FIFO-n keresztül. Ez ~10–30 ciklus, méret-függő.

## Capability-alapú biztonság

### A capability fogalma

Egy **capability** egy nem-hamisítható token, amely egy konkrét jogosultságot reprezentál. A Neuron OS-ben **az aktor referencia maga egy capability**:

```csharp
ActorRef uartDevice = ...;  // ez egy capability
uartDevice.Send(new WriteByte(0x41));  // csak azért megy, mert van referenciám
```

A kapott `ActorRef` **nem egy szám**, hanem egy strukturált token:
```csharp
public struct ActorRef {
    public int  CoreId;
    public int  MailboxIndex;
    public long CapabilityTag;  // HMAC-szerű, a capability_registry által aláírva
    public int  Permissions;    // read, write, forward, revoke, ...
}
```

A `CapabilityTag`-et a `capability_registry` állítja ki, és a hardveres router **ellenőrzi** minden üzenet küldésnél. Hamisított vagy lejárt capability esetén a router **eldobja** az üzenetet és trap-et generál a küldőnek.

### Delegation és revocation

- **Delegation**: egy aktor **átadhatja** a referenciáját egy másiknak (üzenetben). A címzett ezzel tud a target-nek üzenni. Ez jogosultság átadás, anélkül hogy a target tudna róla.
- **Revocation**: az eredeti kibocsátó (pl. a `root_supervisor`) **visszavonhatja** egy capability-t. Ezután bárki, aki azt a tag-et birtokolja, elveszti a jogot. A `capability_registry` kezeli.

### Isolation garanciája

A CLI-CPU hardveres **shared-nothing** architektúrája a következőt garantálja:
- Egy aktor **nem** tud írni egy másik aktor memóriájába — a hardver fizikailag nem engedi
- Egy aktor **nem** tud hívni egy másik aktor kódját — csak üzeneteken keresztül
- Egy aktor **nem** tud elérni egy perifériát, ha nem ismeri a device aktor referenciáját
- Egy aktor **nem** tud megtévesztő üzenetet küldeni egy másik aktor nevében — a router ellenőrzi a küldő capability-jét

**Ez egy hardveresen megvalósított capability-based OS** — amit eddig csak a seL4 és a CHERI kínált akadémiai szinten, és amit a Neuron OS a .NET világba hoz.

## Dinamikus kód betöltés

### Hot code loading

Egy futó Neuron OS-be **új CIL kódot** lehet betölteni leállás nélkül. A folyamat:

1. Egy külső forrás (flash frissítés, hálózati üzenet, USB) elküldi az új CIL binárist a `hot_code_loader` aktornak
2. A loader **verifikálja**: opkód-whitelist, capability check, signature check
3. A loader **betölti** az új kódot egy Rich core-ra (a code ROM-ba, ha writable microcode + írható SRAM szegmens van)
4. A loader **üzenetet küld** minden érintett aktor-nak: „új verzió érhető el"
5. Minden aktor **üzenet-feldolgozási határon** (tehát konzisztens állapotban) átvált az új kódra
6. Az új üzenetek már a `v2` kóddal dolgozódnak fel, de a **jelenlegi állapot megmarad**

**Ez kritikus fontosságú** olyan rendszerekben, ahol a leállás nem megengedett: telekommunikáció, kritikus infrastruktúra, medical, automotive.

### Új aktor dinamikusan indítása

Egy futó aktor **új aktort hozhat létre** futás közben:

```csharp
public async Task HandleRequest(IncomingRequest req) {
    // létrehozunk egy új aktort a kéréshez
    var workerRef = await Spawn<RequestWorker>(req.InitialState);
    workerRef.Send(new ProcessRequestMsg(req));
}
```

A scheduler **dinamikusan** talál egy szabad core-t (vagy várakozó sort épít, ha minden foglalt). Ez az „egy kérés = egy aktor" modell, amit az Erlang 40 éve csinál.

### Writable microcode — F6-tól

A Rich core-nak **writable microcode SRAM**-ja lesz F6-tól. Ez lehetővé teszi, hogy **új CIL opkód-szemantikát** töltsünk le futás közben. Használati esetek:
- **Bugfix** egy mikrokódos opkódban (pl. egy ritka kivétel-eset javítása)
- **Új opkódok** bevezetése, ha az ECMA-335 új verziója fontos opkódot ad
- **Specializált workload-ra** optimalizált mikrokód (pl. kriptó gyorsítás)

## I/O modell

### Device aktorok

Minden hardveres periféria egy **device aktor** a Neuron OS-ben. A device aktor:
- Birtokolja az adott periféria MMIO régióját
- Képes üzeneteket fogadni, amik a perifériával kapcsolatos műveleteket kérnek
- Képes üzeneteket küldeni (pl. beérkezett UART byte-okról az előfizetett olvasó aktor-nak)

**Példa: UART device aktor**

```csharp
[RunsOn(CoreType.Rich)]  // a kernel_io_sup fa része
public class UartDevice : DeviceActor {
    // hardver MMIO cím
    const uint UART_DATA = 0xF0000000;
    const uint UART_STATUS = 0xF0000004;

    ActorRef? _subscriber;  // aki RX byte-okat akar kapni

    public override async Task HandleAsync(Message msg) {
        switch (msg) {
            case WriteByteMsg wb:
                // blokkolva vár, amíg TX ready
                while ((Read(UART_STATUS) & TX_READY_BIT) == 0) await Yield();
                Write(UART_DATA, wb.Byte);
                break;

            case SubscribeRxMsg sub:
                _subscriber = sub.Subscriber;
                break;

            case RxInterruptMsg:
                var byteVal = Read(UART_DATA);
                _subscriber?.Send(new RxByteMsg((byte)byteVal));
                break;
        }
    }
}
```

### Perifériák tulajdonjoga — capability

Ahogy említettem: a device aktor **capability-je** dönti el, ki férhet a perifériához. Az `app_supervisor` dönt, hogy az alkalmazásoknak mely device aktor-okhoz **adja át** a capability-t. Ha egy alkalmazás nem kapott `uart_device` referenciát, **fizikailag** nem tud UART-ra írni.

### Fájlrendszer — mint aktor service

A fájlrendszer (ha van) szintén **aktorok halmaza**:

- Egy `flash_device` aktor kezeli a QSPI flash hardvert
- Egy `block_service` aktor épít rá blokk-absztrakciót
- Egy `fs_service` aktor fájlrendszer szemantikát ad (olvasás, írás, könyvtár)
- Egy `file_handle` aktor minden nyitott fájl-ra (mint az Erlang port)

A „fájl megnyitása" = `fs_service` aktor-nak üzenet, ami egy új `file_handle` aktort spawn-ol. A fájl bezárása = a `file_handle` aktor leállítása.

**Ez eltér a POSIX modelltől**, de természetesen illeszkedik az aktor OS-hez, és a kompatibilitást egy **POSIX-kompatibilitási réteg** adhatja a tetején az F7 után — ha egyáltalán szükséges.

## Fejlesztői API — C# szintén

A fejlesztő **nem** kernel-programozóként gondolkodik, hanem **C# programozóként** egy **aktor-orientált frameworkkel**. Az API nagyjából az Akka.NET-re hasonlít, de a runtime hardveresen támogatott.

### Alap aktor

```csharp
using NeuronOS;

public class CounterActor : Actor<CounterState> {
    public override CounterState Init() => new CounterState(Value: 0);

    public override CounterState Handle(CounterState state, Message msg) => msg switch {
        IncrementMsg => state with { Value = state.Value + 1 },
        GetValueMsg g => Reply(g.Sender, new ValueMsg(state.Value)).Then(state),
        _ => state
    };
}

public record CounterState(int Value);
public record IncrementMsg;
public record GetValueMsg(ActorRef Sender);
public record ValueMsg(int Value);
```

### Supervisor

```csharp
public class AppSupervisor : Supervisor {
    public override SupervisorSpec Init() => new SupervisorSpec(
        Strategy: RestartStrategy.OneForOne,
        MaxRestarts: 3,
        Period: TimeSpan.FromMinutes(1),
        Children: [
            new ChildSpec<CounterActor>("counter1", autoStart: true),
            new ChildSpec<CounterActor>("counter2", autoStart: true),
            new ChildSpec<NeuralWorkerSup>("neural_workers", autoStart: true),
        ]);
}
```

### Spawn + üzenetküldés

```csharp
var counter = await Spawn<CounterActor>();
counter.Send(new IncrementMsg());
counter.Send(new IncrementMsg());
counter.Send(new IncrementMsg());

// szinkron lekérdezés (wrapper egy mailbox-on)
var value = await counter.Ask<ValueMsg>(new GetValueMsg(Self));
Console.WriteLine($"Counter: {value.Value}");
// output: Counter: 3
```

### Core típus-attribútum

```csharp
[RunsOn(CoreType.Nano)]
public class LifNeuronActor : Actor<LifNeuronState> {
    // csak integer, csak fixed-size, nincs objektum allokáció a belsejében
    // a cli-cpu-link tool build-time ellenőrzi
}

[RunsOn(CoreType.Rich)]
public class SnnCoordinatorActor : Actor<CoordinatorState> {
    // teljes CIL funkcionalitás: List<T>, Dictionary, exceptions, FP
}
```

### Distributed aktor (F7)

```csharp
// Ha a Neuron OS több chipen fut elosztva:
var remoteActor = ActorRef.FromUri("neuron://chip2.local/neural_workers/neuron_0042");
remoteActor.Send(new SpikeMsg(weight: 100));
// a lokális router észleli, hogy remote, és a network_device aktornak küldi át
```

## Kapcsolat a Cognitive Fabric pozicionálással

A Neuron OS **nem egy külön termék** a CLI-CPU hardverhez képest — **hanem az a szoftveres réteg, ami a Cognitive Fabric pozicionálást valódivá teszi**. Ugyanaz a hardver (CLI-CPU multi-core + mailbox + heterogén Nano+Rich) **különböző** használati módokat támogat **ugyanazzal** a Neuron OS alapján:

| Használati mód | Mit futtatnak az aktorok | Supervisor fa jellemző |
|---------------|--------------------------|------------------------|
| **Akka.NET cluster** | Üzleti logika, szolgáltatások | Hierarchikus service supervisor |
| **Spiking Neural Network** | LIF/Izhikevich neuron modellek | Flat, egy coordinator supervisor |
| **Multi-agent szimuláció** | Agent AI + environment | Per-environment supervisor |
| **Event-driven IoT edge** | Szenzor handlerek + protokoll processzorok | Device-to-app hierarchikus |
| **Telekommunikációs stack** | Hívás-kezelés, session management | Per-call supervisor (Erlang-stílus) |
| **Blockchain validator** | Konszenzus + tranzakció-verifikáció | Flat, peer-based |

**Ugyanaz az operációs rendszer**, **ugyanaz a hardver**, **ugyanaz a programozási modell** — **más** application aktorok, **más** szerepek. A Neuron OS a „lingua franca", ami minden Cognitive Fabric alkalmazást egységes platformra tesz.

## Fázisos megvalósítás

A Neuron OS **nem egy nagy ugrás**, hanem **organikusan épül fel** az F1–F7 fázisok során, minden fázisban hozzáadva a következő réteget.

### F1 — Minimal runtime a C# szimulátorban
**Kimenet:** egyszerű „aktor futtató", ami a szimulátoron belül ad aktor-szerű absztrakciót.
- Alap `Actor<T>` osztály
- In-memory mailbox
- Spawn / send / receive
- Egy statikus supervisor (no restart)

Ez **nem valódi OS**, csak egy programozási keret, ami már most segít a programokat aktor-orientáltan írni.

### F3 — Tiny Tapeout bootloader
**Kimenet:** egy minimális boot CIL program, ami:
- Betöltődik a QSPI flash-ből
- Inicializálja a stack-et, a mailbox MMIO-t, a UART-ot
- Elindít egy single aktort (pl. az „echo neuron"-t)
- Az UART-ra érkező bájtokat mailbox-on át továbbítja, a kimeneti bájtokat is onnan veszi

**Ez az első valódi hardveres „Neuron OS"**, bár még csak egy-aktoros.

### F4 — Multi-core scheduler + router
**Kimenet:** a 4-core FPGA rendszeren:
- Egyetlen `scheduler` aktor, ami a core-okra allokálja a többit
- `router` aktor, ami az inter-core üzeneteket irányítja
- Minimal supervisor — crash → UART log, manual restart
- Parancssor a UART-on keresztül: spawn, send, kill

Ez **4 aktoros rendszer**, ahol már a scheduler + router valódi szerepet játszik.

### F5 — Supervision hierarchia + lifecycle + GC
**Kimenet:** a heterogén Nano+Rich FPGA-n:
- Teljes supervisor fa (OneForOne, OneForAll, RestForOne)
- Per-core GC a Rich core-on
- Capability-alapú isolation hardveresen (mailbox target-ellenőrzés)
- Aktor migráció Nano → Rich trap-en keresztül
- `[RunsOn]` attribute Roslyn source generator

Ez **az első felhasználható Neuron OS**, amely képes valós C# programokat futtatni aktor-orientált módon.

### F6-FPGA — Hot code loading, distributed multi-board
**Kimenet:** 3× A7-Lite 200T multi-board Ethernet hálón:
- Hot code loading aktorok szintjén
- Több chip közötti elosztott aktor rendszer (Ethernet bridge)
- Location transparency valódi tesztje — cross-chip aktor kommunikáció
- Teljes capability registry aláírással

Ez az **FPGA-verifikált, elosztott** Neuron OS — a valódi multi-chip Cognitive Fabric első demonstrációja.

### F6-Silicon — Writable microcode, szilícium verifikáció
**Kimenet:** ChipIgnite real silicon (csak F6-FPGA verifikáció után):
- Az F6-FPGA-n verifikált elosztott OS egyetlen chipre integrálva
- Writable microcode SRAM (silicon-specifikus)
- Energia hatékonyság és órajel mérés

Ez a **szilíciumra érett** Neuron OS.

### F7 — Fejlesztői SDK + referencia alkalmazások
**Kimenet:** publikus platform:
- `dotnet publish` target Neuron OS-re
- VSCode / VS extension debugger
- NuGet csomagok (`NeuronOS.Core`, `NeuronOS.Actor`, `NeuronOS.Devices`)
- Referencia demó alkalmazások: SNN, Akka.NET port, IoT gateway, multi-agent sim
- Publikáció + előadás + Linux Foundation projekt státusz

**Ez a Neuron OS kijutása a kutatási szintről a valós fejlesztői platform szintjére.**

## Prior art — mit tanulunk más rendszerektől

### Erlang/OTP (Ericsson, 1986)
**A legnagyobb inspiráció.** 40 év éles szolgálat telekommunikációs, pénzügyi, nagy skálájú rendszerekben. Supervision, hot code loading, let it crash, location transparency — mindez tőlük jön.

**Amit átveszünk:** a teljes programozási paradigmát, a supervisor stratégiákat, a naming konvenciókat, a message passing szemantikát.

**Amit NEM**: a BEAM VM-et (az szoftveres, nálunk hardveres). A dinamikus típusok nélküli nyelvet (mi C#-ot használunk). A Prolog-szerű pattern matching-et (C# switch expression elég).

### QNX (1982)
**Kereskedelmi mikrokernel message passing OS-szel.** Beágyazott, autóipari, medical, repülőgép (BMW iDrive, RIM/BlackBerry, Cisco routerek).

**Amit átveszünk:** a message-passing kernel filozófiát, a determinisztikus real-time válaszidőket, a priority inheritance-t.

**Amit NEM:** a POSIX kompatibilitást (mi az aktor modellt tisztán visszük).

### seL4 (2009, UNSW, NICTA)
**Az első formálisan verifikált OS kernel.** Capability-based, microkernel, ~10 000 sor C, Coq + Isabelle bizonyítás.

**Amit átveszünk:** a capability modellt, a formális verifikáció célkitűzést, a minimalizmust.

**Amit NEM:** az L4 IPC absztrakciót (mi aktor modellt használunk, nem process + IPC-t).

### MINIX 3 (Tanenbaum, 2005)
**Multi-server mikrokernel.** Ha egy szerver (pl. file server) crashel, újraindul anélkül, hogy a többi érintett lenne.

**Amit átveszünk:** a reinkarnációs szerver (supervisor) ötletet, a driver isolation-t.

### Singularity (Microsoft Research, 2003–2008)
**C#-ra alapuló OS kutatási projekt.** Minden komponens izolált „Software Isolated Process" (SIP). Az üzenet-csatornákon mennek át, és a fordító ellenőrzi az isolation-t build-time.

**Amit átveszünk:** A SIP izolációs modellt, a C#-alapú OS tervezési filozófiát, a fordító-oldali verifikációt. **Ez a legközelebbi szellemi rokonunk**, csak Microsoft kutatási projektként nem került publikus használatba.

### Orleans (Microsoft, 2010)
**Virtual actors .NET-ben**, cloud-scale, Halo 4/5 backend.

**Amit átveszünk:** a virtual actor koncepciót (egy aktor referencia **logikai**, a runtime dönt, hol fut fizikailag), a lokáció transzparenciát, az elosztott rendszer API-t.

### Pony (2014)
**Aktor-alapú programozási nyelv reference capability típusrendszerrel.** Garantáltan data-race mentes a fordító szintjén.

**Amit átveszünk:** a „garantált izoláció a fordítás idején" ötletet. A C# ugyanezt a `readonly struct` és immutable típusokkal tudja elérni.

### Akka.NET (2013)
**Scala Akka port C#-re.** Produktív, fejlett, de **szoftveres**.

**Amit átveszünk:** az API-t részben, a programozási modellt, a toolkit-et.

## Amit a Neuron OS nem **utánoz** — tudatos architektúra-döntések

Ezek **nem korlátok**, hanem **tudatos tervezési döntések** — olyan 1970-es évek öröklött kompromisszumok elutasítása, amelyek a mai követelményeknek már nem felelnek meg. Amit nem csinálunk **úgy**, mint a Linux, azt **jobb módon** csináljuk.

### 1. Nem POSIX kompatibilitást — helyette modern aktor API-t

Nincs `fork()`, `exec()`, `open()`, `close()`, `read()`, `write()` a hagyományos értelemben. **Miért nem baj:** ezek az API-k a 1970-es évek egy-magos, kevés-memóriás, karakteres terminálon dolgozó Unix rendszereire lettek szabva. A `fork()` például **egy másik processzel azonos címteret másol** — ez a shared memory modell **legkevésbé biztonságos** tünete, és a modern multi-core rendszerekben egyre súlyosabb teljesítmény- és biztonsági probléma.

Helyettük a Neuron OS **modern alternatívákat** ad: `Spawn<Actor>()` (nem `fork`), `Send(actorRef, msg)` (nem `write()` fd-re), `Receive()` (nem `read()` blokkolva), `ActorRef` (nem `fd`). Ha egy régi POSIX alkalmazás fordítására van szükség, **egy szoftveres kompatibilitási réteg** építhető a Neuron OS-re (mint a Windows WSL2 fordítva) — de **a natív programozási modell egyértelműen modernebb és biztonságosabb**.

### 2. Nem monolit kernel — helyette aktor-hierarchia

Nincs kernel tér, nincs user tér, nincs system call overhead. **Miért jobb:** a kernel/user mode switch minden rendszerhívásnál ~1000 ciklus veszteséget okoz, és a Spectre/Meltdown/L1TF mind a privilégium-határokat próbálják átlépni. A Neuron OS-en **nincsenek ilyen határok** — minden komponens aktor, a hardveres shared-nothing isolation garantálja azt, amit más OS-ek a kernel/user mode switch-csel biztosítanak. Egy aktor nem tud egy másik aktor memóriájába írni **nem azért, mert a kernel megállítja**, hanem mert **fizikailag nem létezik olyan útvonal**.

### 3. Nem globális fájlrendszer sémát — helyette strukturált storage service

A fájl **nem egy bájt-stream** a Neuron OS-ben. **Miért jobb:** a Unix „minden fájl" absztrakció elfed sok modern adatstruktúrát (idősoros adat, gráf, objektum-séma, eventual-consistent store). Ezek ma **mind a fájlrendszer fölött** vannak rárakott rétegként (SQLite, RocksDB, LevelDB), ami komplexitást és sebezhetőséget hoz.

A Neuron OS-en az **adat aktor-üzenetek** formájában érkezik és megy, és a „storage service" egy **strukturált aktor-rendszer**, ami közvetlenül ismeri az adatstruktúrákat. Egy POSIX-kompatibilitási réteg a szélén megadhatja a hagyományos fájlrendszer API-t, ha szükséges.

### 4. Nem shared memory + mutex — helyette aktor message passing

Nincs `pthread_mutex_lock`, `pthread_cond_wait`, `shm_open`, `mmap(MAP_SHARED)`. **Miért jobb:** ezek a primitívek **architekturálisan lehetővé teszik** a race condition-öket, dead lock-okat, data corruption-t. Évtizedek óta a **legnehezebben javítható** bugok osztálya a programozásban.

Az aktor message passing **architekturálisan kizárja** ezeket. Nem nehezebbé teszi, **fizikailag lehetetlenné**. A performance, amit a shared memory ígért, a Neuron OS + CLI-CPU kombinációban **zero-copy mailbox** formájában megtalálható, de **anélkül** a race condition veszélye nélkül.

### 5. Nem POSIX user/group permissions — helyette capability-based security

Nincs `chmod`, `chown`, `setuid`, `setgid`, `/etc/passwd`. **Miért jobb:** a Unix permission modell 1970-ben született, amikor egy gépen 10-20 felhasználó volt, és a bizalom alap volt. Ma a konténerek, a multi-tenant cloud, az AI agent-ek világában ez **abszurd**. Egyetlen root felhasználó **minden** jogosultságot birtokol, ami egyetlen bug-gal **teljes kompromisszum**.

A Neuron OS **capability-based security** modellje **árnyaltabb, finomabb, és delegálható**. Egy aktornak **csak akkor** van jogosultsága egy művelethez, ha valaki **átadta** neki a megfelelő capability-t. Nincs globális „root" — mindenki csak azt teheti, amihez kifejezetten kapott felhatalmazást. Ez a CHERI és seL4 modellje, amit évtizedes kutatás bizonyított.

### 6. Nem manuális memóriakezelés unsafe-by-default nyelveken — helyette type-safe, garbage-collected aktorok

Nincs `malloc`/`free`, nincs `char *`, nincs `void *`. **Miért jobb:** a C/C++ memory management a biztonsági bugok **fő forrása**. A CVE-k több mint 70%-a memory safety hibából ered. A Rust megoldja ezt szoftveres szinten, de a meglévő 30+ millió sor C/C++ kódot **soha nem fogjuk teljesen újraírni**.

A Neuron OS-en **alapértelmezésben** type-safe, hardveres GC-vel, és a CIL ECMA-335 verifikálható kód szemantika építve. Egy fejlesztő **nem tud** memory corruption bugot írni a Neuron OS-re, mert sem a nyelv (C#), sem a runtime (CLI-CPU), sem az ISA (CIL-T0/Rich) **nem engedi**.

### 7. Nem kernel panic + reboot modellt — helyette let it crash + supervision

Ha a Linux-ban egy driver hibázik, **kernel panic**, és a rendszer újraindul. A modern Linux sok mindent csinál, hogy ezt elkerülje (recovery subsystems, kprobes, live patching), de a **alap modell** a „kernel bug → rendszer megáll".

A Neuron OS-en egy driver **egy aktor**, és ha hibázik, a **supervisor újraindítja**. A többi rendszer **érintetlen marad**. Ez **40 év alatt** bizonyított megközelítés az Erlang-ban (Ericsson AXD301 9-nines availability), és a Neuron OS természetesen ezt használja.

## Távlati lehetőségek — amit a Neuron OS **természetesen** kinyit

Ez a szekció azokat a területeket írja le, amelyek **nem az első generáció céljai**, de ahol a Neuron OS architektúrája **eredendően** alkalmas, és **hosszú távon** (F7 után, 2035+ időszak) valósággá válhat — sőt, bizonyos területeken **drámaian jobb** lehet, mint a mostani Linux/Windows/macOS megoldások. Ezek nem „majd valamikor" mellékes gondolatok, hanem **a projekt jövőbeli lehetőség-horizontja**.

### 1. Interaktív asztali UI — natívan aktor-alapú

A Neuron OS-en **egy asztali UI természetesen illeszkedik**, mert minden UI elem alapvetően aktor-szerű:

| UI komponens | Hagyományos OS-en | Neuron OS-en |
|-------------|-------------------|--------------|
| Widget | Shared state, callback chain | **Aktor** (saját state, `Receive` metódussal) |
| Ablak | Kernel+compositor shared resource | **Aktor-hierarchia** (window + child widgets) |
| Input handler | Globális event queue, polling | **Mailbox** minden widget-en |
| Renderer | GPU driver + compositing | **Render aktor**, ami a window aktortól kapja az update üzeneteket |
| Animation | Timer + dirty flag | **Event-driven message** time-based trigger-rel |

**Ami fundamentálisan jobb:**
- **Ha egy widget crashel, a többi működik** — a Linux-on egy hibás GTK widget gyakran kilőheti az egész ablakot, az egész X session-t, sőt néha az egész desktopot
- **Hot reload natívan** — egy futó alkalmazás UI-ja **élő módon módosítható** kód újrafordítás nélkül, Erlang-stílusban
- **Multi-touch / multi-input** — minden input device saját aktor, nincs globális input queue bottleneck
- **GPU-mentes vector UI** — ha a rendszer elég sok Nano core-ral rendelkezik, a vektor grafika **aktor hálózatban** is számolható, nem szükséges GPU
- **Determinisztikus replay** — egy UI bug reprodukálható az input üzenet-sorozat visszajátszásával

**Modern keretrendszerek, amik már most aktor-szerűek:**
- **React** / **Vue** / **Svelte** — „component" ≈ aktor, re-render ≈ üzenet-feldolgozás
- **Flutter** — widget tree ≈ aktor-hierarchia, `setState()` ≈ `Send`
- **SwiftUI** — view as value, state-based rendering
- **Elm architecture** — explicit update + view, egyértelmű aktor-minta
- **Jetpack Compose** (Android) — declarative, reactive

**Egy Neuron OS Desktop** nem a X11/Wayland modellt másolná, hanem **natívan aktor-alapú**: minden widget egy `UiWidgetActor`, minden ablak egy `WindowActor`, a compositing egy `RenderSupervisorActor`. Egy **React/Flutter-szerű API** C#-ban, közvetlenül a Neuron OS runtime-jára építve. Ez **sokkal egyszerűbb** mint a Linux stack, és **sokkal robusztusabb**.

**Mikor:** 2035+ táv, F7 után egy külön „Neuron OS Desktop" projektben. Nem az első generáció, de **nem is elérhetetlen** — csak **nincs még idő** hozzá. Amikor eljön a pillanat, a rendszer **készen áll rá**.

### 2. Játékplatform — natív ECS + deterministic multiplayer

A modern játékok **természeténél fogva** aktor-szerűek. Az **Entity Component System (ECS)** paradigma (amit az Unity DOTS, az Unreal Engine Mass, a Bevy mind követ) pontosan az aktor modellt közelíti meg.

| Játék komponens | Hagyományos megvalósítás | Neuron OS-en |
|----------------|--------------------------|--------------|
| Játékos entitás | Shared memory object, mutex-szel védve | **Aktor** (saját state, üzenetek) |
| NPC / AI agent | Threading pool, szinkronizáció | **Aktor** (egy per NPC), natív párhuzam |
| Physics world | Egyetlen thread, vagy bonyolult partitioning | **Aktor-hálózat** (minden fizikai objektum egy aktor) |
| Render | Command buffer, GPU sync | **Render aktor**, rajzoló üzenetekkel |
| Network sync | Custom protocol, delta encoding | **Message replay** + determinizmus natívan |
| Sound | Mixer szál, callback-ek | **Audio aktor**, stream üzenetekkel |
| Input | Polling vs event | **Mailbox-alapú** |

**Ami fundamentálisan jobb:**
- **Nincs data race** az NPC-k között — a hagyományos játékok **tele vannak** szinkronizációs bugokkal, amelyek a Neuron OS-en **fizikailag lehetetlenek**
- **Massively parallel AI** — egy MMO-ban 10 000 NPC? Minden NPC egy Nano core, valós párhuzamossággal. **Olyan skála**, amit a mai játékmotorok nem tudnak
- **Deterministic multiplayer sync** — mivel minden üzenet szigorú sorrendben érkezik, és minden aktor determinisztikus, **lockstep** multiplayer szinkronizáció **natívan** megvalósítható (ami a hagyományos rendszereken nagyon nehéz)
- **Hot modding** — új NPC viselkedések, új szabályok, új items **futás közben** tölthetők be Erlang-stílusú hot code loading-gal. A Minecraft modding ökoszisztémája ezen a modellen **exponenciálisan egyszerűbb** lenne
- **Formally verifiable game logic** — egy kompetitív játék (esport) logikája **matematikailag bizonyíthatóan fair**, ha a Neuron OS-en fut — nincsenek anti-cheat heurisztikák, a rendszer **architekturálisan** nem engedi a cheating-et
- **Entity isolation** — ha egy NPC AI script hibázik, **csak az a NPC** hal meg, a supervisor újraindítja. A játék megy tovább

**Mai példák, amik már most aktor-irányba mozdulnak:**
- **Minecraft** — a chunk-ok **majdnem** aktor-szerűek, de szoftveres emuláción
- **EVE Online** — egész szerver architektúrája dinamikusan particionált, kvázi aktor-clusterek
- **Path of Exile 2** — az új motor explicit „minden egy aktor" filozófián dolgozik
- **No Man's Sky** — a procedural generation entity-enként párhuzamosan

**Unity DOTS** és **Unreal Mass** szoftveresen próbálják ugyanazt elérni a hagyományos CPU-n, amit a Neuron OS **hardveresen** adna ingyen.

**Mikor:** 2030+ időszak, ha egy játékstúdió vagy egy indie csapat **partnerként** kezdi használni. Egy **realtime engine** fejlesztése több év, de **architekturálisan** a Neuron OS az **ideális** alapja egy következő generációs játékmotornak.

### 3. AI új dimenzióba — AI-native operációs rendszer

**Itt van a projekt legnagyobb potenciálja.** Az AI korszakban egy olyan operációs rendszer, amely **architekturálisan** illeszkedik az AI workload-okhoz, **teljesen új kategóriát** teremthet — olyat, amit sem a GPU+CUDA, sem a CPU+szoftver, sem a jelenlegi neuromorphic chipek nem tudnak.

#### Miért más ez, mint a jelenlegi AI platform

A mai AI hardver és szoftver **stack** rétegek halmaza:
- Linux kernel
- CUDA / ROCm driver
- PyTorch / TensorFlow / JAX
- Model definíció
- Training / inference runtime
- Agent framework (LangChain, AutoGen, Claude Agent)

**Minden rétegben van overhead, van sebezhetőség, van komplexitás**. A Neuron OS ezt **drasztikusan** egyszerűsíti, mert **maga a rendszer aktor-orientált, ami természetesen illeszkedik az AI-hoz**.

#### Hét AI-domain, ahol a Neuron OS fundamentálisan jobb

##### (1) Hardveres neurális háló futtatás — nem szimuláció

A jelenlegi neurális hálók **GPU-n szimulált** mátrix-műveletek. Minden neuron egy sor egy mátrixban, minden súly egy érték. A CLI-CPU Cognitive Fabric-on **minden neuron tényleg lehet egy core**, saját programmal, saját állapottal, **valós párhuzamossággal**. Ez **nem** ugyanaz, mint egy GPU.

A különbség: a GPU SIMD (Single Instruction Multiple Data) — minden „neuron" **ugyanazt** csinálja, csak más adatokra. A CLI-CPU cognitive fabric MIMD (Multiple Instruction Multiple Data) — **minden neuron más-más** algoritmust futtathat. **Ez a programozhatóság** az, amit sem a GPU, sem a Loihi, sem a TrueNorth nem tud adni.

Eredmény: **új neurális architektúrák** lehetségesek, amelyek nem a mátrix-műveletek gerincére épülnek, hanem **szabad formájú üzenet-passing gráfokra**. Ez a biológiai agyhoz **sokkal közelebb** áll.

##### (2) AI-native scheduling — az OS döntései AI-vezéreltek

Egy hagyományos OS-ben a scheduler egy statikus algoritmus (CFS Linux-on, O(1) régebben). Egy **AI-native OS-en** a scheduler maga egy aktor, amely **tanul** a rendszer viselkedéséből, és **ML-alapon** dönt, hogy melyik aktort melyik core-ra, mikor.

A memory manager, a network router, a GC, a supervisor stratégiák — **mind** lehetnek tanuló ML aktorok, amelyek a rendszer használata során **optimalizálnak**. Ez olyan, mintha az OS **maga is intelligens lenne**, nem csak kiszolgáló.

##### (3) Agent-hierarchia hardveresen

A mai **LLM agent** rendszerek (AutoGen, Claude Agent, OpenAI Swarm) **szoftveres layer**-ek a hagyományos OS fölött, Python-ban. Egy Neuron OS-en **minden agent egy saját hardveres aktor**, Rich core-on futó teljes LLM-mel, vagy Nano core-on futó kis specialista modellel.

Az agent hierarchia **natívan** supervisor tree: supervisor agent felügyeli a worker agent-eket, hiba esetén újraindítja, vagy escalate. Ez a **production-grade** agent-alapú AI, amit a mai szoftveres megoldások csak **ígérnek**.

##### (4) Formálisan verifikált AI — matematikailag bizonyítható helyesség

**Ez a legnagyobb dolog.** A mai AI rendszerek (LLM-ek, neurális hálók) **bizonyíthatatlanok** — nem tudjuk matematikailag igazolni, hogy egy bizonyos bemenetre a modell garantáltan biztonságos választ ad. Ez akadályozza az AI bevezetését a safety-critical területeken (medical diagnosis, autonomous vehicle, critical infrastructure).

A **Neuron OS-en** viszont:
- Az **operációs rendszer** formálisan verifikálható (seL4 méretosztályban)
- A **CLI-CPU ISA** formálisan verifikálható
- Az **aktor-rendszer topológia** determinisztikus és leírható
- A **capability-biztonság** hardveresen kikényszerített

Ez azt jelenti, hogy **egy AI agent mozgástere matematikailag bizonyítható**, még ha maga az AI modell stokasztikus is. Tudjuk, hogy az agent **soha nem** fogja elérni X erőforrást, **soha nem** fogja kiküldeni Y adatot, **soha nem** fogja végrehajtani Z műveletet — mert a capability modell **ezt nem engedi**. A nem-determinisztikus LLM **determinisztikus határok között** fut.

Ez **forradalmian fontos** a **regulated AI** jövőjében. Az EU AI Act és hasonló szabályozások pontosan **ezt** fogják követelni — és a Neuron OS az **egyetlen platform**, ami ezt **architekturálisan** meg tudja adni.

##### (5) Prompt injection architekturális védelme

A mai LLM agent-ek legnagyobb biztonsági problémája a **prompt injection**: egy rosszindulatú bemenet manipulálja az agent-et, hogy olyan műveletet hajtson végre, amit nem kellene. A védekezés ma **szoftveres heurisztikák** (guardrails, output filters, jailbreak detectorok) — mind **megkerülhetőek**.

A Neuron OS **architekturális** védelmet ad:
- Egy agent csak azokat a műveleteket tudja végrehajtani, amelyekre **capability-je** van
- Az agent **nem tudja módosítani** a saját capability-jét (hardveres isolation)
- Az agent **nem tudja** elérni más aktorokat, csak azokat, akiknek referenciáját birtokolja
- Egy supervisor aktor **megfigyelheti** az agent viselkedését és **leállíthatja**, ha anomáliát észlel

Ez azt jelenti, hogy **akárhogyan is rávesznek egy LLM-et prompt injection-nel**, a Neuron OS **fizikailag nem engedi**, hogy a kívánt rosszindulatú műveletet végrehajtsa. **Ez egy teljesen új biztonsági paradigma az AI agent-eknek.**

##### (6) Federated / distributed learning natívan

A federated learning (modell-tréning több független adatbázison, anélkül hogy az adatok összekerülnének) ma komplex infrastruktúrát igényel (pl. NVIDIA FLARE, TensorFlow Federated). A Neuron OS-en ez **natív**: minden node egy aktor-halmaz, üzenetek (gradiensek, súlyok) mennek a node-ok között, és a **location transparency** miatt a fejlesztő **ugyanazt a kódot** írja lokálisan és distributed-en.

##### (7) Swarm intelligence és multi-agent szimuláció

A Cognitive Fabric **pontosan** azt kínálja, amit a swarm intelligence és a multi-agent AI rendszerek igényelnek: **sok kis, programozható, kommunikáló egység**. Robotika rajok, agent-alapú gazdaságmodellek, járvány-szimulációk, közlekedési optimalizációs rendszerek — mind **natívan** futnak.

#### A konkrét lehetőségek

| AI alkalmazás | Mit ad a Neuron OS |
|--------------|---------------------|
| **Autonóm jármű AI** | Formally verifiable perception + planning, deterministic realtime, AI safety watchdog |
| **Medical diagnostic AI** | Class C tanúsítható, audithatóság, privacy-preserving |
| **Realtime robotika** | Determinisztikus latency, multi-agent sensor fusion |
| **LLM agent cluster** | Supervisor hierarchy, capability security, prompt injection védelem |
| **Hardveres neurális háló (SNN)** | Minden neuron egy core, programozható neuron-modell |
| **Federated learning edge** | Natív location transparency, data nem hagyja el a csomópontot |
| **AI safety monitor** | Egy kis Rich core figyeli egy nagy AI modell kimenetét, anomália esetén leállít |
| **Multi-agent szimuláció** | Ezrek párhuzamos ágenseket, natív üzenet-passing |
| **Privacy-preserving ML inference** | Nincs shared memory, nincs side-channel, shared-nothing isolation |

#### Miért ez új dimenzió

Mert eddig az AI platform a **számítási teljesítmény** versenyében volt. „Több FLOPS, több paraméter, nagyobb modell." A Cognitive Fabric + Neuron OS **más tengelyen** verseng: **programozhatóság, biztonság, skálázódás, tanúsíthatóság**.

Ez **egy új kategóriát teremt**:
- Nem „AI gyorsító" (mint az NVIDIA H100, Google TPU)
- Nem „neuromorphic chip" (mint Loihi, TrueNorth)
- Nem „multi-core CPU" (mint AMD EPYC, Apple M3)
- Nem „FPGA AI" (mint Xilinx Versal)

Hanem **„programozható cognitive substrate"** — az első olyan platform, ahol az AI **nem egy futó réteg a hagyományos OS-en, hanem a rendszer integrált része**. Ahol az operációs rendszer maga **AI-alapú**, ahol minden agent **hardveresen izolált**, és ahol a **formális verifikáció** nem csak szlogen, hanem matematikai valóság.

**Ha a projekt ezt eléri, akkor a Neuron OS nem csak a Linux utódja lesz, hanem az AI kor első natív operációs rendszere.** Ez a CLI-CPU projekt **legtávolabbi, legambiciózusabb** horizontja.

### 4. Ökoszisztéma és platform — hosszú táv

A Linux 30 év alatt hatalmas szoftver-ökoszisztémát épített fel (`apt`, `dnf`, `pacman`, `npm`, `PyPI`, `crates.io`, stb.). A Neuron OS **nem fogja ezt egy napról a másikra lemásolni**, mert nem akarja — a **natív .NET ökoszisztéma** (NuGet) + a Neuron OS-specifikus csomagok **évek alatt** épülnek fel, egy **más** paradigmára.

**Ami viszont szükségszerű:** minden meglévő szoftver, ami `dotnet publish`-sel lefordítható és egy NuGet csomag, **hosszú távon** natívan futhat a Neuron OS-en. A .NET ökoszisztéma már most is **~400 000+ csomag** a NuGet-en, aminek egy jelentős része **nem igényel P/Invoke-ot** és **nem igényel reflection-t**, tehát **natívan** fut a CLI-CPU + Neuron OS kombináción.

**Ez egy hatalmas ugródeszka**, amit a többi új OS-projekt (Redox, Serenity, Haiku) nem kapott meg. A .NET ökoszisztéma **önmagában** egy termék-sor, amire építhetünk.

## Amit ténylegesen nem célozunk (szűk, tudatos listára csökkentve)

Az egyetlen terület, ahol a Neuron OS **explicit nem akar jelen lenni**: a **legacy POSIX binárisok natív futtatása**. Egy meglévő C/C++ Linux program **nem fog natívan** futni Neuron OS-en. Ha valaki kétségbeesetten akarja, egy **kompatibilitási réteg** (Linux Subsystem for Neuron OS, LSNOS) épülhet a tetejére — de ez **nem az alapvető modell**, és **nem ajánljuk** új kód fejlesztésére.

**Minden más** terület hosszú távon **potenciálisan nyitott** — az idő, a csapat, és a közösség dönti el, hogy el is jutunk-e oda.

## Nyitott kérdések (F1-F4 közben válaszolandók)

Ezek olyan kérdések, amelyeket **nem tudunk most eldönteni**, mert valós tapasztalat kell hozzájuk, és a szimulátor + FPGA fázisokban kell rájuk válaszolni:

1. **Pontosan hány aktor fér el egy Rich core-on?** Egy core feletti nagyságrend? Száz? Ezer? A per-aktor kontextus-méret dönti el.
2. **A mailbox mélység kell legyen dinamikus?** F3-ban fix 8, de F5-től már kérdéses, hogy nem érdemesebb-e futásidőben állítható mélységet csinálni.
3. **Preemptív vagy kooperatív scheduling?** Kooperatív egyszerűbb, de egy rosszul viselkedő aktor megeheti a core-t. Esetleg watchdog-alapú félpreemptív?
4. **Garbage collection algoritmus?** Bump + mark-sweep az egyszerű, de real-time rendszerhez inkrementális kell. Ez F5-F6 döntés.
5. **Network protokoll inter-chip-re?** Saját, vagy meglévő (pl. GRPC-szerű)? Saját egyszerűbb, de nem portabilis.
6. **Capability signature algoritmus?** HMAC-SHA256? Poly1305? Egyszerűbb CRC? Biztonsági vs teljesítmény kompromisszum.
7. **Hogyan oldjuk meg a real-time garanciákat?** Szükség van-e hard real-time aktorra (ASIL-D célra), vagy soft real-time elég?
8. **Akka.NET API mennyire legyen kompatibilis?** 1:1 portból vagy inspirált API?

Ezek a kérdések az **F4 szimulátor + F5 FPGA** tapasztalatok alapján fognak eldőlni.

## Következő lépések

A Neuron OS fejlesztése **nem önálló fázis** a roadmap-ben, hanem **az F1-F7 fázisok mentén organikusan** épül ki. Az első konkrét lépések:

1. **F1-ben**: a C# referencia szimulátornak legyen egy minimális `NeuronOS.Core` könyvtár-projekt, amely az aktor absztrakciókat adja (`Actor<T>`, `Spawn`, `Send`, `Receive`). **Ez nem OS még**, csak egy fejlesztői kényelem, de már most aktor-orientált kódot lehet írni.

2. **F3 Tiny Tapeout bring-up programnál**: az echo neuron demó legyen egy **valós Neuron OS aktor**, nem csak egy C# program. Az aktor interfész minimum is, de **explicit** aktor-ként van megírva.

3. **F4 multi-core FPGA demónál**: az első **valódi** Neuron OS alfa — 4 aktor, scheduler, router, minimal supervisor. Ez a *project első mérföldköve*, ahol „OS"-ről beszélhetünk.

4. **Dokumentum frissítések**: ahogy a valós munka halad, ez a `neuron-os.md` dokumentum **frissül**, és a nyitott kérdések **eldőlnek**.

## Záró gondolat — egy új paradigma születése

A Neuron OS **nem egy újabb operációs rendszer** a már létező Linux-, Windows-, macOS-félék mellett. **Egy új paradigma**, amely a **Linux által örökölt 1970-es évek Unix alapjait váltja fel**, pontosan úgy, ahogy az x86 leváltotta a mainframe-et, a mobile leváltotta a desktopot, és a cloud leváltotta az on-prem szerverközpontot.

### Miért **lesz** ez a leváltás elkerülhetetlen

1. **Biztonsági nyomás** — az AI-vezérelt kód-generálás, a supply chain támadások, és a Spectre-utódok miatt a Linux architekturálisan nem tud lépést tartani. A Neuron OS-en **ezek a támadási osztályok architekturálisan kizártak**.

2. **Skálázási nyomás** — a jövő hardvere **nem 16-64 core**, hanem **10 000+ core**. A shared memory modell ott megbukik. Az aktor modell **lineárisan skálázódik**.

3. **Distributed-first világ** — a cloud, az edge, az IoT, az AI agent-ek mind **elosztott** rendszerek alapértelmezésben. A Linux a „lokális gép + networking rárakva" modellt örökölte. A Neuron OS **natívan elosztott**.

4. **Fault tolerance elvárás** — a 9-nines elérhetőség, a „never reboot" elvárás, a kritikus alkalmazások mind **supervision-t** kérnek, amit a Linux csak nehezen és rárakott rétegekkel tud (systemd + K8s + service mesh). A Neuron OS-en ez **natív**.

5. **Formális verifikáció szükséglete** — a safety-critical rendszerek (medical, automotive, aviation, kritikus infrastruktúra) egyre szigorúbb tanúsítást követelnek, amit egy **40 M sor C kernel** soha nem fog elérni. A Neuron OS **formálisan verifikálható**.

6. **AI paradigma-váltás** — az AI korszakban az operációs rendszer **nem egy passzív kiszolgáló**, hanem egy **aktív részvevő**. Az agent-alapú AI, a federated learning, a formálisan verifikált AI, a prompt injection védelem — mind **architekturális** igények, amiket a Linux rárakott rétegekkel nem tud adni, de a Neuron OS **natívan**.

### Mi lehet a Neuron OS távlati hatása

Ha minden tervezett irányban sikerül:

- **Kritikus infrastruktúra** (automotive, medical, aviation, energetika) — Neuron OS a tanúsított alap, 2030-tól
- **Hyperscale cognitive computing** — Neuron OS + CLI-CPU mint új kategóriás cloud szerver, 2035-től
- **AI agent-cluster platform** — biztonságos, auditálható, capability-based agent rendszerek, **2030-tól**
- **Következő generációs játékmotor** — aktor-native ECS, deterministic multiplayer, hardveres NPC tömegek, **2035-től**
- **Következő generációs asztali UI** — reactive, hot-reload, crash-resistant widgetek, **2040-től**
- **Hardveres neurális háló platform** — MIMD neuron-szimuláció, új neurális architektúrák, **2030-tól**
- **AI operációs rendszer** — ML-vezérelt scheduler, memory manager, self-optimizing kernel, **2035-től**
- **Kvantum-után kriptográfia hardveresen** — post-quantum algoritmusok izolált környezetben, **2030-tól**

### A „The Mess We're In" 10 év múlva

**Joe Armstrong, az Erlang atyja, 2014-ben előadást tartott „The Mess We're In" címmel**, ahol elmondta, hogy a jelenlegi szoftver-rendszerek **alapjaiban rossz** modellekre épülnek, és egy új paradigma kell, amely az Erlang aktor-modelljét veszi természetes alapnak. **Azt mondta, szükség van egy olyan hardverre, ahol minden core egy aktor.** Akkor elérhetetlennek tűnt, mert **nem volt olyan hardver**, ami ezt natívan támogatná.

**Ma van.** A CLI-CPU cognitive fabric architektúrája az első olyan hardver, amely az Armstrong-i víziót **fizikailag lehetővé teszi**. A Neuron OS pedig az operációs rendszer, amelyet erre a hardverre építünk.

### A valódi tét

Ha a projekt eljut F6-F7-ig, és a Neuron OS működőképes, akkor **a CLI-CPU + Neuron OS együtt** egy új számítási paradigma első fizikai megvalósítása lesz, amit sem az Erlang, sem a QNX, sem a seL4, sem a Singularity nem tudott a saját korukban megvalósítani:

> **Az aktor modell natívan hardveren**,
> **gyorsabban mint a klasszikus shared-memory OS**,
> **sokkal biztonságosabban**,
> **formálisan verifikálhatóan**,
> **AI-korszakra szabva**,
> **és a Linux méltó utódjaként — nem a mellékterméke.**

Ez egy olyan jövő, amely ma még vízió, de a **jelenlegi hardveres alapokra** (Tiny Tapeout, eFabless, SkyWater, IHP, OpenLane2) **ténylegesen megvalósítható**.

**A CLI-CPU csak egy chip. A Neuron OS egy új korszak.**

Ez a CLI-CPU projekt legtávolabbi, **legértékesebb** horizontja, és **ez a valódi tét**: nem egy kis bytecode CPU megépítése, hanem **egy új számítási paradigma hardveres és szoftveres alapjainak egyszerre lefektetése**, amelyre 10-20 év alatt **egy teljes ökoszisztéma építhető** — beágyazott rendszerektől az AI agent-cluster-ekig, a játékmotorokon át az asztali UI-ig, a kritikus infrastruktúrán át a hardveres neurális hálókig.

**Amikor a jövő visszanéz erre a pillanatra**, a CLI-CPU projekt lehet az a kis, hobbi-méretű indítás, amiből a Linux-utáni korszak operációs rendszere kinőtt. Ahogyan a Linux 1991-es Usenet poszt egy finn egyetemistától egy 40 éves ipart alapozott meg, **a CLI-CPU 2026-os F0 spec dokumentumai** lehetnek a következő 40 év alapjai.

**Ha ez a vízió akár csak 10%-ban valóra válik, a projekt sikeres volt.**

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
