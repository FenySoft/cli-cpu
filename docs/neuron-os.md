# Neuron OS — a CLI-CPU aktor-alapú operációs rendszere

> **Vízió dokumentum.** Ez az OS hosszú távú terve, amely F4 multi-core szimulátorral kezd kibontakozni, F5-F6 hardverrel éri el az első valós használhatóságot, és F7-ben lép ki kiforrott fejlesztői platform szinten.
>
> **A tartalom iránytű, nem végleges spec.** A részleteket menet közben, az F4–F6 tapasztalatok alapján finomítjuk. A cél itt az, hogy a tervezési döntések **irányt kapjanak**, és ne minden F4 iterációnál újra vitatkozzunk az alapelvekről.

## Filozófia — az Erlang vízió hardveres megvalósítása

A **Neuron OS** célja egy olyan operációs rendszer megvalósítása, amelyben **minden entitás aktor**, és a kommunikáció **kizárólag üzenetküldéssel** történik. Ez nem új ötlet — az Erlang/OTP 1986 óta csinálja, a QNX mikrokernele az 1980-as évek óta, és a seL4 2009 óta formálisan verifikáltan.

A különbség: ezek a rendszerek **hagyományos, shared-memory CPU-kon** futnak, ahol az aktor modell **szoftveres overhead-ként** jelenik meg. A Neuron OS **az első aktor-alapú OS, amelyik eleve aktor-orientált hardverre épül** (a CLI-CPU cognitive fabric architektúrájára), ahol:

- Minden core **fizikailag elszigetelt** saját SRAM-mal — nincs shared memory trükk
- A core-ok közötti üzenetküldés **hardveres mailbox FIFO-kon** megy, nem szoftveres queue-kon
- A context switch **~5-8 ciklus** (csak a TOS cache és a PC), nem 500-2000
- A supervisor trap **hardveres interrupt vonalon** érkezik egy másik core-nak, nem signal-alapú
- A capability model **hardveresen** kikényszerített, nem szoftveres check

Ebben az architektúrában **az aktor modell legnagyobb hátránya (a performance overhead) eltűnik**, és ami marad, az az aktor modell **minden előnye** a hagyományos OS-ekhez képest: fault tolerance, lineáris skálázódás, natív distributed systems, capability-based security, hot code loading, és egész hibaosztályok automatikus kizárása.

Joe Armstrong (Erlang egyik atyja) 2014-es „The Mess We're In" előadásában pontosan erről álmodott: egy olyan hardver, ahol az aktor modell nem szoftveres réteg, hanem **az architektúra alapja**. A Neuron OS ezt a víziót valósítja meg, konkrétan a .NET CIL ökoszisztémában.

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

Egy fut ó aktor **új aktort hozhat létre** futás közben:

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

### F6 — Hot code loading, writable microcode, distributed
**Kimenet:** ChipIgnite real silicon:
- Hot code loading aktorok szintjén
- Writable microcode SRAM
- Több chip közötti elosztott aktor rendszer (network device)
- Teljes capability registry aláírással

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

## Amit NEM célozunk

Legyünk tiszták, mit **nem** csinálunk — ez ugyanolyan fontos, mint mi mit csinálunk:

### 1. NEM POSIX-kompatibilitás
Nincs `fork()`, `exec()`, `open()`, `close()`, `read()`, `write()` a hagyományos értelemben. Egy POSIX alkalmazás **nem fordítható le** közvetlenül Neuron OS-re. Ha szükséges, egy kompatibilitási réteget lehet írni a tetejére, de az **nem az alapvető modell**.

### 2. NEM teljes Linux funkcionalitás
Nincs X11, Wayland, systemd, GNOME, KDE, dpkg, apt. A Neuron OS **nem desktop OS**. Beágyazott, szerver, kritikus, és specializált AI workload-okra tervezzük.

### 3. NEM interaktív multiuser shell
Nincs bash, zsh, terminál-alapú user session. A „shell" (ha van) maga is egy aktor, és üzenetekkel dolgozik, nem karakter-stream-mel.

### 4. NEM hagyományos fájlrendszer sémát
A fájl nem egy bájt-stream. Az adat **aktor-üzenetek** formájában érkezik és megy. Egy „file" aktor mailbox-jához hasonlít egy stream-hez, de **szemantikailag más**.

### 5. NEM monolitikus kernel
Nincs kernel tér, nincs user tér, nincs system call. Minden komponens aktor, még a „kernel" funkcionalitás is. A hardveres isolation garantálja, amit más OS-ek a kernel/user mode switch-csel biztosítanak.

### 6. NEM mindent felülmúló általános célú OS
A Neuron OS **nem** akar versenyezni a Linuxszal a webszerver, a konténerek, vagy a desktop területén. **Más kategória**: cognitive fabric, aktor-alapú distributed rendszerek, kritikus beágyazott, AI safety. Ezekben **overtly jobb**, ami másra nem optimalizált, ott nem is próbál ott lenni.

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

## Záró gondolat

A Neuron OS **nem** egy új operációs rendszer akar lenni, ami versenyezni próbál a Linuxszal. **Egy új paradigma első valós platformja**, amely az aktor modellt kihúzza a kutatási marginális térből egy **tömegesen használható alapra**, mert a hardver (CLI-CPU) először teszi ezt **performance-effektíven** lehetővé.

Ha a projekt eljut F6-F7-ig, és a Neuron OS működőképes, akkor **a CLI-CPU + Neuron OS együtt** egy új számítási paradigma első fizikai megvalósítása lesz, amit **sem az Erlang, sem a QNX, sem a seL4 nem tudott** a saját korukban: **az aktor modell natívan hardveren, gyorsabban mint a klasszikus shared-memory OS, és sokkal biztonságosabban**. Ez a CLI-CPU projekt legtávolabbi, **legértékesebb** horizonja.
