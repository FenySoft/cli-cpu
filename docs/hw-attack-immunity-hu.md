# CFPU — HW Attack Immunity Reference

> English version: [hw-attack-immunity-en.md](hw-attack-immunity-en.md)

> Version: 1.0

Ez egy **kompakt referenciatáblázat** a CFPU hardveres támadás-immunitásáról: támadás-osztály → kivédő mechanizmus → forrás dokumentum. Teljes threat model, formális verifikáció és tanúsítási útvonalak: [`security-hu.md`](security-hu.md).

> A táblázat **csak HW-szintű mitigáció**. Szoftveres bug, social engineering, fizikai roncsolás (FIB, probing, fault injection) **nem** ennek a dokumentumnak a hatóköre.

## A mitigáció négy pillére

A CFPU támadás-immunitása **négy architekturális döntésre** épül — minden táblázatos mitigáció ezekre vezethető vissza:

| Pillér | Mechanizmus | Mit zár ki |
|--------|-------------|-----------|
| **1. In-order, no OoO, no speculation** | Determinisztikus pipeline, statikus branch hint | Spectre-család, transient execution |
| **2. Shared-nothing fabric** | Per-core SRAM, mailbox NoC, nincs cache coherence | Cache side-channel, cross-core leak |
| **3. HW-managed capability (CST + Quench-RAM SEAL)** | Capability Slot Table QSRAM-ban, SEAL/RELEASE HW FSM | Memory safety, capability forge, DMA bypass |
| **4. Trust by construction (AuthCode + LMS/WOTS+)** | Hash-alapú PQC aláírás kódbetöltéskor, runtime W⊕X | Code injection, supply chain, JIT spray |

## Per-message authenticity — a HMAC nélküli megoldás

> **Fontos**: a CFPU **NEM használ HMAC-et** üzenet-szinten. A header v3.0 (interconnect-hu.md) változat ezt explicit törölte.

A küldő-aktor azonossága helyett:

| Komponens | Mechanizmus | Hamisíthatatlanság forrása |
|-----------|-------------|----------------------------|
| **`src_actor[8]`** a header-ben | A core HW írja közvetlenül az **aktív actor context regiszterből** | Szoftver nem férkőzik a HW kontextus regiszterhez |
| **`src[24]`** (forrás core ID) | A NoC router fizikailag a forrás portjáról jön | Routing-szintű lokalitás |
| **CST index → cím feloldás** | A CST (Capability Slot Table) QSRAM-ban él, **Quench-RAM SEAL alatt** | Szoftver nem írhat QSRAM-ot, csak Seal Core SEAL/RELEASE FSM |
| **Capability `perms`** | NEM utazik a header-ben — küldéskor a HW ellenőrzi a CST-ben | Stateless küldő ellenőrzés, lokálisan |
| **CRC-16** (payload) + **CRC-8** (header) | Integritás, NEM authentikáció | Bit-flip detection a NoC-ban |

**Trust by construction** — a CIL bináris **egyszer** kerül LMS-aláírású verifikációra (AuthCode kódbetöltéskor), és onnan minden capability hardveresen kötött. Nincs szükség per-message HMAC-re, mert:

1. A küldő aktor identitását **a HW írja** (nem hamisítható)
2. A capability tartalma **QSRAM SEAL** alatt él (nem manipulálható)
3. A futó kód **AuthCode-verifikált** és **CodeLock W⊕X** alatt fut (nem injektálható)

## Támadás-immunitási referencia

### Transient execution / spekulációs támadások

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| Spectre v1/v2/v4 | CWE-1037 | Nincs spekuláció | [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) |
| Meltdown | CWE-1037 | Nincs OoO + nincs spekuláció | [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) |
| Foreshadow / L1TF | CWE-1037 | Per-core SRAM scratchpad, nincs L1 cache | [`core-types-hu.md`](core-types-hu.md) |
| MDS (RIDL/Fallout/ZombieLoad) | CWE-1037 | Nincs SMT, nincs internal buffer sharing | [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) |
| Retbleed / BHI | CWE-1037 | Nincs branch predictor (statikus hint) | [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) |
| Inception / SQUIP | CWE-1037 | Nincs SMT, nincs scheduler resource sharing | [`core-types-hu.md`](core-types-hu.md) |

### Cache side-channel

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| Flush+Reload | CWE-208 | Nincs shared cache | [`core-types-hu.md`](core-types-hu.md) |
| Prime+Probe | CWE-208 | Nincs cache eviction policy (scratchpad) | [`core-types-hu.md`](core-types-hu.md) |
| Evict+Reload | CWE-208 | Per-core SRAM, deterministic latency | [`core-types-hu.md`](core-types-hu.md) |
| MESI protocol leak | — | Shared-nothing, nincs koherencia protokoll | [`interconnect-hu.md`](interconnect-hu.md) |
| CacheBleed | CWE-208 | Nincs cache port szerializáció | [`core-types-hu.md`](core-types-hu.md) |
| Cross-core MDS | CWE-1037 | Shared-nothing fabric | [`interconnect-hu.md`](interconnect-hu.md) |

### Memory safety

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| Buffer overflow | CWE-119/120 | HW bounds check minden memória opkódra | [`security-hu.md`](security-hu.md) |
| Use-after-free | CWE-416 | Per-actor heap + capability lifecycle (SEAL/RELEASE) | [`quench-ram-hu.md`](quench-ram-hu.md) |
| Double-free | CWE-415 | Quench-RAM RELEASE atomi, status-bit | [`quench-ram-hu.md`](quench-ram-hu.md) |
| Type confusion | CWE-843 | CIL típus-rendszer, ILC verification AOT | [`security-hu.md`](security-hu.md) |
| Pointer leak | CWE-200 | Capability index (32-bit), nyers cím nem leak-elhet | [`interconnect-hu.md`](interconnect-hu.md) §Capability v3.0 |
| Privilege escalation | CWE-269 | Nincs "kernel mode" — capability nem eszkalálható | [`sealcore-hu.md`](sealcore-hu.md) |
| Stack smashing | CWE-121 | HW stack bounds + frame pointer fizikailag elkülönített | [`security-hu.md`](security-hu.md) |
| Information leak in freed memory | CWE-244, CWE-226 | Quench-RAM RELEASE = atomi wipe | [`quench-ram-hu.md`](quench-ram-hu.md) |
| Uninitialized memory read | CWE-457 | Quench-RAM + ECMA-335 zero-init | [`quench-ram-hu.md`](quench-ram-hu.md) |

### Cross-actor / fabric támadások

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| Inter-process info leak | CWE-200 | Shared-nothing — fizikailag nincs közös memória | [`interconnect-hu.md`](interconnect-hu.md) |
| DMA bypass | CWE-1233 | DDR5 HW Capability Slot QRAM-ban + `flags.DDR5_CAP` HW-only bit | [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) |
| Confused deputy | CWE-441 | `src_actor` HW context register-ből, nem hamisítható | [`interconnect-hu.md`](interconnect-hu.md) |
| Aktor-spoofing | — | A `src_actor[8]` mezőt a core HW írja (nem szoftver) | [`interconnect-hu.md`](interconnect-hu.md) v3.0 |
| Capability forging | — | CST QSRAM-ban, Quench-RAM SEAL alatt — szoftver nem írhat | [`quench-ram-hu.md`](quench-ram-hu.md) v1.4 |
| Capability tag forging | — | Sealed régió, fizikailag hamisíthatatlan | [`quench-ram-hu.md`](quench-ram-hu.md) |
| Replay attack mailbox-on | — | `seq[16]` fragment counter + AuthCode-tól származó kód-integritás | [`interconnect-hu.md`](interconnect-hu.md) |

### Code integrity / supply chain

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| Unsigned code execution | CWE-345 | AuthCode HW verify minden kódbetöltéskor | [`authcode-hu.md`](authcode-hu.md) |
| Tampered binary execution | CWE-345 | LMS+WOTS+ aláírás, SHA-256(bytecode) ↔ cert.PkHash | [`authcode-hu.md`](authcode-hu.md) |
| Stateful signature key reuse | — | Symphact HSM Card single-use NVRAM | [`authcode-hu.md`](authcode-hu.md) |
| Quantum break of signature | — | LMS+WOTS+ hash-alapú PQC (FIPS 205, NIST SP 800-208) | [`authcode-hu.md`](authcode-hu.md) |
| Hot code loader tamper | — | Seal Core firmware mask ROM / eFuse immutable | [`sealcore-hu.md`](sealcore-hu.md) |
| Memory controller write-path bypass | — | Pre-QRAM WE-routing / QRAM SEAL HW-trigger | [`sealcore-hu.md`](sealcore-hu.md) |
| Shellcode injection | CWE-94 | CODE R/O hardveresen, Quench-RAM SEAL | [`quench-ram-hu.md`](quench-ram-hu.md) |
| JIT spraying | — | **Nincs JIT** — natív CIL execution | [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) |
| Self-modifying code | CWE-94 | Quench-RAM SEAL — sealed régió írhatatlan | [`quench-ram-hu.md`](quench-ram-hu.md) |
| Supply chain at HW level | — | Nyílt HDL (CERN-OHL-S), reprodukálható build | [`security-hu.md`](security-hu.md) |
| Supply chain at code level | — | AuthCode trust chain: eFuse → CA → vendor → card → binary | [`authcode-hu.md`](authcode-hu.md) |

### Control flow integrity

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| ROP (Return-Oriented Programming) | CWE-121 | CFI az ISA-ban, return target HW-verified | [`security-hu.md`](security-hu.md) |
| JOP (Jump-Oriented Programming) | — | Branch target verification (csak metódus-belüli ugrás) | [`security-hu.md`](security-hu.md) |
| Format string | CWE-134 | Nincs printf, nincs C-string | [`security-hu.md`](security-hu.md) |
| Stack overflow (unbounded recursion) | CWE-674 | HW stack bounds trap | [`security-hu.md`](security-hu.md) |

### Concurrency

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| Race condition GC-ben | CWE-362 | Per-core privát heap, nincs globális GC | [`core-types-hu.md`](core-types-hu.md) |
| Deadlock (lock contention) | CWE-833 | Nincs shared lock, csak mailbox | [`interconnect-hu.md`](interconnect-hu.md) |
| False sharing covert channel | — | Nincs shared cache | [`interconnect-hu.md`](interconnect-hu.md) |
| TOCTOU (Time-Of-Check Time-Of-Use) | CWE-367 | Capability check atomi a küldő HW-ben | [`interconnect-hu.md`](interconnect-hu.md) |

### Cold boot / physical-adjacent

| Támadás | CWE | CFPU mechanizmus | Forrás |
|---------|-----|-----------------|--------|
| Cold boot key recovery | — | Quench-RAM: sealed kulcs csak wipe-on át szabadul | [`quench-ram-hu.md`](quench-ram-hu.md) |
| Rowhammer (cross-row) | CWE-1247 | Per-core SRAM (nem DRAM), DDR5 capability-bound | [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) |

## Mit NEM véd HW-szinten — őszinte hatókör

A CFPU jó architektúra, de **nem mindenható**. Az alábbiakhoz **kiegészítő mechanizmus** szükséges:

| Támadás | Miért nem véd HW-szinten | Mit kell mellé |
|---------|--------------------------|---------------|
| Power analysis (DPA/SPA) | Constant-time ALU nem default | Constant-time + masking szoftveresen, különösen Seal Core crypto-ban |
| EM analysis | Fizikai szivárgás | Shielding, masked logic — Seal Core-szintű opció |
| Fault injection (clock/volt glitch, laser) | Fault detection FSM nem default | Clock monitor, voltage monitor, redundancia — Seal Core-ban indokolt |
| Physical probing / FIB | Decapped chip látható | Anti-tamper mesh, active shield — Seal Core-ban |
| Software bug a felhasználói kódban | A logika hibáját HW nem javítja | "Secure by design" SDLC, code review |
| Social engineering / kulcs-kompromittáció | HW-en kívül | Folyamati kontrollok, HSM-szabályzat |
| Denial of Service (mailbox spray) | Rate limiting nincs HW-ben | Symphact runtime feladat |
| Üzleti logika hiba (engedély-ellenőrzés) | Ha a C# kód rosszul hívja a capability-t | Tervezési felelősség |

## A négy pillér összefoglalva — ha bárki rákérdez

Ha egy auditor vagy partner egyetlen mondatot kér:

> **A CFPU négy architekturális döntéssel** (in-order pipeline, shared-nothing fabric, HW-managed capability QRAM SEAL alatt, trust-by-construction LMS-aláírású kódbetöltés) **a publikált CWE-listák túlnyomó többségét fizikailag kizárja** — nem szoftveres mitigáció, hanem szerkezeti tulajdonság, ami **nem patch-elhető rossz irányba** és **nem kapcsolható ki performance-cserébe**.

## Pozícionálási üzenet

| Réteg | Hagyományos CPU | CFPU |
|-------|-----------------|------|
| **Mitigáció szintje** | Software patch, firmware microcode | **HW design choice** |
| **Auditálhatóság** | Patch-ek listája, mindegyikre exploit-CVE | TLA+/SVA assertion-ök, formálisan verifikálható |
| **Bypass lehetőség** | "Fast mode" vagy disable flag (pl. SMT-off Spectre miatt) | **Nincs** — szerkezeti |
| **Új támadás-osztálynál** | Új patch, új teljesítményvesztés | **Architektúrális immunitás** |
| **Marketing** | "Secure with patches" | **"Secure by construction"** |

## Kapcsolódó dokumentumok

- [`security-hu.md`](security-hu.md) — átfogó threat model, formális verifikáció, tanúsítási útvonalak, piaci szegmensek
- [`microarch-philosophy-hu.md`](microarch-philosophy-hu.md) — in-order, no OoO, TLP > ILP filozófia
- [`interconnect-hu.md`](interconnect-hu.md) — Header v3.0, CST, capability modell
- [`quench-ram-hu.md`](quench-ram-hu.md) — Quench-RAM SEAL/RELEASE, atomi wipe
- [`authcode-hu.md`](authcode-hu.md) — AuthCode + CodeLock + LMS/WOTS+ trust chain
- [`sealcore-hu.md`](sealcore-hu.md) — Seal Core mint trust anchor
- [`ddr5-architecture-hu.md`](ddr5-architecture-hu.md) — capability slot, HW request assembler

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-05-02 | Kezdeti verzió. Kompakt mitigation-tábla. Négy pillér + per-message authenticity (HMAC nélkül, src_actor HW context register + CST QSRAM SEAL alatt) + LMS/WOTS+ kódaláírás. Hatókör: csak HW-szintű mitigáció; formális verifikáció és tanúsítás: [`security-hu.md`](security-hu.md). |
