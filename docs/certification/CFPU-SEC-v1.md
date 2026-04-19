# CFPU-SEC-v1 -- Kotelező Biztonsagi Elemek Specifikacioja

> Version: 1.0 | Datum: 2026-04-17

> English version: CFPU-SEC-v1-en.md (TODO)

Ez a dokumentum a **CFPU Certified** tanusito vedjegy (certification mark) technikai alapjat kepezi. Meghatarozza azokat a **kotelezo biztonsagi elemeket**, amelyek teljesuleset a CFPU Foundation ellenorzi es tanusitja. A dokumentum egyben az EUIPO tanusito vedjegy bejelenteshez szukseges **Regulations of Use** vazat is tartalmazza.

## Tartalom

1. [Cel es hatalyossag](#cel)
2. [Hivatkozott dokumentumok](#hivatkozasok)
3. [Kotelezo biztonsagi elemek (S1-S12)](#elemek)
4. [Tanusitasi szintek](#szintek)
5. [Konformancia-teszt vazlat](#tesztek)
6. [Tanusitvany formatum es regiszter](#tanusitvany)
7. [Regulations of Use (EUIPO tanusito vedjegy)](#regulations)
8. [Eletciklus es verziozas](#eletciklus)
9. [Changelog](#changelog)

## Cel es hatalyossag <a name="cel"></a>

### Mit tanusit a CFPU Certified vedjegy

A **CFPU Certified** tanusito vedjegy (EU certification mark, Nice osztaly: 9 + 42) azt tanusitja, hogy egy CFPU-architekturaju chip vagy modul **megfelel** a jelen specifikacioban leirt kotelezo biztonsagi elemeknek. A vedjegy **nem** a gyartot azonositja, hanem **egy technikai tulajdonsagot** tanusit a termekrol.

### Kire vonatkozik

- Barmely jogi vagy termeszetes szemely, aki CFPU-architekturaju chipet gyart, forgalmaz, vagy CFPU-kompatibilis IP-blokkot licencel
- A tanusitas **nem diszkriminativ** -- barkinek elerheto, aki atment a konformancia-teszten es fizette a regisztracios dijat

### Mire NEM vonatkozik

- Szoftveres kompatibilitas (CIL toolchain, Neuron OS alkalmazasok) -- ez kulon tanusitasi program
- Fizikai tamper-resistance (dekapszulacio, FIB-tamadas) -- ez a threat model-en kivul esik
- Teljesitmeny vagy energiahatekonysag -- a CFPU-SEC kizarolag biztonsagi property-ket vizsgal

## Hivatkozott dokumentumok <a name="hivatkozasok"></a>

| Dokumentum | Helye | Relevancia |
|-----------|-------|------------|
| Seal Core architektura | [`docs/sealcore-hu.md`](../sealcore-hu.md) | S1, S2, S3 elemek: a hitelesitesi gatekeeper core |
| AuthCode + CodeLock | [`docs/authcode-hu.md`](../authcode-hu.md) | S3, S4, S11, S12 elemek: kodalairasi es W-xor-X mechanizmus |
| Quench-RAM memoriacella | [`docs/quench-ram-hu.md`](../quench-ram-hu.md) | S5, S6, S7 elemek: per-blokk status-bit es atomi wipe |
| Security Model | [`docs/security-hu.md`](../security-hu.md) | S8, S9, S10 elemek: izolacio, CFI, stack vedelem |
| ISA specifikacio | [`docs/ISA-CIL-T0-hu.md`](../ISA-CIL-T0-hu.md) | S9, S10 elemek: opkod-szintu bounds check |
| Architektura | [`docs/architecture-hu.md`](../architecture-hu.md) | S4, S8 elemek: Harvard-architektura, shared-nothing |

## Kotelezo biztonsagi elemek (S1--S12) <a name="elemek"></a>

Minden elem egy **verifikalhat property**: egy hardveres garancia, amelynek teljesulese automatizalt teszttel ellenorizheto. Az elemek **nem implementacios reszletek** -- nem irjak elo a gate-szamot, a pipeline-melyseg et vagy a chip-technologiat. Csak a **megfigyelheto viselkedest** rogzitik.

---

### S1 -- Seal Core jelenleteS1 -- Seal Core jelenlet es aktivitas

> **Forras:** [`sealcore-hu.md`](../sealcore-hu.md) SS mi-a-sealcore

**Kovetelmeny:** A chip tartalmaz legalabb egy (1) Seal Core-t, amely boot utan aktiv es heartbeat-jelet ad.

**Verifikacio:**
- Boot-szekvencia utan a health monitor `alive[i]` flag aktiv legalabb egy Seal Core-ra
- A Seal Core valaszol self-test lekerdezesre (firmware hash report)

**Indoklas:** A Seal Core a CFPU biztonsagi modelljeben a trust anchor -- nelkule nincs AuthCode verify, nincs SEAL trigger forras, es a kodbetoltes hitelessege nem garantalhato.

---

### S2 -- Seal Core firmware immutabilitas

> **Forras:** [`sealcore-hu.md`](../sealcore-hu.md) SS boot

**Kovetelmeny:** A Seal Core firmware-je **nem modosithato** a chip elettartama alatt. A firmware tarolas modja: mask ROM, OTP eFuse, vagy flash + eFuse-integrity-check. A firmware hash az eFuse-ban rogzitett.

**Verifikacio:**
- `SHA-256(firmware_readback) == eFuse.SealCoreFirmwareHash`
- Irasi kiserletek a firmware-taroloba trap-et vagy no-op-ot eredmenyeznek

**Indoklas:** Ha a Seal Core firmware-jet tamperelni lehetne, az egesz trust chain osszeomlik (a hitelesito maga hiteltelen).

---

### S3 -- AuthCode verify gate

> **Forras:** [`authcode-hu.md`](../authcode-hu.md) SS authcode, [`sealcore-hu.md`](../sealcore-hu.md) SS qram

**Kovetelmeny:** Minden CIL bytecode, amely a chip CODE regiojaba kerul, **kotelezo jelleggel** athalad az AuthCode verifikacion. Az AuthCode verify flow harom lepest tartalmaz:
1. `SHA-256(bytecode) == cert.PkHash`
2. `BitIceCertificateV1.Verify(cert, eFuse.CaRootHash)`
3. `cert.SubjectId notIn revocation_list`

Barmely lepes bukasa eseten a bytecode **nem kerul betoltesre** es trap generalodik.

**Verifikacio:**
- Alairatlan `.acode` kontener betoltese -> `INVALID_SIGNATURE` trap, CODE regio valtozatlan
- Tamperelt bytecode (1 bit flip) -> `CODE_HASH_MISMATCH` trap
- Ervenyes `.acode` -> sikeres betoltes, aktor indithato

**Indoklas:** Az AuthCode a "single gate" elv megvalositasa -- a chipen csak es kizarolag alatirt, ellenorzott kod futhat.

---

### S4 -- CodeLock W-xor-X hardveres szeparacio

> **Forras:** [`authcode-hu.md`](../authcode-hu.md) SS codelock

**Kovetelmeny:** A chip hardveresen **fizikailag** kikenyszeriti a W-xor-X (Write XOR Execute) szeparaciot:
- Write-to-CODE trap: barmelyik core irasra probal a CODE regioba -> `WRITE_TO_CODE_DENIED`
- Execute-from-DATA trap: a PC (program counter) DATA/STACK cimre mutat -> `EXECUTE_FROM_DATA`
- PC range check: minden instruction fetch ellenorzi, hogy a PC ervenyes CODE tartomanyban van

**Verifikacio:**
- Memoria-iras a CODE regio cimere -> `WRITE_TO_CODE_DENIED` trap
- PC beallitasa DATA regiobeli cimre (branch/call) -> `EXECUTE_FROM_DATA` trap
- ROP/JOP gadget-lep: stack-re irt "visszateresi cim" DATA-ba mutat -> trap

**Indoklas:** A CodeLock biztositja, hogy a betoltott kod bitre valtozatlan marad (integrity), es adat soha nem ertelmezodik kodkent (shellcode injection kizaras).

---

### S5 -- Quench-RAM SEAL/RELEASE allapotgep-invarians

> **Forras:** [`quench-ram-hu.md`](../quench-ram-hu.md) SS allapotgep

**Kovetelmeny:** Minden Quench-RAM blokk rendelkezik **egy status-bittel** (0 = mutable, 1 = sealed/immutable). A kovetkezo invarians **minden ciklus utan** igaz:

> `status = 0` implikálja `data = 0...0` (minden allokalhato blokk zero-initialized)

Ez ket atmeneti muveletet jelent:
- `SEAL`: 0 -> 1 (adat valtozatlan, blokk immutable-le valik)
- `RELEASE`: 1 -> 0 **es** `data <- 0^N` (atomi, 1 ciklus)

Mas allapot-atmenet **nem letezik**.

**Verifikacio:**
- RELEASE utan a blokk minden bitje 0 (readback verify)
- Sealed blokk irasi kiserlete -> trap vagy no-op
- Frissen allokalt blokk (status=0) tartalma 0 (zero-init garancia)

**Indoklas:** A Quench-RAM invarians a use-after-free, information leak, es cold boot key recovery tamadasokat fizikailag zarja ki.

---

### S6 -- Quench-RAM atomi wipe

> **Forras:** [`quench-ram-hu.md`](../quench-ram-hu.md) SS isa-primitivek

**Kovetelmeny:** A `RELEASE` muvelet **egyetlen orajel-ciklusban** vegrehajtja a status-bit reset-et (1 -> 0) es az osszes adatbit nullazasat. A ket esemeny **atomi** -- nincs koztes allapot, ahol a blokk "released-de-szennyezett" lenne.

**Verifikacio:**
- Idozites-meres: RELEASE -> kovetkezo ciklusban a blokk status=0 es data=0
- Nincs koztes allapot olvasas lehetoseg (a broadcast-clear az SRAM sor teljes szelessegeben egyidejuleg hat)

**Indoklas:** A nem-atomi wipe ablakot nyitna timing-alapu tamadasokra (a felszabaditas es a torles kozott az adat kiolvashatona lenne).

---

### S7 -- Trust boundary: SEAL/RELEASE nem hivhato CIL-bol

> **Forras:** [`quench-ram-hu.md`](../quench-ram-hu.md) SS trust-boundary

**Kovetelmeny:** A `SEAL` es `RELEASE` **hardveres allapotgep-muveletek (HW FSM)**, amelyeket **kizarolag** jol-meghatarozott trigger-esemenyek hivhatnak meg:

| Primitiv | Engedelyezett triggerek |
|----------|------------------------|
| `SEAL` | CODE regio (Seal Core boot / `hot_code_loader`), `SEND` (payload kilep a Core-bol), Swap-out (DMA evict kulso QRAM-ba) |
| `RELEASE` | `GC_SWEEP` (csak a hivo aktor sajat heap-jen), `hot_code_loader` unload, Swap-in (kulso QRAM-bol visszatoltes) |

CIL alkalmazas-szintrol **semmilyen uton** nem erheto el sem SEAL, sem RELEASE.

**Verifikacio:**
- SEAL/RELEASE kizarolag HW FSM trigger-esemenyre aktivizalodik, CIL-bol nem erheto el
- Egy aktor `GC_SWEEP`-je **csak** a sajat heap-jen hat, mas aktor blokkjait nem erinti

**Indoklas:** Ha egy rosszindulatú aktor tetszolegesen SEAL-elhetne vagy RELEASE-elhetne blokkokat, a Quench-RAM biztonsagi garanciai ervenytelenek lennenek.

---

### S8 -- Per-aktor heap izolacio (shared-nothing)

> **Forras:** [`security-hu.md`](../security-hu.md) SS 4, [`architecture-hu.md`](../architecture-hu.md)

**Kovetelmeny:** Minden aktor **sajat, privat SRAM heap-en** dolgozik. Ket kulonbozo aktor memoriateruletenek **nincs** fizikai atfedese. Cross-core memoriairas **fizikailag lehetetlen** (a bus-routing nem engedi).

**Verifikacio:**
- Aktor A megprobal irni Aktor B heap-cimere -> `INVALID_MEMORY_ACCESS` trap
- Aktor A megprobal olvasni Aktor B heap-cimerol -> `INVALID_MEMORY_ACCESS` trap
- Mailbox SEND/RECEIVE az egyetlen cross-aktor kommunikacios utvonal

**Indoklas:** A shared-nothing izolacio a cross-core side-channel tamadasok (Foreshadow, L1TF, false sharing) fizikai kizarasanak alapja.

---

### S9 -- Vezerlesifoly am-integritas (CFI)

> **Forras:** [`security-hu.md`](../security-hu.md) SS 3

**Kovetelmeny:** A chip **hardveresen** kikenyszeriti a vezerlesifoly am-integritast:

| Ellenorzes | Kovetelmeny |
|-----------|-------------|
| Call target | Minden `call`/`callvirt` cel **CIL metaadat szerinti metodus-belepesi pont** |
| Return target | A `ret` **hardveres frame pointer-bol** veszi a visszateresi cimet, nem a user stack-rol |
| Branch target | Minden `br*` cel a **jelenlegi metodus kodtartomanyan belul** |

**Verifikacio:**
- Tetszoeleges cimre mutato `call` -> `INVALID_CALL_TARGET` trap
- Stack-manipulacioval hamisitott visszateresi cim -> `INVALID_BRANCH_TARGET` trap
- Metoodus-hataron tuli branch -> `INVALID_BRANCH_TARGET` trap

**Indoklas:** A CFI a ROP es JOP tamadasok fizikai kizarasa -- ez onmagaban ~30-40%-at fedi a publikalt kernel-exploiteknek.

---

### S10 -- Stack bounds check

> **Forras:** [`security-hu.md`](../security-hu.md) SS 1, [`ISA-CIL-T0-hu.md`](../ISA-CIL-T0-hu.md)

**Kovetelmeny:** Minden stack-muvelet (push, pop, ldloc, stloc, ldarg, starg) **hardveresen ellenorzott**:
- Stack overflow -> `STACK_OVERFLOW` trap
- Stack underflow -> `STACK_UNDERFLOW` trap
- Lokalis valtozo index >= lokalis count -> `INVALID_LOCAL` trap
- Argumentum index >= arg count -> `INVALID_ARG` trap

**Verifikacio:**
- Recurziv hivasok amelyek tullepik a stack-meretet -> `STACK_OVERFLOW` trap (nem korlalatlan stack-novekedes)
- Ures stack-rol pop -> `STACK_UNDERFLOW` trap
- `ldloc 99` amikor csak 3 lokalis van -> `INVALID_LOCAL` trap

**Indoklas:** A stack bounds check a buffer overflow es stack smashing tamadasok hardveres kizarasa.

---

### S11 -- eFuse CA Root Hash jelenlet

> **Forras:** [`authcode-hu.md`](../authcode-hu.md) SS trustchain

**Kovetelmeny:** A chip eFuse-aban **32 byte CA Root Hash** rogzitett, amely a BitIce trust chain gyokere. Az eFuse tartalma:
- Gyartaskor vagy elso boot-kor irhato (OTP -- one-time programmable)
- Az iras utan **soha nem modosithato**
- Boot-kor olvasható a Seal Core firmware altal

**Verifikacio:**
- eFuse readback: nem csupa-nulla (programozott)
- Az eFuse tartalom megegyezik a Foundation CA Root publikus hash-sel
- Irasi kiserletek az eFuse-ra -> no-op vagy trap (OTP jelleg)

**Indoklas:** Az eFuse CA Root Hash a trust chain fizikai gyokere. Nelkule az AuthCode verify-nak nincs mihez hasonlitania -- barmely cert elfogadhatova valna.

---

### S12 -- Revocation list tamogatas

> **Forras:** [`authcode-hu.md`](../authcode-hu.md) SS revocation, [`sealcore-hu.md`](../sealcore-hu.md)

**Kovetelmeny:** A Seal Core firmware kepes egy **revocation list**-et tarolni es a cert-verify soran felhasznalni. Egy revokalt `SubjectId`-vel alairt `.acode` kontener betoltese -> `CERT_REVOKED` trap.

**Verifikacio:**
- Revocation list frissites utan az erintett SubjectId-vel alairt `.acode` betoltese -> `CERT_REVOKED` trap
- Nem-revokalt cert -> tovabbra is sikeres betoltes
- Revocation list tarolasi kapacitas: legalabb 64 revoked entry (v1.0 minimum)

**Indoklas:** A revokacio nelkuli rendszerben egy kompromittalt fejlesztoi kartya **orokre** ervenyes cert-eket ad ki. A revocation list biztositja, hogy a Foundation visszavonhassa a kompromittalt cert-eket.

---

## Tanusitasi szintek <a name="szintek"></a>

A CFPU-SEC-v1 **harom szintet** definiál, amelyek a chip fejlettsegehez es a felhasznalasi kontextushoz igazodnak:

### CFPU-SEC-v1-Basic

**Fazis:** F3--F5 (pre-QRAM era, kulso CODE RAM)

**Kotelezo elemek:**

| Elem | Kovetelmeny | Mechanizmus |
|------|------------|-------------|
| S1 | Seal Core jelenlet | legalabb 1 aktiv |
| S2 | Firmware immutabilitas | mask ROM / eFuse |
| S3 | AuthCode verify gate | minden code-load a Seal Core-on at |
| S4 | CodeLock W-xor-X | fizikai WE-pin routing (pre-QRAM) |
| S8 | Shared-nothing izolacio | per-core SRAM, nincs shared bus |
| S9 | CFI | call/ret/branch target verify |
| S10 | Stack bounds check | overflow/underflow trap |

**Nem kotelezo (pre-QRAM-ban nem releváns):** S5, S6, S7 (Quench-RAM), S11, S12 (eFuse + revocation)

**Indoklas:** A pre-QRAM eraban a CODE vedelem fizikai WE-pin routing-on alapul, nem Quench-RAM status-biten. A Basic szint a korai sziliciumra (Tiny Tapeout, FPGA) vonatkozik, ahol a Quench-RAM meg nem erheto el.

---

### CFPU-SEC-v1-Full

**Fazis:** F5+ (QRAM era, on-chip Quench-RAM)

**Kotelezo elemek:** **Minden S1--S12.**

| Elem | Kovetelmeny |
|------|------------|
| S1 | Seal Core jelenlet (legalabb 1) |
| S2 | Firmware immutabilitas |
| S3 | AuthCode verify gate |
| S4 | CodeLock W-xor-X (Quench-RAM status-bit alapu) |
| S5 | Quench-RAM SEAL/RELEASE invarians |
| S6 | Quench-RAM atomi wipe |
| S7 | Trust boundary (SEAL/RELEASE nem hivhato CIL-bol) |
| S8 | Shared-nothing izolacio |
| S9 | CFI |
| S10 | Stack bounds check |
| S11 | eFuse CA Root Hash |
| S12 | Revocation list tamogatas |

**Indoklas:** Az F5+ eraban a Quench-RAM elerheto, es a teljes biztonsagi modell (AuthCode + CodeLock + Quench-RAM + Seal Core) egyutt mukodik. Ez a cel-szint az ipari alkalmazasokhoz.

---

### CFPU-SEC-v1-Redundant

**Fazis:** F6+ (production silicon)

**Kotelezo elemek:** **Minden S1--S12**, plusz:

| Elem | Kovetelmeny |
|------|------------|
| S1+ | Legalabb **2** aktiv Seal Core |
| S1++ | Health monitor heartbeat (HW FSM, nem szoftveresen vezerelt) |
| S1+++ | Graceful degradation: 1 Seal Core kiesese eseten a rendszer tovabb mukodik |

**Indoklas:** A Redundant szint a safety-critical alkalmazasokra (IEC 61508 SIL-3+, ISO 26262 ASIL-B+) keszul, ahol egyetlen HW-hiba nem okozhat teljes rendszerlealst.

---

### Tanusitasi szintek osszefoglalo tablazata

| Szint | Fazis | Kotelezo elemek | Seal Core min. | Quench-RAM | Revocation |
|-------|-------|----------------|----------------|------------|------------|
| **Basic** | F3--F5 | S1-S4, S8-S10 | 1 | nem | nem |
| **Full** | F5+ | S1--S12 | 1 | igen | igen |
| **Redundant** | F6+ | S1--S12 + redundancia | 2+ | igen | igen |

## Konformancia-teszt vazlat <a name="tesztek"></a>

A konformancia-tesztsuite **automatizalt, reprodukalhato** tesztekbol all. Minden teszt egy S-elemre hivatkozik, es egy **PASS/FAIL** eredmenyt ad. A tesztsuite nyilt forrasu (a CLI-CPU repo resze), es futtathatot mind szimulátoron (`TCpu`), mind fizikai sziliciumon.

### Teszthalmazok

#### TH-1: Seal Core boot es eletjel (S1, S2)

| Teszt ID | Leiras | Elvárt eredmeny |
|----------|--------|-----------------|
| TH-1.1 | Boot utan health monitor lekerdezese | legalabb 1 Seal Core `alive` |
| TH-1.2 | Seal Core firmware hash readback | `SHA-256(fw) == eFuse.SealCoreFwHash` |
| TH-1.3 | Firmware-taroloba iras kiserlete | trap vagy no-op, firmware valtozatlan |

#### TH-2: AuthCode verify (S3, S11, S12)

| Teszt ID | Leiras | Elvárt eredmeny |
|----------|--------|-----------------|
| TH-2.1 | Ervenyes `.acode` betoltes | sikeres, aktor indithato |
| TH-2.2 | Alairatlan `.acode` betoltes | `INVALID_SIGNATURE` trap |
| TH-2.3 | Tamperelt bytecode (1 bit flip) | `CODE_HASH_MISMATCH` trap |
| TH-2.4 | Ervenyes cert, de revokalt SubjectId | `CERT_REVOKED` trap |
| TH-2.5 | Ervenyes cert, de eFuse CA Root Hash nem egyezik | `INVALID_SIGNATURE` trap |
| TH-2.6 | eFuse CA Root Hash readback | nem csupa-nulla |

#### TH-3: CodeLock W-xor-X (S4)

| Teszt ID | Leiras | Elvárt eredmeny |
|----------|--------|-----------------|
| TH-3.1 | Iras CODE regio cimere | `WRITE_TO_CODE_DENIED` trap |
| TH-3.2 | PC -> DATA regio (branch) | `EXECUTE_FROM_DATA` trap |
| TH-3.3 | PC -> STACK regio (ROP-szeru) | `EXECUTE_FROM_DATA` trap |
| TH-3.4 | Ervenyes CODE-bol fetch | sikeres, nincs trap |

#### TH-4: Quench-RAM invariansok (S5, S6, S7) -- csak Full/Redundant

| Teszt ID | Leiras | Elvárt eredmeny |
|----------|--------|-----------------|
| TH-4.1 | RELEASE utan blokk readback | minden bit = 0 |
| TH-4.2 | Sealed blokk irasi kiserlete | trap vagy no-op |
| TH-4.3 | Frissen allokalt blokk tartalma | minden bit = 0 |
| TH-4.4 | RELEASE atomicitas (timing) | 1 ciklus, nincs koztes allapot |
| TH-4.5 | SEAL/RELEASE csak HW FSM triggerekre aktivizalodik | CIL-bol nem erheto el, nincs ilyen opkod |
| TH-4.6 | GC_SWEEP mas aktor heap-jen | `INVALID_MEMORY_ACCESS` trap |

#### TH-5: Izolacio es CFI (S8, S9, S10)

| Teszt ID | Leiras | Elvárt eredmeny |
|----------|--------|-----------------|
| TH-5.1 | Cross-core memoria iras | `INVALID_MEMORY_ACCESS` trap |
| TH-5.2 | Cross-core memoria olvasas | `INVALID_MEMORY_ACCESS` trap |
| TH-5.3 | `call` ervenytelen celcimre | `INVALID_CALL_TARGET` trap |
| TH-5.4 | `ret` hamisitott visszateresi cimmel | `INVALID_BRANCH_TARGET` trap |
| TH-5.5 | Branch metodus-hataron tul | `INVALID_BRANCH_TARGET` trap |
| TH-5.6 | Stack overflow (melyen rekurziv) | `STACK_OVERFLOW` trap |
| TH-5.7 | Stack underflow (ures stack-rol pop) | `STACK_UNDERFLOW` trap |
| TH-5.8 | `ldloc` ervenytelen index | `INVALID_LOCAL` trap |

#### TH-6: Redundancia (csak Redundant szint)

| Teszt ID | Leiras | Elvárt eredmeny |
|----------|--------|-----------------|
| TH-6.1 | 2+ Seal Core alive boot utan | health monitor: alive count >= 2 |
| TH-6.2 | 1 Seal Core szimulalt kieses | a masik atveszi, code-load tovabb mukodik |
| TH-6.3 | Heartbeat timeout detektalas | dead[i] flag set a health monitor-ban |

### Konformancia-teszt eredmeny-formatum

```json
{
  "schemaVersion": "CFPU-SEC-v1",
  "chipId": "CFPU-2026-XXXX",
  "testSuiteVersion": "1.0.0",
  "level": "Full",
  "timestamp": "2026-04-17T12:00:00Z",
  "results": {
    "TH-1.1": "PASS",
    "TH-1.2": "PASS",
    "TH-2.1": "PASS",
    "...": "..."
  },
  "summary": {
    "total": 27,
    "passed": 27,
    "failed": 0,
    "verdict": "PASS"
  }
}
```

A `verdict` ertek:
- **PASS** -- minden teszthalmazban minden teszt PASS -> tanusitvany kiadhato
- **FAIL** -- barmely teszt FAIL -> tanusitvany **nem** adhato ki

Reszleges megfeleles **nem letezik**. Egy szinten belul minden elem kotelezo.

## Tanusitvany formatum es regiszter <a name="tanusitvany"></a>

### Elektronikus tanusitvany

A CFPU Foundation **elektronikus tanusitvanyt** allit ki W3C Verifiable Credential formatumban, a Foundation Ed25519 (vagy PQC) eSeal-jevel alairt. Minden kiadott tanusitvany tartalmazza:

| Mezo | Leiras |
|------|--------|
| `id` | Egyedi URI: `https://cfpu.org/registry/CFPU-YYYY-NNNN` |
| `issuer` | `did:web:cfpu.org` (CFPU Foundation) |
| `issuanceDate` | Kiadas datuma |
| `expirationDate` | Lejarati datum (alapertelmezett: 2 ev) |
| `credentialSubject.sku` | Chip SKU / termek-azonosito |
| `credentialSubject.manufacturer` | Gyarto neve |
| `credentialSubject.conformanceLevel` | `Basic` / `Full` / `Redundant` |
| `credentialSubject.testSuiteVersion` | Hasznalt tesztsuite verzio |
| `credentialSubject.mandatoryElements` | S1--S12 PASS/N-A statusok |
| `proof` | Ed25519Signature2020 vagy WOTS+ alairás |

### Publikus regiszter

A Foundation a `https://cfpu.org/registry/` cimen **publikus, lekerdezhetot, auditalhato regisztert** tart fenn:

- **Kereses:** gyarto, SKU, szint, datum szerint
- **API:** `GET /registry/{id}` -> JSON-LD Verifiable Credential
- **Statusz:** `GET /registry/{id}/status` -> `valid` | `revoked` | `expired`
- **CRL:** `GET /registry/crl.json` -> visszavont tanusitványok listaja
- **Transparency log:** append-only Merkle-fa (opcionalis, sigstore/rekor kompatibilis)

### Tanusitvany visszavonas

A Foundation visszavonhat tanusitvanyt ha:
- Utolag biztonsagi hiba derul ki a tanusitott chipben
- A gyarto megteveszto adatokat szolgaltatott
- A chip modosult a tanusitas ota (uj revizio tanusitas nelkul)

A visszavont tanusitvany a CRL-en es a regiszterben `revoked` statuszba kerul. A tanusitvany-tulajdonos 30 napon belul fellebbezhet.

## Regulations of Use -- EUIPO tanusito vedjegy szabalyzat (vazlat) <a name="regulations"></a>

Ez a szekció az EU tanusito vedjegy bejelenteshez szukseges **Hasznalati Szabalyzat** (Regulations of Use) vazlatát tartalmazza az EUIPO 2017/1001 rendelet 83. cikkelye szerint.

---

### 1. cikkely -- A vedjegy es tulajdonosa

**A vedjegy:** CFPU Certified (szovedjegy) + logo (abravédjegy)

**Tulajdonos:** CFPU Foundation [jogalany meghatározandó: magyar egyesulet, EU nonprofit, vagy Svajci Stiftung]

**Nice osztalyok:** 9 (szamitogep-hardver, processzorok, felvezetok, szoftver), 42 (muszaki tervezes, K+F szolgaltatasok)

### 2. cikkely -- Mit tanusit a vedjegy

A CFPU Certified vedjegy azt tanusitja, hogy a jelolt aru vagy szolgaltatas **megfelel** a CFPU-SEC-v1 specifikacioban (jelen dokumentum) leirt **kotelezot biztonsagi elemeknek**, az ott meghatarazott szintek (Basic, Full, Redundant) egyiken.

### 3. cikkely -- Ki hasznalhatja

A vedjegy hasznalata **barkinek elerheto**, aki:
1. Benyujtja a termeleket konformancia-tesztre
2. A teszt eredmenye **PASS** a kert szinten
3. Fizeti az eves regisztracios dijat (a CFPU Foundation nyilvanosan koezli a dijszabast)
4. Betartja a hasznalati felteteleket (4. cikkely)

A Foundation **nem tagadhatja meg** a vedjegy hasznalatat olyan feltetellel, amely nem kapcsolodik a tanusitott property-khoz. A tanusitas nem diszkriminativ -- foldrajzi, tulajdonosi, vagy uzleti modell-alapon nem korlatozhato.

### 4. cikkely -- Hasznalati feltetelek

A vedjegy hasznalatakor a licensz-tulajdonos koteles:
1. A **szintet** jol lathatoan feltuintetni (pl. "CFPU Certified Full")
2. A tanusitvany **egyedi azonositojat** (CFPU-YYYY-NNNN) feltuntetni a termek-dokumentacioban
3. A **cfpu.org/registry** URL-t elérhetove tenni a felhasznaloknak
4. A termeleket **nem modositani** a tanusitas ota oly modon, ami erinti a tanusitott property-ket, uj tanusitas nelkul
5. A Foundation loghasznalati utmutatojat betartani (meretezes, szin, kontextus)

### 5. cikkely -- Tesztelesi eljaras

1. A kerelmezo bekuldi a chip/modul-t (fizikai minta vagy RTL + szimulaciot futtatasi lehetoseg)
2. A Foundation (vagy az altala akkreditalt labor) futtatja a CFPU-SEC-v1 konformancia-tesztsuite-ot
3. Az eredmeny PASS/FAIL. FAIL eseten a Foundation reszletes jelentest kuld a bukott tesztekrol.
4. PASS eseten a Foundation **30 napon belul** kiallitja a tanusitvanyt es felveszi a regiszterbe.
5. A kerelmezo **30 napon belul** fellebbezhet FAIL dontés ellen.

### 6. cikkely -- Dijszabas

A Foundation nyilvanosan koezli a dijszabast. A dijak fedezik:
- Konformancia-tesztelesi koltseg
- Tanusitvany kiallitas es regisztralas
- Eves megujitasi dij (a regiszter fenntartasahoz)

A dijak **nem lehetnek diszriminativak** -- azonos szintu tesztelesert azonos dijat kell kerni.

### 7. cikkely -- Visszavonas

A Foundation visszavonhatja a vedjegyhasznalati jogot ha:
1. A tanusitott termek **nem felel meg** a specifikacionak (utolagos audit alapjan)
2. A licensz-tulajdonos **megteveszto modon** hasznalja a vedjegyet
3. A licensz-tulajdonos **nem fizeti** az eves dijat 90 napon tul
4. A licensz-tulajdonos **modositotta** a termeleket tanusitas nelkul

A visszavonas **irásban** tortenni, 30 napos fellebbezesi idovel.

### 8. cikkely -- Ellenorzes

A Foundation jogosult:
- **Eves random audit**-ot vegezni a tanusitott termekek egy mintan
- **Panaszalapú vizsgalat**-ot inditani harmadik fel jelzesere
- Az audit koltsege a Foundation-t terheli (kivéve megtevesztes bizonyitasa eseten)

### 9. cikkely -- Modositas

A jelen Szabalyzatot a Foundation Steering Committee modosithatja. A modositasok **6 honapos atmeneti idovel** lepnek hatalyba. A meglevo licensz-tulajdonosokat a Foundation **kozvetlenul ertesiti**.

---

## Eletciklus es verziozas <a name="eletciklus"></a>

### A CFPU-SEC specifikacio verziozasa

| Mező | Jelentés |
|------|---------|
| **Major verzio** (v1, v2, ...) | Uj kotelezo elem felvetele vagy letezo elem torlese -> uj tanusitas szukseges |
| **Minor verzio** (v1.1, v1.2, ...) | Pontositas, teszt hozzaadas, szoveges javitas -> meglevo tanusitvanyal kompatibilis |

### Visszafele kompatibilitas

- Egy **CFPU-SEC-v1-Full** tanusitvany **ervenyes** a v1 teljes elettartama alatt
- Ha v2 megjelenik, a v1 tanusitvanyal **automatikusan 2 evvel meghosszabbodik** (sunset period)
- A Foundation **nem vonhat vissza** tanusitvanyt pusztan azert, mert uj verzio jelent meg

### Kapcsolodas a chip-generaciokhoz

| Chip-generacio | Elerheto szint |
|----------------|---------------|
| F3 Tiny Tapeout | Basic |
| F5 RTL prototipus | Basic vagy Full (QRAM jelenletetol fugg) |
| F6 ChipIgnite | Full vagy Redundant |
| F7+ production | Redundant (ajanlott safety-critical alkalmazasokhoz) |

## Changelog <a name="changelog"></a>

| Verzio | Datum | Osszefoglalo |
|--------|-------|-------------|
| 1.0 | 2026-04-17 | Kezdeti kiadas. 12 kotelezo biztonsagi elem (S1--S12), harom tanusitasi szint (Basic/Full/Redundant), konformancia-tesztsuite vazlat (27 teszt), elektronikus tanusitvany (W3C Verifiable Credential), publikus regiszter, EUIPO Regulations of Use vazlat. |
