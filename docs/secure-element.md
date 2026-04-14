# CLI-CPU Secure Edition — Nyílt Secure Element / TEE / JavaCard utóda

> **Stratégiai pozicionálási dokumentum.** Ez a harmadik piaci pálya a Cognitive Fabric és a Trustworthy Silicon mellé. Egy külön chip-család tervét írja le, amely ugyanarra az alap architektúrára épül, kiegészítve a Secure Element specifikus hardveres komponensekkel, és a JavaCard / TEE / Secure Element piacot célozza.

> English version: not yet available

> Version: 1.0

## Tartalmi áttekintés

1. [Miért egy harmadik pálya](#miert-egy-harmadik-palya)
2. [A Secure Element piac áttekintése](#a-secure-element-piac-attekintese)
3. [Versenytárs mappa — zárt gyártók és nyílt projektek](#versenytars-mappa)
4. [TROPIC01 — az első nyílt secure element részletes elemzése](#tropic01-reszletes)
5. [CLI-CPU Secure Edition — pozicionálás és megkülönböztetés](#pozicionalas)
6. [Architekturális illeszkedés — mi adott, mi hiányzik](#architekturalis-illeszkedes)
7. [Szükséges kiegészítések](#szukseges-kiegeszitesek)
8. [Tanúsítási útvonal](#tanusitasi-utvonal)
9. [Konkrét termékcsalád és használati módok](#termekcsalad)
10. [Új fázis: F6.5 — Secure Edition parallel tape-out](#f6-5-fazis)
11. [Partnerségek és közösség](#partnersegek)
12. [Realista időskála](#idoskala)
13. [Következő lépések](#kovetkezo-lepesek)

## Miért egy harmadik pálya <a name="miert-egy-harmadik-palya"></a>

Az eddigi `docs/architecture.md`, `docs/security.md` és `docs/neuron-os.md` dokumentumok **két piaci pályát** rögzítettek:

1. **Cognitive Fabric** — programozható kognitív szubsztrátum, AI/SNN/actor cluster (hosszú távú vízió)
2. **Trustworthy Silicon** — regulated industries (automotive, aviation, medical, critical infra), rövid-közép távú bevétel

Ez a dokumentum egy **harmadik pályát** vezet be: a **Secure Element / TEE / JavaCard** piacot. Három oka van annak, hogy ez érdemes egy külön stratégiai szintű dokumentumra:

1. **Hatalmas piac.** ~$25-40B globális, gyorsan növekvő, és **tízszer nagyobb**, mint az, amit eddig pozicionáltunk
2. **Tökéletes architekturális illeszkedés.** A CLI-CPU alap-tulajdonságai (memory safety, shared-nothing, formálisan verifikálható ISA, kicsi méret, alacsony fogyasztás, determinizmus) **pontosan** azok, amit a Secure Element piac keres
3. **Megkülönböztető pozicionálás lehetséges.** A jelenlegi nyílt SE projektek (TROPIC01, OpenTitan) **mind** egymagos, hagyományos modelleket használnak. A CLI-CPU multi-core, shared-nothing, aktor-alapú megközelítése **új kategóriát** teremthet: több független Secure Element egy chipen, hardveres isolation-nel

A cél **nem** a Cognitive Fabric vagy a Trustworthy Silicon kicserélése, hanem egy **kiegészítő** piaci terület, ugyanazon az alap hardveren. Az F6 (eFabless ChipIgnite tape-out) mellett egy **F6.5 Secure Edition** variáns készülhet, amely a Secure Element specifikus komponenseket adja hozzá (crypto gyorsítók, TRNG, PUF, tamper detection, side-channel countermeasures) — **minimális újratervezéssel**.

## A Secure Element piac áttekintése <a name="a-secure-element-piac-attekintese"></a>

### Mi egy Secure Element

A **Secure Element (SE)** egy dedikált chip vagy chip-régió, amely érzékeny adatokat (kulcsok, bank adatok, biometrikus adatok, device identity) tárol és feldolgoz, izoláltan a fő számítási környezettől. A SE alapvető tulajdonságai:

- **Tamper resistance** — fizikai támadások (dekapszulálás, probing, laser injection, voltage glitching) elleni védelem
- **Memory isolation** — a SE memóriáját a fő CPU nem tudja közvetlenül olvasni vagy írni
- **Cryptographic co-processor** — AES, SHA, RSA/ECC, post-quantum gyorsítók
- **True Random Number Generator (TRNG)** — entrópia forrás kulcsgeneráláshoz
- **Secure storage** — egyszer programozható memória (OTP/eFuse) a root kulcsoknak
- **Secure boot + attestation** — mérési lánc, amellyel a chip bizonyítja a fő rendszernek, hogy csak engedélyezett firmware fut rajta
- **Tanúsítás** — Common Criteria EAL-5+ vagy EAL-6+ szint (a legszigorúbb fizikai biztonsági vizsgálat után)

### A JavaCard öröksége

A **JavaCard** (Oracle, eredetileg Sun Microsystems, 1996-ban jelent meg) a világ legelterjedtebb smart card szoftver platformja. Becslések szerint **~30 milliárd kártyán** fut a világon: SIM-ek, bankkártyák, nemzeti eID, tömegközlekedési jegyek, eSIM-ek, FIDO authenticator-ek. A JavaCard **pontosan** az, amit a CLI-CPU is próbál — **bytecode natív végrehajtás** izolált biztonsági hardveren — csak:

- **Java 1.5 szintű** (2004), modern fejlesztői élmény hiányzik
- **Zárt ökoszisztéma**, Oracle licensz, magas belépési küszöb
- **Szoftveres interpreter** egy 8-bites vagy 16-bites (ritkán 32-bit) MCU-n
- **Szoftveres application isolation** — a JavaCard runtime különböző applet-eket "isol"-ál egy szoftveres verifier-rel
- **Fix crypto algoritmusok** — nehéz új (pl. post-quantum) algoritmusokat hozzáadni
- **Korlátozott multi-threading** — egy kártyán egyszerre egy applet aktív

**A JavaCard öreg architektúra**, amely 30 éve nem kapott érdemi frissítést. A piacon **alig van verseny** — az Oracle, néhány hardver gyártó (Gemalto/Thales, Idemia, G+D), és a JavaCard 3.2 szabvány az egész. **Ideális leváltási célpont** egy modernebb, nyílt, ténylegesen izolált, aktor-alapú platform számára.

### TEE (Trusted Execution Environment)

A TEE egy izolált számítási környezet, amely a fő OS mellett fut. A jelenlegi kereskedelmi TEE-k mind **sebezhetőségekkel** küzdenek:

| TEE | Gyártó | Ismert sebezhetőségek |
|-----|--------|-----------------------|
| **Intel SGX** | Intel | Foreshadow, L1TF, Plundervolt, SGAxe, ÆPIC Leak, INTEL-SA többszáz |
| **AMD SEV / SEV-SNP** | AMD | SEVered, Cipherleaks, Undeserved, vulnerabilities |
| **ARM TrustZone** | ARM | CacheOut, rengeteg implementációs hiba |
| **Apple Secure Enclave** | Apple | Zárt, nem auditálható; A11-ig SEP keys kiszivárogtak |
| **Google Titan M2** | Google | Zárt, de a Titan M-ben több bug található már |
| **RISC-V Keystone** | akadémiai | Kísérleti státusz |

A probléma közös: a TEE-ket **utólag építik** egy shared-memory, speculative-execution CPU-ra. A CLI-CPU ezzel szemben **eleve shared-nothing**, tehát **nincs utólag hozzáadandó isolation réteg** — ez a rendszer alapja.

### Piacméret

A Secure Element / TEE / SE-alapú termékek éves piaca globálisan:

| Szegmens | Éves piac | Jellemző termék |
|----------|-----------|-----------------|
| **Smart card chips (JavaCard)** | ~$12-15B | SIM, banking card, eID, transit |
| **eSIM / iSIM** | ~$8-12B | beágyazott SIM mobile-ban, IoT-ban |
| **TEE / Secure Enclave** | ~$5-10B | Intel SGX, Apple Secure Enclave, ARM TrustZone |
| **HSM (Hardware Security Module)** | ~$2B | datacenter key management |
| **FIDO2 / Passkey authenticator** | ~$1B | YubiKey, hardver token |
| **TPM (Trusted Platform Module)** | ~$2B | Windows PC, szerver, IoT RoT |
| **Automotive secure element** | ~$1B | V2X, digital key, OTA update |
| **Összesen** | **~$30-42B** | — |

Ez **tízszer nagyobb**, mint a kezdeti Cognitive Fabric pozicionálás, és **gyorsan nő** — a post-quantum migráció, a zero-trust architecture, és a FIDO2 tömeges bevezetése miatt 2030-ig **~$60-80B** lehet.

## Versenytárs mappa <a name="versenytars-mappa"></a>

### Zárt gyártók — a fő piaci célpontok

| Gyártó | Termékek | Éves bevétel (csoport) | Nyíltság |
|--------|----------|--------------------------|----------|
| **Thales** (ex-Gemalto) | SIM, banking, eID, eSIM | ~€15B | ❌ zárt |
| **Idemia** (ex-Oberthur) | banking, biometrikus ID | ~€2.5B | ❌ zárt |
| **Giesecke+Devrient** | SIM, banking, eGovernment | ~€3B | ❌ zárt |
| **Infineon** | SLE/SLS Secure Elements | ~€15B | ❌ zárt |
| **NXP** | SmartMX, A71CH, EdgeLock | ~€13B | ❌ zárt |
| **STMicroelectronics** | ST33, ST54 | ~€17B | ❌ zárt |
| **Samsung Semiconductor** | embedded Secure Element | — | ❌ zárt |

**Mind zárt, mind drága, mind öröklött architektúrával**. A belépési korlát magas (Common Criteria tanúsítás, partner kapcsolatok, évtizedes IP portfolió), de **a nyílt alternatívák most kezdenek megjelenni**, és a piac **nyitott** rájuk, különösen az EU-ban, ahol a szuverenitás és auditálhatóság egyre fontosabb.

### Big Tech saját SE-jei

| Cég | Chip | Célkör |
|-----|------|--------|
| **Apple** | Secure Enclave (A/M series) | iPhone/Mac/iPad, Face ID, Touch ID, Apple Pay |
| **Google** | Titan M2 (Pixel), Titan (server) | Android secure boot, confidential computing |
| **Samsung** | Knox Vault | Galaxy secure element |
| **Microsoft** | Pluton (AMD, Intel, Qualcomm) | Windows device RoT |

Ezek **mind zártak**, és a nagy tech saját platformjaira vannak tervezve. A külső fejlesztő nem férhet hozzá, nem auditálhatja, nem cserélheti őket.

### Nyílt projektek

#### OpenTitan (Google + lowRISC + partnerek, 2019-)

A **Google által kezdeményezett** első nyílt forráskódú silicon Root of Trust projekt. **Ibex RISC-V** mag (ugyanaz, mint a TROPIC01). Koordinálja a lowRISC alapítvány (Cambridge, UK).

- **Fokus**: datacenter Root of Trust (Google szerverekben)
- **Megjelenés**: első earlgrey chip 2024-ben tape-out, rendelhető
- **Támogatók**: Google, Nuvoton, Winbond, Western Digital, lowRISC
- **Licenszek**: Apache 2.0

#### TROPIC01 (Tropic Square, Prága, 2019-)

Az **első ténylegesen kereskedelmi nyílt secure element**, a SatoshiLabs (Trezor hardware wallet anyacége) támogatásával. Ezt részletesen a következő szekció tárgyalja.

## TROPIC01 — az első nyílt Secure Element részletes elemzése <a name="tropic01-reszletes"></a>

A TROPIC01 **nem csak egy koncepció vagy prototípus** — **2026 Q1-ben full production**, már rendelhető, és az első partner termékek (Trezor hardware wallet új generációja, MikroE Secure Tropic Click) már elérhetők. Ez az **első** valóságos példa arra, amit a CLI-CPU Secure Edition is céloz: **nyílt architektúrájú, auditálható secure element**.

### Architektúra

| Komponens | Részletek |
|-----------|----------|
| **Fő CPU** | **Ibex RISC-V**, dual lock-step konfiguráció (ISO 26262-barátságos, automotive-kompatibilis minta) |
| **Kriptográfiai koprocesszor** | **SPECT** — egyedi ISA-val rendelkező dedikált egység, amelyben a kriptográfiai műveletek futnak. Nem a RISC-V magon! |
| **Csomagolás** | QFN32, ~4×4 mm |
| **Host interfész** | SPI, **encrypted channel forward secrecy-vel** |
| **Memória** | OTP (x.509 és root kulcsok) + Flash (általános adat, PIN) + NVM on-the-fly encryption + ECC védelem + memory address scrambling |

A **SPECT koprocesszor** különösen érdekes tervezési minta: a kriptográfiai workload **nem** a fő RISC-V magon fut, hanem egy dedikált egységen saját ISA-val. Ez **három előnyt ad**:
1. **Biztonság** — a fő OS soha nem lát nyers kulcsot
2. **Sebesség** — a SPECT optimalizált az adott algoritmusokra
3. **Side-channel ellenállás** — a SPECT konstans időben és konstans fogyasztással dolgozik

### Kriptográfia (SPECT gyorsítók)

| Kategória | Algoritmusok |
|-----------|-------------|
| **Aszimmetrikus** | **Ed25519** EdDSA, **P-256** ECDSA, **X25519** Diffie-Hellman |
| **Hash** | SHA-256, SHA-512, **Keccak** (SHA-3) |
| **Szimmetrikus** | **AES-256-GCM** |
| **Lightweight AEAD** | **ISAP** (NIST LWC finalist) |

**Érdekes kimaradás:** a TROPIC01 **nem támogat RSA-t**. Ez **tudatos döntés**: az Ed25519 és ECDSA modernebb, kisebb kulcsokkal dolgozik, és kevésbé érzékeny timing támadásokra. **Nincs legacy.**

### Fizikai biztonság (teljes csomag)

| Komponens | Funkció |
|-----------|---------|
| **Electromagnetic pulse detector** | EM glitch injection védelem |
| **Voltage glitch detector** | tápfeszültség-manipuláció elleni védelem |
| **Temperature sensor** | fagyás + melegítés alapú támadás elleni védelem |
| **Laser detector** | optikai fault injection elleni védelem |
| **Active shield** | fémháló a chip felett, amelynek megszakítása trigger-eli a key zeroization-t |
| **PUF** (Physically Unclonable Function) | chip egyedi fizikai identitás |
| **TRNG** | entrópia forrás kulcsgeneráláshoz |

Ezek a komponensek **általában** évek mérnöki munkát igényelnek, és a zárt gyártók **szigorúan védik** ezeket a design-okat. A Tropic Square **minden részletet publikussá tett**, ami **óriási** ajándék a nyílt hardver közösségnek.

### Nyíltság — ez a kulcs

A TROPIC01 nyíltsága **nem marketing**, hanem **tényleges, ellenőrizhető**:

| Komponens | Státusz | GitHub repó |
|-----------|---------|-------------|
| **Fő dokumentáció** | ✓ publikus | `tropicsquare/tropic01` |
| **RTL (SystemVerilog)** | **✓ publikus** | `tropicsquare/tropic01-rtl` |
| **Application firmware (C)** | **✓ publikus** | `tropicsquare/ts-tr01-app` |
| **SPECT compiler** | **✓ publikus** | külön repó |
| **SPECT firmware** | **✓ publikus** | külön repó |
| **SDK és hostkönyvtárak** | ✓ publikus | Tropic Square GitHub |
| **Development board** | ✓ MikroE Secure Tropic Click | mikroe.com |

Ez **az első Secure Element**, ahol a tulajdonos **valóban leellenőrizheti**, mi van a chipben — nem csak a binárist, hanem a **forrás RTL-t** is. Ez **forradalmi**.

### Érettség

- **Alapítás**: 2019
- **Első tape-out**: ~2023-2024
- **Általános elérhetőség (GA)**: 2025 Q1
- **Full production**: 2026 Q1
- **Embedded World 2026** — nyilvános demonstráció és partnerek bejelentése
- **Referencia termékek**: Trezor új generációs hardware wallet, MikroE Secure Tropic Click

**Fejlesztési idő**: **~6 év** az alapítástól a full production-ig. Ez egy fontos benchmark a saját tervünkhöz.

### Mit tanulunk a TROPIC01-től

1. **A nyílt SE piac létezik és támogatott.** Nem kutatási fantázia, hanem valós piac, valós vásárlókkal, valós partnerekkel.
2. **A SPECT-minta értékes.** Egy dedikált crypto koprocesszor saját ISA-val gyorsabb, biztonságosabb, és side-channel ellenállóbb, mint a fő magon futó crypto.
3. **A tamper detection komplex, de nyíltan megosztható.** A TROPIC01 RTL-ből **megtanulható**, hogyan kell ezeket a komponenseket tervezni.
4. **Az Ibex dual lock-step ISO 26262 barátságos.** Ez egy tudatos választás, ha automotive piacra akarunk menni.
5. **A MikroE partnerség modell átvehető.** Egy hobbista bővítőkártya **drámaian** növeli a fejlesztői közösség elérhetőségét.
6. **Modern crypto only** — RSA mellőzve, csak Ed25519 / ECDSA / X25519 / AES-GCM / Keccak. Ez **tisztább** kódbázis és **kisebb** attack surface.
7. **Fejlesztési időkeret**: ~6 év alapítástól production-ig. Ez reális cél a CLI-CPU Secure Edition-nek is.
8. **SatoshiLabs partnership**: a Bitcoin/crypto közösség **hajlandó pénzt adni** nyílt hardverért, ha a narratíva jó.

## CLI-CPU Secure Edition — pozicionálás és megkülönböztetés <a name="pozicionalas"></a>

### Nem versenytárs, hanem következő generáció

A TROPIC01 **kiváló első generációs nyílt secure element**, és az OpenTitan is a maga datacenter RoT szegmensében erős. Ezek **kihúzzák az utat** a CLI-CPU Secure Edition számára — bizonyítják, hogy a piac létezik, érett, és pénzeli a nyílt alternatívákat.

**A CLI-CPU Secure Edition nem ezek ellen versenyzik.** Egy **következő generációs** megközelítést kínál, ami **más architektúrán alapul**, és a piac **még nem megoldott** problémáira ad választ:

| Szempont | TROPIC01 | OpenTitan | CLI-CPU Secure Edition |
|----------|----------|-----------|------------------------|
| **ISA** | Ibex RISC-V + SPECT | Ibex RISC-V | **CIL (ECMA-335)** |
| **Magok száma** | 1 + lock-step + SPECT | 1 + pár crypto modul | **4-16 Nano + 1-4 Rich + Crypto Actor** |
| **Isolation modell** | Egy security domain, szoftveres applet isolation | Egy security domain | **N független security domain, hardveres shared-nothing** |
| **Programozási nyelv** | C (embedded) | C (embedded) | **C# (modern, type-safe)** |
| **Aktor modell** | ❌ | ❌ | **✓ natív** |
| **Capability-based security** | Korlátozott | Korlátozott | **Natív** |
| **Multi-application support** | Szekvenciális, szoftveres | Szekvenciális | **Párhuzamos, hardveres** |
| **Post-quantum ready** | Tervezett | Kutatási | **Natív (programozható)** |
| **Fejlesztői ökoszisztéma** | Embedded C közösség | Embedded C közösség | **~400 000 NuGet csomag a .NET-ből** |
| **Cél piac elsődleges** | Hardware wallet, single-use SE | Datacenter RoT | **Multi-use, konvergens SE platform** |
| **Érettség** | **Production 2026 Q1** | **Production 2024** | **F0 spec 2026, várható production 2031-2032** |

### A megkülönböztető érv

**A jelenlegi Secure Element piacon egy chip = egy security domain.** Ha egy okosóra egyszerre akar banking SE-t, eSIM-et, eID-t, FIDO2-t, crypto wallet-et és TPM-et, akkor **hat külön chipet** kell beletenni. Ez **fizikailag drága, energiaigényes, és komplex**.

A CLI-CPU Secure Edition **egyetlen chipen több független Secure Element**-et kínál, **hardveres shared-nothing** izolációval. Minden Nano core **egy független secure applet**, amely **matematikailag bizonyítottan** nem tud kommunikálni a többivel, csak a definiált mailbox interfészeken át.

**Ez egy új kategória**, amit sem a TROPIC01 (egy security domain), sem az OpenTitan (egy security domain), sem a klasszikus zárt SE-k (szekvenciális applet model) nem kínálnak.

### Konkrét példa: okostelefon multi-SE

Egy modern okostelefon igényel:
- Banking SE (Apple Pay / Google Pay)
- eSIM (cellahálózat identitás)
- Passport / eID (nemzeti ID, mDL)
- FIDO2 / Passkey (web hitelesítés)
- Crypto wallet (Bitcoin/Ethereum on-device)
- TPM (Windows/Android secure boot)
- Device identity (remote attestation)

**Ma:** 7 Secure Element chip, vagy szoftveresen izolált applet-ek egy chipen (szoftveres verifier-rel, **sebezhetően**).

**TROPIC01-gyel:** egy chip, egy security domain, **szoftveres** applet isolation — megnyerte az **auditálhatóságot**, de nem a **fizikai izolációt**.

**CLI-CPU Secure Edition-nel:** egy chip, **7 külön Nano core**, mindegyik egy teljes aktor-alapú Secure Element, **Rich core** supervisor koordinálja. Ha a banking core valaha kompromittálódna, a többi **architekturálisan érintetlen** — fizikai, hardveres garancia, nem szoftveres remény.

**Ez egy valós, megoldatlan piaci probléma**, amit a CLI-CPU Secure Edition **meg tud oldani**.

## Architekturális illeszkedés — mi adott, mi hiányzik <a name="architekturalis-illeszkedes"></a>

### Amit a jelenlegi CLI-CPU terv **már tartalmaz**

A `docs/architecture.md`, `docs/security.md` és `docs/ISA-CIL-T0.md` már most megadja azokat az alapokat, amelyekre a Secure Edition épülhet, **minimális újratervezéssel**:

| Secure Element követelmény | CLI-CPU status | Fázis |
|---------------------------|----------------|-------|
| **Hardveres memory safety** | ✓ benne van | F3 (Nano core) |
| **Type safety (isinst/castclass)** | ✓ | F5 (Rich core) |
| **Control flow integrity** | ✓ (stack-gép modell) | F3 |
| **Shared-nothing isolation** | **✓ (multi-core)** | **F4** |
| **Non-speculative execution** | ✓ | F3 |
| **Determinizmus** | ✓ | F3 |
| **Kis lapka méret** | ✓ (~8700 std cell / Nano core) | F3 |
| **Alacsony fogyasztás (event-driven)** | ✓ | F3 |
| **Formálisan verifikálható ISA** | ✓ (48 opkód) | F5 |
| **Auditálható (nyílt HDL)** | ✓ | F3 |
| **Multi-application isolation** | **✓ (hardveres)** | **F4** |
| **Immunitás Spectre/Meltdown/ROP/JOP** | ✓ | F3-F5 |
| **Capability-based security (aktor ref)** | ✓ | F5 (Neuron OS) |
| **Supervision hierarchia (fault tolerance)** | ✓ | F5 (Neuron OS) |

Ez egy **nagyon erős kiindulás**. A jelenlegi F0-F6 terv **~80%-ban** lefedi a Secure Element követelményeket, **anélkül hogy azt kifejezetten céloznánk**.

### Amit hozzá **kell** adni

A hiányzó ~20% konkrét, **Secure Element specifikus** hardveres komponenseket igényel, amit a jelenlegi tervhez nem kell, de a Secure Edition-hez **kötelezőek**.

## Szükséges kiegészítések <a name="szukseges-kiegeszitesek"></a>

### 1. Crypto Actor — SPECT-ihletett kriptográfiai koprocesszor

A TROPIC01 SPECT mintáját átvéve, a CLI-CPU Secure Edition-be egy **dedikált Crypto Actor** kerül be. Ez egy külön Nano core-szerű egység, **de saját mikrokódolt instrukciókkal** a kriptográfiai workload-ra optimalizálva.

**Működési minta:**

```
Main actor → send({encrypt: plaintext, with: key_id}) → Crypto Actor
Crypto Actor → (SPECT-szerű mikroprogramot futtat)
Crypto Actor → reply({ciphertext: ..., tag: ...})
```

**Támogatott algoritmusok (F6.5 terv):**

| Kategória | Algoritmusok | Becslés (Sky130 std cell) |
|-----------|-------------|----------------------------|
| Aszimmetrikus | Ed25519, X25519, P-256 ECDSA, P-384 ECDSA | ~15k |
| Hash | SHA-256, SHA-512, SHA-3 (Keccak) | ~4k |
| Szimmetrikus | AES-128/256 (ECB, CBC, CTR, GCM, CCM) | ~3k |
| Lightweight AEAD | ChaCha20-Poly1305, ISAP | ~3k |
| Post-Quantum | **Kyber** (KEM), **Dilithium** (signing), **Falcon** (signing) | **~20k** |
| RSA | **NEM** (tudatos döntés a TROPIC01 mintájára) | — |
| **Összesen** | — | **~45k std cell** |

**A post-quantum algoritmusok beépítése** az elsők között lenne a piacon — ez egy konkrét versenyelőny, ahogy a NIST-standardizált PQC algoritmusok (Kyber, Dilithium, Falcon, SPHINCS+) tömeges bevezetése megindul 2026-2030-ban.

### 2. True Random Number Generator (TRNG)

Entropia forrás kulcsgeneráláshoz. Kötelező minden SE tanúsításhoz.

**Tervezési opciók:**
- **Ring oscillator jitter-alapú** — egyszerű, bevált, de dokumentált támadási felületekkel
- **Metastable flip-flop alapú** — komplexebb, de statikusan elemezhető
- **Diódás shot noise** — analóg, külön IP blokk

**Méret**: ~1-2k std cell + SHA-alapú whitening

**Tanúsítás**: NIST SP 800-90A/B/C megfelelés, AIS 31 (BSI) PTG.2 vagy PTG.3 osztály.

**Tanulás a TROPIC01-től**: a PUF + TRNG kombinációja erős. Az RTL-ükben megnézhető a konkrét implementáció.

### 3. PUF (Physically Unclonable Function)

Egy chip-egyedi fizikai "ujjlenyomat", amely a gyártási toleranciák alapján generál egy egyedi értéket. Két chip **soha nem** fogja ugyanazt a PUF értéket adni, még ugyanazon a waferen sem.

**Felhasználás:**
- **Device identity** — a chip egyedi azonosítója
- **Root key derivation** — a PUF kimenete szolgál master kulcsként
- **Anti-cloning** — egy támadó nem tudja legyártani ugyanazt a chipet
- **Key wrapping** — a tárolt kulcsok a PUF-alapú kulccsal vannak titkosítva

**Tervezési opciók:**
- **SRAM PUF** — bekapcsoláskor az SRAM cellák random állapota adja a PUF-ot
- **Arbiter PUF** — delay-chain alapú összehasonlítás
- **Ring oscillator PUF** — frekvencia-különbség

**Méret**: ~500-1000 std cell + error correction (BCH vagy Reed-Solomon)

### 4. Write-once kulcstárolás (OTP / eFuse)

**eFuse** vagy **antifuse** cellák, amelyekbe **egyszer** lehet írni, és utána csak olvasni. Gyártáskor a gyökér-kulcs és a device identity kerül ide.

**Tipikus méret SE-ben**: 4-16 Kbit OTP

**Fontos**: a OTP **fizikailag elkülönül** a CPU memóriától, és csak egy dedikált **OTP olvasó port** férhet hozzá. A szoftveres réteg **sem** tudja módosítani, csak olvasni (és azt is csak korlátozott módon).

### 5. Secure Boot + Remote Attestation

**Boot lánc:**

```
1. Boot ROM (nem flash, immutable) — legelső futó kód
2. Ellenőrzi a Rich core firmware aláírását
3. Ha OK, betölti és indítja
4. Ha NOK, error állapot + zeroization
```

**Remote attestation:**
A chip **képes egy üzenetet** küldeni egy külső szervernek (attestation server), amely **bizonyítja**:
1. A chip valódi (PUF-alapú chip identity)
2. A firmware hash megfelel az elvártnak
3. A boot folyamat helyesen ment végbe
4. A jelenlegi SE konfiguráció

Ez lehetővé teszi a **remote trust establishment**: egy felhő szerver **megerősítheti**, hogy a kommunikáló eszköz **valóban** egy valódi, auditált CLI-CPU Secure Edition.

### 6. Tamper Detection

A TROPIC01-ből tanulva, a CLI-CPU Secure Edition **ugyanezt a csomagot** kell hogy tartalmazza:

| Komponens | Funkció | Méret |
|-----------|---------|-------|
| **Electromagnetic pulse detector** | EM glitch védelem | ~300 cell |
| **Voltage glitch detector** | tápfeszültség-manipuláció | ~400 cell |
| **Temperature sensor** | thermal attack védelem | ~200 cell |
| **Laser detector** | optikai fault injection | ~500 cell |
| **Active shield** | fémrács mesh, megszakítás detect | layout munka |
| **Frequency monitor** | clock glitch detect | ~200 cell |
| **Összesen** | — | **~1.6k std cell + layout** |

**Fontos**: az active shield **layout szintű** munka, nem RTL. Ezt csak **F6.5 ténylegesen megtervezzünk**, nem lehet átemelni egy "IP core"-ként.

Bármelyik detektor trigger-e **azonnali key zeroization**-t indít: minden érzékeny állapot, kulcs, cache **nullával felülíródik**, és a chip **irreverzibilisen** hibás állapotba kerül. A tamper esemény a OTP-ben rögzítésre kerül, és a chip soha többé nem bootol normálisan.

### 7. Side-Channel Countermeasures (DPA védelem)

A **Differential Power Analysis (DPA)** támadás méri a chip fogyasztását kriptográfiai művelet közben, és statisztikai módszerekkel **kiolvassa a kulcsot**. Ez **az egyik legnehezebben védhető** támadás, és **minden komoly SE** foglalkozik vele.

**Védekezések:**

1. **Masking** — az érzékeny értékeket véletlen maszkkal XOR-olva végezzük a műveleteket, aztán a végén "unmask". A támadó a "kulcs + maszk" értéket látja, nem a kulcsot.
2. **Hiding** — konstans időben és fogyasztással futó algoritmusok. Minden feltételes ágat kiegészítünk dummy műveletekkel.
3. **Noise injection** — véletlenszerű dummy cycle-ök és dummy power consumption.
4. **Constant-time code** — a kriptográfiai primitívek nem ágaznak el érzékeny adattól függően.

**Hatás**: ~15-30% lassabb a crypto, ~10-20% nagyobb terület. **Elengedhetetlen** EAL-5+ tanúsításhoz.

### Összesített hardver budget a Secure Edition-höz

| Komponens | Std cell |
|-----------|----------|
| Alap CLI-CPU (Nano + Rich, F6 terv) | ~200k |
| **Crypto Actor** (AES, SHA, ECC, PQC, SPECT-mintájú) | ~45k |
| **TRNG** | ~2k |
| **PUF** + error correction | ~1.5k |
| **OTP / eFuse** tároló | ~3k (plusz memory cell) |
| **Secure boot ROM** + attestation | ~3k |
| **Tamper detection** (6 komponens) | ~1.6k |
| **DPA countermeasures** (overhead a crypto-n) | ~8k |
| **Összesen a Secure Edition-nek** | **~264k std cell** |

Ez **~32%-kal nagyobb**, mint a standard F6 Cognitive Fabric chip (~200k). **Belefér** egy ChipIgnite MPW-ba (~10 mm² user area), vagy egy IHP SG13G2 MPW-ba (~15 mm²).

## Tanúsítási útvonal <a name="tanusitasi-utvonal"></a>

### Common Criteria (ISO/IEC 15408)

A **Common Criteria** a nemzetközi szabvány az IT biztonsági termékek tanúsítására. Hét EAL (Evaluation Assurance Level) szint van: EAL-1 (legalacsonyabb) és EAL-7 (legmagasabb). A Secure Element-ek tipikusan **EAL-5+** vagy **EAL-6+** tanúsítványt kapnak.

| EAL szint | Vizsgálat intenzitás | Tipikus használat |
|-----------|--------------------|-------------------|
| EAL-1 | Funkcionális teszt | Alapvető termékek |
| EAL-2 | Strukturált teszt | Kereskedelmi szoftverek |
| EAL-3 | Módszeres teszt + dokumentált dev | Kereskedelmi hardver |
| EAL-4 | Dokumentált dev folyamat + code review | Szerver szoftverek |
| **EAL-4+** | Kibővített vulnerability analysis | **eSIM, FIDO** |
| **EAL-5+** | Félig-formális tervezés + verifikáció | **Banking card, eID, TPM** |
| **EAL-6+** | Félig-formális verified tervezés | **High-security government, military** |
| EAL-7 | Formálisan verifikált tervezés | **Kritikus fegyver rendszerek** |

**A CLI-CPU Secure Edition reálisan EAL-5+ célzott**, és **EAL-6+** is elérhető a formálisan verifikálható ISA és az egyszerű mikroarchitektúra miatt.

### Tanúsítási idő és költség

A Common Criteria tanúsítás **nem olcsó és nem gyors**:

| Fázis | Idő | Költség |
|-------|-----|---------|
| Scheme selection (BSI/ANSSI/CCRA) | 1-2 hónap | $10-20k |
| Protection Profile kiválasztás / fejlesztés | 3-6 hónap | $30-50k |
| Evaluation lab kiválasztás és szerződés | 1-2 hónap | $10-20k |
| Tervezés és fejlesztés az EAL szint szerint | 12-24 hónap | **a projekt részeként** |
| Evaluation (a labornál) | 6-12 hónap | **$300-800k** |
| Certification body review | 2-4 hónap | $20-40k |
| **Összesen** | **24-48 hónap** | **$400k-1M** |

Ez **nem kezdő projekt költségkeret**. Az EAL-5+ tanúsítást a CLI-CPU Secure Edition **F6.5 után** (tehát 2031-2032 körül) érdemes elindítani, amikor már van valódi szilícium és tapasztalat.

### Akkreditált laborok

- **BSI** (Németország) — legfontosabb európai tanúsító testület
- **ANSSI** (Franciaország) — második legfontosabb
- **NIAP** (USA) — amerikai NSA-hoz kötődő
- **CCRA** — nemzetközi elfogadási megállapodás

A Tropic Square jelenleg a **BSI** és **ANSSI** felé mozdul. A CLI-CPU Secure Edition ugyanezen az úton haladhat, **tanulva a TROPIC01 tapasztalataiból**.

### Alternatív / kiegészítő tanúsítások

| Tanúsítvány | Fókusz | Releváns piac |
|-------------|--------|---------------|
| **FIPS 140-3** | Kriptográfiai modul | USA kormányzati, IoT, pénzügy |
| **EMVCo** | Banking card | Payment iparág (Visa, Mastercard) |
| **GlobalPlatform** | Secure Element interoperability | SIM, eSIM, mobile payment |
| **GSMA eUICC** | eSIM szabvány | Mobilhálózati ipar |
| **FIDO Certified** | FIDO2 / Passkey authenticator | Web authentikáció |
| **TCG TPM 2.0** | Trusted Computing | Windows, szerver, IoT |

A CLI-CPU Secure Edition **egy termékcsalád**, amely **több tanúsítást szerez** a különböző célterületekre.

## Konkrét termékcsalád és használati módok <a name="termekcsalad"></a>

A CLI-CPU Secure Edition **nem egy chip**, hanem **egy platform**, amelyre **több konkrét termék** épülhet, minden egyes termék egy-egy piaci szegmenset céloz. A **hardveres alap közös**, de a **firmware és a tanúsítás** különböző.

### 1. CLI-CPU Open Banking Card (EMV-kompatibilis)

**Cél**: első nyílt forráskódú, EMV-kompatibilis bankkártya platform.
**Tanúsítás**: EMVCo + EAL-5+
**Megkülönböztető**: a felhasználó **láthatja**, mi fut a kártyáján. Bankbiztonság forradalma.
**Versenytárs**: Thales, Idemia, Infineon banking chip-jei (mind zárt).

### 2. CLI-CPU Open eSIM / iSIM

**Cél**: nyílt SIM/eSIM platform, amelyet a felhasználó **saját maga** flash-elhet a telefonjára, és függetlenül választhat szolgáltatót.
**Tanúsítás**: GSMA eUICC + EAL-4+
**Megkülönböztető**: felhasználói szuverenitás a mobilhálózati identitás felett.
**Versenytárs**: Thales eSIM (zárt).

### 3. CLI-CPU Open eID / Passport

**Cél**: nemzeti elektronikus identitás kártya, ahol a polgár **auditálhatja** a firmware-t.
**Tanúsítás**: ICAO 9303 + EAL-5+
**Megkülönböztető**: **privacy-respecting eGovernment**. Kifejezetten vonzó az EU-ban, az EU Digital Identity Wallet kezdeményezéshez.
**Versenytárs**: Idemia, G+D eID chipek.

### 4. CLI-CPU Open FIDO2 / Passkey Authenticator

**Cél**: YubiKey-alternatíva, auditálható hardver token.
**Tanúsítás**: FIDO Certified Level 2 vagy 3 + EAL-4+
**Megkülönböztető**: **nyílt, auditálható, formálisan verifikálható** FIDO authenticator. A privacy-aware közösség számára.
**Versenytárs**: Yubico (zárt), SoloKeys (részben nyílt, de nem SE alapú).

### 5. CLI-CPU Open TPM 2.0

**Cél**: Trusted Platform Module alternatíva Windows/Linux/szerver/IoT rendszerekhez.
**Tanúsítás**: TCG TPM 2.0 + EAL-4+
**Megkülönböztető**: **Intel PTT és AMD fTPM-et leváltja**, ha valakinek fontos az auditálhatóság. **Microsoft Pluton** alternatíva.
**Versenytárs**: Infineon SLB (TPM 2.0 zárt), Nuvoton NPCT.

### 6. CLI-CPU Open Automotive V2X Secure Element

**Cél**: vehicle-to-everything kommunikáció + digital key + OTA update + remote attestation.
**Tanúsítás**: ISO 21434 + EAL-5+ + ASIL-D
**Megkülönböztető**: **formálisan verifikált, nyílt forrású** automotive SE. Kifejezetten vonzó az EU autóipar számára (CHIPS Act kontextus).
**Versenytárs**: Infineon AURIX Secure Element, NXP A71.

### 7. CLI-CPU Open Medical Secure Element

**Cél**: beültethető és hordozható orvosi eszközök (pacemaker, inzulinpumpa, CGM, neurális implantátum) secure element-je.
**Tanúsítás**: IEC 62304 Class C + HIPAA + EAL-4+
**Megkülönböztető**: **privacy-preserving medical AI inference, tanúsítható device identity, post-quantum ready crypto**. Jelenleg az orvosi eszközök többnyire **elavult 8-bites MCU-k**, mert az új CPU-kat nem tudják tanúsítani. A CLI-CPU modern és tanúsítható.
**Versenytárs**: Microchip, Infineon medical.

### 8. CLI-CPU Open Hardware Wallet

**Cél**: Ledger és Trezor alternatívája, **nyílt forráskódból**.
**Tanúsítás**: EAL-5+ (opcionális)
**Megkülönböztető**: a TROPIC01 **egy** security domain-t ad; a CLI-CPU Secure Edition **több** crypto-t támogat egyszerre (Bitcoin + Ethereum + Solana + monero + ...), mindegyiket külön hardveres security domain-ben. **Multi-chain multi-wallet egyetlen chipen**, biztonságosan.
**Versenytárs**: Trezor (TROPIC01 alapon), Ledger (zárt), GridPlus.

### 9. CLI-CPU Open Validator Node

**Cél**: blockchain validator (Ethereum PoS, Cardano, Solana, Cosmos), **determinisztikus, auditált** módon.
**Tanúsítás**: EAL-5+ (opcionális)
**Megkülönböztető**: **determinisztikus végrehajtás**, **formálisan verifikált consensus logic**, **shared-nothing** minden validator instance között. A validator maintenance drasztikusan egyszerűsödik.
**Versenytárs**: x86 szerverek + szoftveres validator node (nagyon sebezhetőek).

### 10. CLI-CPU Open AI Safety Watchdog

**Cél**: egy kis, formálisan verifikált CLI-CPU Secure Edition **felügyeli** egy nagy AI modell (LLM, agent) döntéseit, és vészleállítja, ha anomáliát észlel.
**Tanúsítás**: IEC 61508 SIL-3/4 + EAL-5+
**Megkülönböztető**: a **formális verifikáció** miatt a watchdog **matematikailag bizonyítottan** nem tud cserben hagyni. Autonóm rendszerek AI safety layer-eként.
**Versenytárs**: nincs közvetlen — új kategória.

## Új fázis: F6.5 — Secure Edition parallel tape-out <a name="f6-5-fazis"></a>

### Cél

A Secure Edition **nem egy önálló projekt**, hanem egy **parallel tape-out variáns** az F6 eFabless ChipIgnite / IHP MPW submission-hoz képest. Ugyanaz az architektúra (Nano + Rich core), **plusz** a Secure Element specifikus komponensek.

### Időzítés

| Esemény | Becsült dátum |
|---------|--------------|
| F6 Cognitive Fabric tape-out | 2029-2030 |
| F6.5 Secure Edition tape-out | **~6 hónappal F6 után** |
| F6.5 bring-up, tesztelés | 2030 Q2 - Q4 |
| F6.5 Common Criteria evaluation kezdet | 2030 Q4 |
| **EAL-5+ tanúsítvány** | **2032-2033** |
| Első kereskedelmi termékek | **2033-2034** |

Ez **reális** a Tropic Square ~6 éves fejlesztési időkerete alapján (2019 → 2025 GA).

### Új tervezési munka F6.5-höz (a meglévő F5 és F6 mellé)

| Komponens | Mérnökmunka becslés |
|-----------|---------------------|
| Crypto Actor (SPECT-inspirált) | 6-12 mérnökhónap |
| TRNG (RO jitter + whitening) | 2-3 mérnökhónap |
| PUF (SRAM PUF + BCH error correction) | 2-4 mérnökhónap |
| OTP / eFuse interfész | 1-2 mérnökhónap |
| Secure boot + attestation | 2-3 mérnökhónap |
| Tamper detection (6 komponens) | 4-6 mérnökhónap |
| Active shield layout | 2-3 mérnökhónap |
| DPA countermeasures | 3-5 mérnökhónap |
| Integration + verification | 4-6 mérnökhónap |
| **Összesen** | **~30-50 mérnökhónap** |

Egy **3-5 fős csapat** számára ez **~1-1.5 év plusz munka** az F6 alapján. Nem triviális, de **reális**, különösen ha a TROPIC01 és OpenTitan publikus IP-ket újrahasználunk.

### Költségek

| Tétel | Becsült költség |
|-------|----------------|
| Plusz mérnökbér (4 fő × 1.5 év) | $0.5-1.2M |
| MPW tape-out (Sky130 ChipIgnite vagy IHP) | $10-50k |
| Evaluation lab szerződés (EAL-5+ cél) | $400k-1M |
| Bring-up board (second variant) | $50-100k |
| **Összesen F6.5 teljes** | **$1-2.5M** |

Ez **jelentős**, de a Trustworthy Silicon pálya (Cognitive Fabric nélkül) **önmagában is** pénzt termel, ha piacot kap.

## Partnerségek és közösség <a name="partnersegek"></a>

### Potenciális partnerek

#### Tropic Square (nem most — F5/F6 körül érdemes kapcsolatba lépni)

**Együttműködési lehetőségek:**
- **Közös IP library**: crypto gyorsítók, TRNG, tamper detection — mindkét projekt profitál
- **Közös tanúsítási tapasztalat**: BSI, ANSSI folyamatok — ők már átmentek rajta
- **Közös EU lobbizás**: Chips Act, Horizon Europe, EU szuverenitás
- **Technikai konferenciák**: 35C3/FOSDEM/TROOPERS előadások együtt
- **Hardveres partnerség**: egy TROPIC01-et akár **használhatunk** egy CLI-CPU chip mellett root of trust-ként

**Nem most**, mert:
- A CLI-CPU F0 spec, nem jutunk még rögtön hardverig
- Először meg kell mutatnunk a saját hozzájárulásunkat (F1 szimulátor, F3 Tiny Tapeout)
- **F5 körül** érdemes kezdeményezni, amikor már van valami demonstrálhatónk

#### OpenTitan konzorcium

A lowRISC által koordinált OpenTitan konzorcium (Google, Nuvoton, Winbond, WD, stb.) egy **érett szervezet**, amely hasonló irányban dolgozik. **Partnerség lehetséges**, különösen a crypto IP és a tanúsítási folyamat terén.

#### SatoshiLabs / Trezor

A SatoshiLabs finanszírozza a Tropic Square-t. Ha a CLI-CPU Secure Edition egy **multi-chain hardware wallet** változatot kínál (ami 10. terméktípus), akkor a **Trezor ökoszisztéma** egy természetes partner.

#### Akadémiai partnerek

| Intézmény | Releváns kutatócsoport | Szerepe |
|-----------|----------------------|---------|
| **Cambridge (UK)** | CHERI, lowRISC | Capability security, open silicon |
| **ETH Zürich** | SafeBoard, ERIS lab | Secure systems, RISC-V |
| **KU Leuven (BE)** | COSIC | Crypto design, side-channel |
| **TU Graz (AT)** | IAIK | Crypto, hardware security |
| **CTU Prague (CZ)** | — | Tropic Square kapcsolat |
| **BME / SZTAKI (HU)** | — | Magyar akadémiai háttér |

**Egy akadémiai partner bevonása** F1-F4 körül, a **formális verifikáció** és a **cryptographic accelerator design** területén, **drámaian gyorsíthatja** a projekt érettségét.

### Közösség építés

A Secure Element közösség **különbözik** a Cognitive Fabric / AI közösségtől:

- **Embedded security** szakemberek (BSI, ANSSI, Common Criteria tapasztalat)
- **Cryptography** kutatók (IACR, post-quantum közösség)
- **Privacy aktivisták** (EFF, Privacy International, Tor, Signal)
- **Crypto/Bitcoin közösség** (hardware wallet felhasználók)
- **Regulatory professionals** (EU Cybersecurity Act, eIDAS, NIS2)

**Konferenciák**, ahol érdemes megjelenni:
- **35C3** (Chaos Communication Congress, Leipzig) — privacy + hardware hacking
- **FOSDEM** (Brüsszel) — open source foundation
- **TROOPERS** (Heidelberg) — enterprise security
- **RSA Conference** (San Francisco) — kereskedelmi SE piac
- **Embedded World** (Nürnberg) — ahol a Tropic Square is szerepel

## Realista időskála <a name="idoskala"></a>

A CLI-CPU Secure Edition **nem egy gyors projekt**. A Tropic Square tanulsága: **~6 év** az alapítástól a full production-ig, és **2-3 év** a Common Criteria tanúsításig.

| Év | Fázis | Esemény |
|----|-------|--------|
| **2026** | F0 | Spec dokumentumok (beleértve ezt) |
| **2026-2027** | F1 | C# referencia szimulátor |
| **2027** | F2 | RTL, Nano core egymagos |
| **2027-2028** | F3 | Tiny Tapeout (Nano core + mailbox) — első szilícium |
| **2028** | F4 | FPGA 4× Nano multi-core (A7-Lite 200T) |
| **2028-2029** | F5 | Rich core + heterogén FPGA (A7-Lite 200T) |
| **2029-2030** | F6-FPGA | Heterogén Cognitive Fabric FPGA-verifikáció (3× A7-Lite 200T multi-board) |
| **2030** | F6-Silicon | ChipIgnite tape-out (csak F6-FPGA verifikáció után) |
| **2030-2031** | **F6.5** | **Secure Edition parallel tape-out** |
| **2030-2031** | — | Bring-up, belső tesztelés |
| **2031** | — | Common Criteria evaluation kezdete |
| **2032-2033** | — | **EAL-5+ tanúsítvány megszerzése** |
| **2033** | — | **Első kereskedelmi Secure Edition termékek** |
| **2034-2035** | — | Banking / eSIM / FIDO / TPM termékek piacon |
| **2035-2040** | — | Piaci részesedés szerzése, multi-use SE ökoszisztéma |

Ez **9-10 év** az első spec-től a kereskedelmi Secure Edition termékig. **Nem rövid táv**, de ez a **valóság** egy Common Criteria-tanúsított nyílt chip esetén, és reális a Tropic Square példája alapján.

## Következő lépések <a name="kovetkezo-lepesek"></a>

A Secure Edition **nem sürget** semmit az F1-F4 fázisokban, mert a Cognitive Fabric + Trustworthy Silicon pályák **természetesen** hordozzák az alapokat. Amit most tenni kell:

### Rövid táv (F1 szimulátor mellett, 2026-2027)

1. **Ne módosítsd a meglévő F1-F4 terveket** — a Cognitive Fabric és a Trustworthy Silicon **természetesen** halad
2. **Kezdeményezd a kapcsolatot** egy crypto kutatócsoporttal (KU Leuven COSIC, TU Graz IAIK, vagy magyar akadémiai), hogy legyen egy **akadémiai szponzorunk** a Secure Edition tervhez
3. **Figyeld a Tropic Square fejlődését** — különösen a BSI/ANSSI tanúsítási tapasztalatokat és a publikus IP library-jét

### Közép táv (F4 multi-core után, 2028-2029)

4. **Első formális Crypto Actor design** — F5-höz kapcsolódóan, de már a Secure Edition-re is figyelve
5. **Post-quantum crypto integráció** — a Kyber/Dilithium/Falcon implementációkat már most érdemes vizsgálni
6. **Kapcsolatfelvétel a Tropic Square-rel** — hivatalos együttműködési megkeresés F5 környékén
7. **EU finanszírozás** (Horizon Europe, EU Chips Act) — a Trustworthy Silicon pálya részeként, kiegészítve a Secure Edition-nel

### Hosszú táv (F6 után, 2030+)

8. **F6.5 tape-out** — a Cognitive Fabric tape-out után 6 hónappal, parallel
9. **Common Criteria evaluation** — BSI vagy ANSSI akkreditált laborban
10. **Első termékek** — valószínűleg hardware wallet (Trezor-szerű) vagy FIDO2 authenticator (YubiKey-szerű), mert ezek a legkisebb belépési küszöbök

## Kapcsolat a többi dokumentummal

- [`docs/security.md`](security.md) — A hardveres biztonsági tulajdonságok itt vannak dokumentálva; a Secure Edition ezekre épül.
- [`docs/architecture.md`](architecture.md) — A heterogén Nano + Rich multi-core architektúra a Secure Edition alapja is.
- [`docs/roadmap.md`](roadmap.md) — Az F6.5 fázis itt kerül rögzítésre.
- [`docs/neuron-os.md`](neuron-os.md) — A Neuron OS aktor-alapú modellje **természetesen** támogatja a multi-SE hardveres isolation-t.

## Záró gondolat

A Secure Element piac **óriási** (~$30-40B), **érett**, és **most nyílik** a nyílt forrású alternatívákra (TROPIC01, OpenTitan bizonyítja). A CLI-CPU Secure Edition **természetesen** illeszkedik ebbe a térbe, mert az alap architektúra (stack-gép, shared-nothing, formálisan verifikálható ISA, kicsi méret, alacsony fogyasztás) **pontosan** az, amit a SE piac keres.

A **megkülönböztető pozíciónk** nem az, hogy "még egy nyílt SE" — hanem hogy **multi-core, aktor-alapú, több független security domain egyetlen chipen**. Ez egy **új kategória**, amit sem a TROPIC01, sem az OpenTitan, sem a zárt gyártók nem kínálnak. A jövő Secure Element-je **több security domain-t** fog igényelni (okosóra okostelefon banking + eSIM + eID + FIDO + wallet + TPM), és a CLI-CPU Secure Edition **készen áll** erre.

**A Tropic Square megmutatta, hogy a piac reális és elérhető.** A CLI-CPU Secure Edition **a következő lépést teszi**: ugyanazt az auditálhatóságot és nyíltságot, **egy generációval jobb architektúrán**.

---

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-14 | Kezdeti verziózott kiadás |
