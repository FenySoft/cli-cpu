# AuthCode + CodeLock — Hitelesített kódbetöltés és W⊕X hardveres kényszerítés

> English version: [authcode-en.md](authcode-en.md)

> Version: 1.0

Ez a dokumentum a **CFPU kódbetöltési biztonsági modelljét** írja le: hogyan garantálja a hardver, hogy **csak hiteles kód** kerülhet végrehajtásra, és hogy **adat soha nem lehet kód**. A mechanizmus két komplementer komponensből áll: **AuthCode** (aláírás-ellenőrzés kódbetöltéskor) és **CodeLock** (runtime W⊕X szeparáció). A kettő együtt a trust-lánc alapja — az eFuse-ba égetett root hash-től a fejlesztő kezében lévő Symphact HSM Card-ig.

> **Vízió-szintű dokumentum.** A teljes modell az F5 RTL-ben kap először körvonalakat, és F6-ban lesz szilícium szinten jelen. A BitIce integrálás és a Symphact HSM Card a szoftver- és hardver-dizájn kombinált kérdése; a konkrét paraméterek (AID, form factor, HSS mélység, PIN policy) a megfelelő F-fázisokhoz kötött nyitott kérdések.

## Tartalom

1. [Motiváció](#motivacio)
2. [Az alapelv: Trust by Construction](#alapelv)
3. [Architektúra áttekintés](#architektura)
4. [AuthCode — aláírás-ellenőrzés kódbetöltéskor](#authcode)
5. [CodeLock — W⊕X hardveres szeparáció](#codelock)
6. [BitIce tanúsítvány-integráció](#bitice)
7. [A trust-lánc](#trustchain)
8. [Symphact HSM Card](#neuroncard)
9. [A `.acode` konténerformátum](#acode)
10. [Fejlesztői workflow](#workflow)
11. [Operational minták](#operational)
12. [Revocation stratégia](#revocation)
13. [Hardware-szükséglet és teljesítmény](#hardware)
14. [Biztonsági garanciák](#biztonsag)
15. [Szinergia a Quench-RAM-mal és a Symphact-sel](#szinergia)
16. [Nyitott kérdések](#nyitott)
17. [F-fázis bevezetés](#fazisok)
18. [Referenciák](#referenciak)
19. [Changelog](#changelog)

## Motiváció <a name="motivacio"></a>

A modern operációs rendszerek biztonsági modelljében a **kódbetöltés és a kódfuttatás gyenge pont**:

- **Linux / Windows:** tetszőleges futtatható állományt betölthet bármely felhasználó, ha van `execute` jogosultsága. A kódforrás ellenőrzése opcionális (code signing), és sokszor szoftveresen megkerülhető.
- **iOS / Android:** code signing kötelező, de szoftveresen kikényszerítve (kernel-szintű ellenőrzés). A rendszert jailbreakelni lehet, a signing bypass rendszeres CVE-forrás.
- **JIT-alapú környezetek** (JVM, V8, .NET): új kód folyamatosan generálódik futás közben, ami **alapjaiban ellentmond** a strict code signing-nak. Minden JIT spray exploit pont erre épül.

A CFPU **architekturálisan más** alapállásból indul:

> **Egyetlen szoftver sem fut a chipen, ameddig a hardver nem bizonyosodott meg róla, hogy hitelesített publisher-től származik, és a bytecode bitre pontosan azonos azzal, amit aláírtak.**

Ezt két mechanizmus együtt biztosítja: **AuthCode** a betöltéskor (egyszeri ellenőrzés), **CodeLock** a futás alatt (folyamatos hardveres szeparáció).

A modell radikálisan egyszerűsíti a futásidejű biztonsági ellenőrzéseket. Ha minden futó aktor **konstrukció szerint** megbízható kódból származik, nem kell minden üzenetet kriptografikusan azonosítani — a capability-alapú izoláció elegendő.

## Az alapelv: Trust by Construction <a name="alapelv"></a>

A biztonsági modell egyetlen mondatban:

> **A trust egyszer dől el (kódbetöltéskor), nem másodpercenként százmilliószor (üzenetküldéskor).**

Ez az elv **fundamentálisan különbözik** a hagyományos per-message authentikációs modellektől (Kerberos, TLS, stb.), és az **iOS App Store / Android Play** code signing megközelítéséhez hasonlít — de **hardveresen kikényszerítve**, nem szoftveres ellenőrzéssel.

A három építőkő:

1. **Egyetlen kapu a kód-betöltésnél** — minden belépő bytecode-ot a hardver ellenőriz, aláírva hash-alapú PQC cert-chain ellen
2. **Immutable kód-régió** — a betöltött kód Quench-RAM SEAL-elt, futás közben nem módosítható
3. **Adat soha nem futtatható** — a PC (program counter) fizikailag nem mutathat DATA régióba

A három együtt: a chipen **csak és kizárólag** olyan CIL bytecode futhat, amit egy ismert publisher aláírt, és a bytecode bitre pontosan azonos a aláírtjával.

## Architektúra áttekintés <a name="architektura"></a>

```
┌─────────────────────────────────────────────────────────────────┐
│ KÜLSŐ VILÁG                                                     │
│                                                                 │
│  Fejlesztő          Symphact HSM Card           CIL bytecode       │
│     │                     │                       │             │
│     └──── sign(hash) ─────┘                       │             │
│                     │                             │             │
│                     ▼                             │             │
│            BitIce cert + bytecode ────────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                     │
                     │  .acode konténer
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ CFPU CHIP                                                       │
│                                                                 │
│  [hot_code_loader aktor]                                        │
│         │                                                       │
│         ▼                                                       │
│  ┌─ AuthCode verify (BitIce trust chain) ───────────────────┐   │
│  │  1. SHA-256(bytecode) == cert.PkHash ?                   │   │
│  │  2. BitIce.Verify(cert, eFuse.CaRootHash) ?              │   │
│  │  3. cert.SubjectId ∉ revocation_list ?                   │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │ (mind OK)                                             │
│         ▼                                                       │
│  [CODE régió — Quench-RAM SEAL]                                 │
│         │                                                       │
│  ┌─ CodeLock hardveres kényszerítés ─────────────────────────┐  │
│  │  - PC range check minden fetch-nél                        │  │
│  │  - Write-to-CODE tilos (csak hot_code_loader)             │  │
│  │  - Execute-from-DATA trap                                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│         │                                                       │
│         ▼                                                       │
│  [scheduler → aktor futtatás]                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

A bal oldali oszlop **szoftveres** (fejlesztő + kártya + CIL), a jobb oldali **hardveres** (chip-belső kényszerítés). A két oldal között a `.acode` konténer megy át.

## AuthCode — aláírás-ellenőrzés kódbetöltéskor <a name="authcode"></a>

Az AuthCode a **hot_code_loader kernel-aktor** kriptografikus ellenőrzési folyamata. Minden új CIL bytecode ezen megy át, mielőtt a Quench-RAM CODE régióba kerülhetne.

### Az ellenőrzési folyamat lépésről lépésre

```
hot_code_loader.LoadActor(acodeContainer):
  // Konténer felbontása
  bytecode ← acodeContainer.cilBytecode
  cert     ← acodeContainer.bitIceCertificate

  // 1. Kód-hash ellenőrzés: a cert valóban EZT a kódot jogosítja?
  binary_hash ← SHA-256(bytecode)
  if binary_hash ≠ cert.PkHash then
      trap(CODE_HASH_MISMATCH)
      return

  // 2. BitIce cert-chain verify: a cert az eFuse root-tól származik?
  if not BitIceCertificateV1.Verify(cert, eFuse.CaRootHash) then
      trap(INVALID_SIGNATURE)
      return

  // 3. Revocation check: a cert nincs visszavonva?
  if cert.SubjectId ∈ revocation_list then
      trap(CERT_REVOKED)
      return

  // 4. Allokáció és írás
  code_region ← Quench-RAM.alloc_code_region(bytecode.length)
  Quench-RAM.write(code_region, bytecode)

  // 5. SEAL — a kód innentől immutable
  Quench-RAM.seal(code_region)

  // 6. Registry-bejegyzés
  LoadedCodeRegistry.insert(
      actor_id: newActorId,
      code_hash: binary_hash,
      issuer: cert.IssuerId,
      subject: cert.SubjectId,
      code_region: code_region
  )

  // 7. Scheduler engedélyezi az aktor indítását
  scheduler.allow_spawn(newActorId, code_region)
```

Bármelyik lépés bukása → `trap` és az aktor **sosem indul el**. Nincs runtime támadási felület, mert a rossz kód soha nem kerül a chipre.

### Miért `cert.PkHash == SHA-256(bytecode)`

A BitIce cert-formátum (lásd [BitIce integráció](#bitice)) a `PkHash` mezőben **az aláírt kártya publikus kulcsának hash-ét** tárolja. A CFPU-ra adaptálva ezt **a CIL bytecode SHA-256 hash-ének** használjuk. Ezzel a cert **kriptografikusan kötődik ahhoz a konkrét bytecode-hoz**, amit jogosít — nem lehet ugyanazt a cert-et más bytecode-hoz használni, mert akkor az 1. ellenőrzés bukna.

## CodeLock — W⊕X hardveres szeparáció <a name="codelock"></a>

A CodeLock a runtime mechanizmus, amely **fizikailag lehetetlenné teszi**, hogy:
- adat végrehajtódjon (execute-from-DATA),
- a kód módosuljon (write-to-CODE),
- a program counter érvénytelen címre mutasson.

### Hardveres ellenőrzések

| Ellenőrzés | Hol történik | Trap |
|-----------|--------------|------|
| PC range check | minden instruction fetch előtt | `INVALID_PC` |
| Write-to-CODE region | minden memory store | `WRITE_TO_CODE_DENIED` |
| Execute-from-DATA | minden fetch DATA címről | `EXECUTE_FROM_DATA` |
| CODE blokk status check | minden fetch a Quench-RAM státuszt ellenőrzi | `CODE_NOT_SEALED` |

Az architektúra eleve **Harvard-jellegű** (a `docs/architecture-hu.md` 105. sora szerint a CODE és DATA külön címtartományban van), de a CodeLock ezt **hardveresen kényszeríti** — nem opcionális konfiguráció, hanem a dekóder része.

### Mi az, amit explicit kizár

- **JIT compilation:** nincs. Ha egy CIL kód megpróbál új bytecode-ot írni egy új memóriaterületre és oda ugrani, az `WRITE_TO_CODE_DENIED` trap-pel áll le. A CFPU-n **nem lehet JIT-et futtatni** — ami security-szempontból előny (nincs JIT spraying), és a .NET natív CIL-futtatás ezt amúgy is feleslegessé teszi.
- **Shellcode injection:** egy buffer overflow sem tud új kódot "odaejteni" a DATA-ba, mert a DATA-ból nincs execute.
- **Self-modifying code:** a Quench-RAM SEAL garantálja, hogy a betöltött kód bitre változatlan marad, amíg a CODE régió fel nem szabadul (ami szintén csak GC-folyamatból történhet).
- **Return-to-data gadgets:** a PC range check minden fetchnél triggerelődik; a stack-tól, heap-től, bármely DATA címtől a PC visszaugrása trap-el.

### Miért a Quench-RAM ezt "ingyen adja"

A `docs/quench-ram-hu.md`-ban leírt Quench-RAM cella **ugyanazt a status-bit mechanizmust** használja a CODE régióban, mint bárhol máshol:
- A `hot_code_loader` írja a bytecode-ot (status=0, mutable)
- Az írás után `SEAL` triggerelődik (status=1, immutable)
- Futás közben minden fetch ellenőrzi a status-t
- GC vagy unload hívja a `RELEASE`-t (status→0, data→0, a régió újra alloc-olható)

A CodeLock nem külön hardveres modul — **a Quench-RAM szemantikájának egy célzott alkalmazása** a CODE régióra.

## BitIce tanúsítvány-integráció <a name="bitice"></a>

A CFPU **a BitIce library** (`github.com/BitIce.io/BitIce`) kriptografikus alapjait használja az aláírás-ellenőrzéshez. A BitIce egy hash-alapú post-quantum PKI-keretrendszer:

- **WOTS+** (Winternitz One-Time Signature Plus) — a tényleges aláírási primitiv
- **LMS Merkle tree** — stateful tree-based aláírási struktúra
- **SHA-256** — az egyetlen hash-funkció
- **HSS** — Hierarchical Signature Scheme a nagyobb aláírásszámhoz
- **BitIceCertificateV1** — kompakt (71 byte) és teljes (2535 byte) tanúsítvány-formátum

### A `BitIceCertificateV1` mezői a CFPU kontextusban

```
BitIceCertificateV1 (compact 71 byte):
  Version       (1)   : 0x01
  Type          (1)   : 0x01 (Card / aktor bináris)
  H             (1)   : Merkle fa magasság (5-15, default 10)
  SubjectId    (16)   : az aláírt entitás ID-je (itt: a kód / aktor azonosítója)
  IssuerId     (16)   : a kibocsátó delegate ID-je (Symphact Vendor)
  PkHash       (32)   : SHA-256(CIL bytecode)   ◄── ez köti a cert-et a kódhoz
  SignatureIndex(4)   : LMS leaf index (anti-replay)

BitIceCertificateV1 (full 2535 byte):
  [compact 71 byte]
  AuthPath   (320 byte)  : Merkle path (h=10 × 32 byte)
  WotsSig   (2144 byte)  : WOTS+ aláírás (67 × 32 byte)
```

### A `Verify` eljárás (a BitIce kódbázisából)

```csharp
public bool Verify(ReadOnlySpan<byte> caRoot)
{
    // 1. TBS hash
    byte[] tbsHash = SHA256.HashData(tbs);
    // 2. WOTS+ pk rekonstrukció
    byte[] computedPk = WotsPlus.ComputePublicKeyFromSignature(wotsSignature, tbsHash);
    // 3. Leaf hash
    byte[] leafHash = SHA256.HashData(computedPk);
    // 4. Merkle root újraszámítás
    byte[] computedRoot = LmsMerkleTree.ComputeRoot(leafHash, sigIndex, authPath, TreeHeight);
    // 5. Összehasonlítás a CA root-tal
    return computedRoot.SequenceEqual(caRoot);
}
```

Ez **öt SHA-256-alapú lépés**. A CFPU hardveres SHA-256 egységgel ezt közvetlenül végrehajtja — nincs szükség ECC-re, RSA-ra vagy más aszimmetrikus primitívre.

### Miért hash-alapú, miért nem ECDSA / Ed25519

| Aspektus | ECDSA / Ed25519 | WOTS+ / LMS (BitIce) |
|----------|-----------------|-----------------------|
| Quantum-resistance | ❌ (Shor algoritmus töri) | ✅ (hash-alapú, Grover csak 2× erősítés) |
| Hardveres primitiv-szám | elliptikus görbe matek + hash | **csak SHA-256** |
| NIST-standardizált | FIPS 186 | FIPS 205 (SLH-DSA) + NIST SP 800-208 (LMS/HSS) |
| Stateful? | Nem | **Igen** — single-use leaf enforcement kell |
| Hardveres állapot-kezelés | Nem szükséges | **Kötelező** (NIST SP 800-208 SHALL) |

A hash-alapú séma stateful-sága **pozitív tulajdonság** a CFPU kontextusban, mert a Symphact HSM Card fizikailag biztosítja a single-use kényszerítést (lásd [Symphact HSM Card](#neuroncard)).

## A trust-lánc <a name="trustchain"></a>

A teljes hitelességi lánc a gyártáskor beégetett hardveres root-tól a fejlesztő kezében lévő kártyáig:

```
[Chip eFuse: 32 byte CA Root Hash]                    ← gyártáskor immutable
        │ root-of-trust (hardveres)
        ▼
[BitIce CFPU Foundation Root CA]                      ← HSM-ben tartott
        │ signs WOTS+ (HSS level 1)
        ▼
[Symphact Vendor Delegate Cert]                      ← vendor (pl. FenySoft)
        │ signs WOTS+ (HSS level 2)
        ▼
[Symphact HSM Card]                                      ◄── FEJLESZTŐI KÁRTYA
   └─ Symphact HSM Applet                         ← fizikai SE, single-use leaf
        │ signs WOTS+ (leaf in XMSS tree, h=10)
        ▼
[CIL Binary Cert]                                     ← konkrét bytecode aláírás
        │ verifies on
        ▼
[CFPU AuthCode loader]                                ← chip-belső verify + load
```

### A lánc minden eleme hardveresen védett

| Elem | Hol él | Védelem |
|------|--------|---------|
| CA Root Hash | eFuse on chip | gyártáskor beégetett, soha nem módosítható |
| Foundation Root CA | dedicated HSM | FIPS 140-3 Level 3+ tamper-resistant |
| Vendor Delegate Cert | vendor HSM | ugyanaz |
| Symphact HSM Card | fejlesztő kezében | tamper-resistant smart card, single-use NVRAM counter |
| `.acode` file | fejlesztő gépén | nem kell védeni — a signature önhitelesítő |

**Nincs olyan pont a láncban, ahol szoftver egyedül dönthet.** A trust mindenhol fizikai eszközben él.

## Symphact HSM Card <a name="neuroncard"></a>

A Symphact HSM Card egy dedikált, dedikált, single-purpose HSM smart card, amely **JavaCard runtime-on** egy különálló **Symphact HSM Applet**-et futtat. Ez a kártya **kötelező** minden fejlesztő számára, aki CFPU-ra aktort telepít.

### Miért kötelező a hardveres aláíró

A WOTS+ aláírási primitiv **egyetlen kritikus tulajdonsága**: egy leaf-kulcs **csak egyszer** használható. Kétszeri használat esetén a támadó **interpolációval tetszőleges aláírást tud gyártani** — a biztonság teljesen összeomlik.

Szoftveres signer **soha nem** tudja ezt megbízhatóan garantálni:
- VM snapshot → state rollback → ugyanaz a leaf kétszer
- Backup restore → state rollback
- Race condition két párhuzamos signing művelet között
- Memory dump → privát kulcs lopás

A **NIST SP 800-208** (a LMS/HSS szabvány) ezért **explicit megtiltja** a szoftveres state-tracking-et:

> *"State management for stateful hash-based signature schemes SHALL be performed by the cryptographic module that contains the private key, and SHALL NOT rely on external software or operating system support."*

A Symphact HSM Card tamper-resistant smart card hardvere biztosítja:

| Garancia | Mechanizmus |
|----------|-------------|
| Single-use leaf index | NVRAM counter, atomic write-before-sign |
| State nem klónozható | Privát kulcs sosem hagyja el a kártyát |
| State nem rollback-elhető | Tamper detection + secure element zóna |
| Backup nem hozható létre | Privát kulcs export disabled |
| Side-channel ellenálló | Constant-time WOTS+ implementáció |

### Miért külön kártya és külön applet

A JavaCard 3.x+ runtime **firewall mechanizmust** ad az appletek között — egy applet nem fér hozzá egy másik applet adataihoz. Egy különálló **Symphact Applet** a BitIce ökoszisztémában:

| Előny | Mit jelent |
|-------|-----------|
| Domain isolation | Bug egy identity / payment applet-ben nem szivárogtat Symphact állapotot |
| Független leaf-counter | A Symphact HSS-tér csak CIL-aláírásra fogy |
| Független cert-chain | Másik vendor delegate lehet, mint a hétköznapi BitIce-használathoz |
| Független PIN / policy | Más szigorúságú PIN / biometria a kódaláíráshoz |
| Független audit-log | "Ki és mikor írt alá CIL-t" — tiszta forensic nyom |
| Független élettartam | A kártya cserélhető a Symphact oldalon anélkül, hogy más BitIce funkciók érintettek |

A **külön kártya** (nem multi-applet) tovább erősít:
- Fizikai elválasztás — a fejlesztő nem keveri a banki / identity kártyájával
- Reduced attack surface — egyetlen applet = kisebb JavaCard runtime támadási felület
- Egyszerűbb audit — "CFPU code-signing card" egyértelműen azonosítható

### Az applet APDU-interfésze (vázlat)

```
SELECT_APPLET   <Symphact Applet AID>      → authenticate
SIGN_CIL_HASH   <SHA-256 hash>              → BitIceCertificateV1 (compact 71 byte)
GET_FULL_CERT                                → BitIceCertificateV1 (full 2535 byte)
GET_CERT_CHAIN                               → chain up to root
GET_REMAINING                                → még felhasználható leaf-ek száma
ROTATE_KEY                                   → új sub-tree (HSS deeper level)
```

A konkrét APDU byte-layout, AID, PIN-policy és form factor **F-fázis-függő nyitott kérdés** (lásd [Nyitott kérdések](#nyitott)).

## A `.acode` konténerformátum <a name="acode"></a>

A fejlesztő a `cli-cpu-link` tool-lal **`.acode`** fájlt készít, ami a CIL bytecode-ot és a BitIce cert-et egy konténerben tartja:

```
.acode file layout (vázlat):
  ┌────────────────────────────────────────────┐
  │ Magic:  "ACODE"                  5 byte    │
  │ Version:                         1 byte    │
  │ Flags:                           2 byte    │
  │ BitIce cert length:              4 byte    │
  │ CIL bytecode length:             8 byte    │
  │ BitIce certificate:     variable (2535)    │
  │ CIL bytecode:           variable           │
  │ CRC32 over all:                  4 byte    │
  └────────────────────────────────────────────┘
```

A konkrét formátum **implementációs kérdés**, amit a `cli-cpu-link` tool bevezetésekor véglegesítünk. A lényeg: **önmagában teljes** (standalone) — a `hot_code_loader` mindent megtalál benne, amire szüksége van az ellenőrzéshez.

## Fejlesztői workflow <a name="workflow"></a>

```
1. C# kód írása                            (fejlesztő)
2. dotnet build → CIL bytecode              (Roslyn)
3. cli-cpu-link:
     hash ← SHA-256(bytecode)
4. Symphact HSM Card csatlakoztatva:
     SELECT_APPLET <Symphact Applet AID>
     PIN / biometria prompt
5. cli-cpu-link → card:
     SIGN_CIL_HASH(hash)
       → card NVRAM: leaf_index++ (atomic commit BEFORE return)
       → card: WOTS+ sign TBS (TBS tartalmazza a hash-t PkHash mezőben)
       → return: BitIceCertificateV1 (full 2535 byte)
6. cli-cpu-link package:
     bytecode + cert → program.acode
7. Deploy:
     hot_code_loader fogadja a .acode-ot
     AuthCode flow fut (lásd fent)
     ha sikeres: Quench-RAM SEAL → scheduler indíthatja
```

A **4-5. lépés az egyetlen**, amihez fizikai kártya kell. Egy h=10 XMSS fa 1024 aláírásra elég; napi 1-3 build esetén ez **1-3 évig** fedezi a fejlesztő munkáját, utána kulcs-rotáció (ROTATE_KEY) vagy új kártya.

## Operational minták <a name="operational"></a>

### CI/CD integráció

Modern dev-workflow-ban a CI/CD pipeline automatikusan aláír build-eket. Ez **fizikai kártyát igényel**, amely a build szerverhez csatlakozik. Három lehetséges minta:

| Minta | Mit jelent | Kompromisszum |
|-------|-----------|---------------|
| **Dedicated CI/CD card** | Zárt szerverszobában lévő card server → build szerver hálózaton éri el | Szabványos, skálázódik, audit-barát |
| **Developer-signs-only** | Minden fejlesztő lokálisan ír alá, CI csak verify | Manuális, lassít, de minimális támadási felület |
| **Tiered**: dev / prod | Dev branchen software signer (emulátor), prod-on hardware card | Hibrid, de "software signer" a CFPU-n NEM futtatható, csak szimulátoron |

A **dedicated CI/CD card** a legelterjedtebb minta — analóg az AWS CloudHSM, Azure Key Vault HSM-módjával. A BitIce-nek ehhez **server form factor**-t kell támogatnia (PCIe vagy network appliance, JavaCard runtime-mal) — ez BitIce roadmap-kérdés.

### Emergency hotfix

3 órai kritikus bug esetén:
- Az on-call mérnök **fizikailag jelen van** a kártyájához
- Vagy: "emergency response" kártya páncélszekrényben, m-of-n hozzáférés (pl. két mérnök PIN-je kell)
- Minden aláírás auditálva → forensic review utólag

Ez **megegyezik** a hagyományos TLS cert HSM-management gyakorlattal.

### Nyílt forráskódú kontribúciós modell

Egy GitHub kontribútor nem tud a CFPU-ra telepíthető kódot aláírni (nincs delegate cert-je). Két elfogadott minta:

| Modell | Működés |
|--------|---------|
| **Maintainer-resigning** | A projekt maintainer-je felülvizsgálja a PR-t, és a saját kártyájával újra-aláírja a merged bytecode-ot |
| **Per-project sub-CA** | A projekt vendor-delegate-je kibocsát "contributor cards"-ot az aktív kontribútoroknak |

A **maintainer-resigning** a biztonságosabb default — emlékeztet a Debian package-signing modellre.

## Revocation stratégia <a name="revocation"></a>

Ha egy Symphact HSM Card elvész, ellopódik, vagy a privát kulcsa valamilyen módon kompromittálódik, a hozzá tartozó cert-eket **vissza kell vonni**.

### Lehetséges mechanizmusok (F-fázis-függő döntés)

| Mód | Hogy működik | Komplexitás |
|-----|--------------|-------------|
| **Local revocation list** | A chip Quench-RAM-ban tart egy revoked-list-et, amit signed updates frissítenek | Egyszerű, lokális, de chip memória-igényes |
| **Cert validity period** | Minden cert rövid lejáratú, periódikus re-issuance | Heavy infrastruktúra, de nincs revocation-list |
| **OCSP-szerű query** | Minden code load online ellenőrzi a cert-et | Internet-dependens, offline rendszerekben nem megy |
| **Hybrid** | Lokális revocation-list + opcionális online check | Rugalmas, de több kód |

A pontos döntés **F5-F6 kérdés**. A v1.0 modell most azt rögzíti, hogy a **lokális revocation list** a baseline, és szükség szerint bővíthető.

## Hardware-szükséglet és teljesítmény <a name="hardware"></a>

### Fix hardveres overhead

| Komponens | Méret | Megjegyzés |
|-----------|-------|------------|
| SHA-256 unit | ~5K gate | egyszer már kell a Quench-RAM payload_hash-hez is |
| WOTS+ verifier state machine | ~3K gate | csak SHA-256 láncolás |
| Merkle path verifier | ~2K gate | h=10 lépéses iteráció |
| eFuse (CA Root Hash) | 256 bit + ECC | gyártáskor |
| PC range comparator | ~32 gate per core | CodeLock része |
| Write-to-CODE enforcement | ~Quench-RAM meglévő | nincs új |

**Összes új hardver:** ~10K gate + eFuse. **2 nagyságrenddel kisebb**, mint pl. egy per-message auth rendszer lett volna.

### Memória-szükséglet

| Cél | Méret | Frequency |
|-----|-------|-----------|
| Loaded Code Registry | ~256 byte/aktor | permanent while alive |
| Revocation list (opcionális) | ~16 byte/entry × max 1024 | ~16 KB ha használt |
| Temporarily: .acode buffer load közben | bytecode size + 2535 byte cert | transient |

### Verifikációs idő

Egy tipikus cert-verify (h=10 XMSS):

| Lépés | SHA-256 ops | Ciklus (1 GHz, HW) |
|-------|-------------|---------------------|
| TBS hash | 1 | ~80 |
| WOTS+ recompute (67 × ~7.5 átlag) | ~500 | ~40K |
| Leaf hash | 1 | ~80 |
| Merkle path (h=10) | 10 | ~800 |
| **Összesen** | **~512** | **~41K ciklus ≈ 41 µs** |

Egy 100 KB CIL bytecode load ~100 µs (SHA-256 compute) + 41 µs (verify) + 10 µs (seal) = **~150 µs**. **Egyszeri**, aktor-indításkor. Futás közben **nulla overhead**.

## Biztonsági garanciák <a name="biztonsag"></a>

Az AuthCode + CodeLock + Symphact HSM Card együtt **nyolc** klasszikus támadási osztályt zár ki hardveresen:

| Támadás-osztály | CWE | Hagyományos CPU | CFPU (AuthCode+CodeLock) |
|----------------|-----|-----------------|---------------------------|
| Shellcode injection | CWE-94 | Sebezhető | **Kizárva** (CodeLock: W⊕X) |
| JIT spraying | — | Minden JIT környezetben | **Kizárva** (nincs JIT) |
| Code reuse / gadgets | — | ROP/JOP lehetséges | **Kizárva** (CodeLock + Quench-RAM SEAL) |
| Unsigned code execution | CWE-345 | OS-függő, bypass-olható | **Kizárva** (AuthCode kötelező) |
| Tampered binary | CWE-345 | Szoftveres check, kerülhető | **Kizárva** (SHA-256 hash-PkHash binding) |
| Supply chain at code level | — | Ellenőrizhetetlen | **Ellenőrizhető** (BitIce trust chain) |
| Stateful sig key reuse | — | Ha szoftveres signer, könnyű | **Kizárva** (Symphact HSM Card single-use NVRAM) |
| Quantum break of signature | — | Shor töri ECDSA/Ed25519-et | **Kizárva** (WOTS+/LMS hash-alapú PQC) |

## Szinergia a Quench-RAM-mal és a Symphact-sel <a name="szinergia"></a>

### Quench-RAM

A CodeLock **nem új hardver** — a `docs/quench-ram-hu.md`-ban leírt Quench-RAM cella célzott alkalmazása a CODE régióra:

- A `hot_code_loader` írja a bytecode-ot status=0 Quench-RAM blokkokba
- Az írás után a loader triggereli a SEAL-t
- Futás közben a hardver a status-bit alapján engedélyezi a fetch-et
- Unload-kor a GC vagy a loader triggereli a RELEASE-t → a régió újraalloc-olható

A Quench-RAM per-blokk status-bit mechanizmusa **pontosan azt** garantálja, amit a CodeLock megkíván: a CODE régióba csak egyszer lehet írni (egy load-ciklusban), és a betöltött kód immutable a lifetime-ja alatt.

### Symphact hot code loader

A [`Symphact/vision-hu.md#kernel-aktorok-root-level`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-hu.md#kernel-aktorok-root-level) szakasza leír egy `hot_code_loader` aktort, ami új CIL kódot fogad. Az AuthCode **ennek a aktornak a biztonsági moduljává** válik:

```
hot_code_loader (Symphact kernel aktor):
  - fogadja a .acode konténert üzenetként
  - AuthCode flow (verify + load + seal)
  - ha siker: report_success(new_actor_id) → parent supervisor
  - ha bukás: report_failure(reason) → security_log aktor
```

A `hot_code_loader` maga is **aláírt aktor** — a root supervisor része, vendor-delegálva vagy direkt root CA által aláírva. Ez a recursive trust alapja.

### Per-actor capability model

Az AuthCode csak a **kódbetöltést** ellenőrzi — a futó aktorok egymás közötti interakcióját **továbbra is a meglévő capability-alapú rendszer** kezeli ([`Symphact/vision-hu.md#capability-alapú-biztonság`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-hu.md#capability-alapú-biztonság)). A kettő ortogonális:

- **AuthCode:** "ki futtatható a chipen egyáltalán"
- **Capability:** "mit tud egy futó aktor"

## Nyitott kérdések <a name="nyitott"></a>

A v1.0 a vízió-szintű architektúrát rögzíti. A következő részletek **későbbi F-fázisokban** pontosítandók, a hardver és a szoftver aktuális fejlettségi szintjéhez igazítva.

### F4-F5 idején (szim + RTL prototípus)

1. **CA Root Hash forrása az eFuse-ban** — egyetlen global CA root, vendor-customizált root, vagy több root slot?
2. **Revocation-list mérete és frissítési mechanizmusa** — mekkora a maximális revoked entries száma on-chip?
3. **HSS mélység a BitIce cert-chainben** — h=10 (1024), h=15 (32K), vagy mélyebb? Minden szint egy HSS szint.

### F5-F6 idején (első hardware)

4. **Symphact HSM Card AID** — regisztrált ISO/IEC AID a Symphact RID alatt (pl. `<RID>+"NEURONOS"`).
5. **Form factor** — ISO 7816 ID-1 (kártya), USB token, NFC, vagy több variáns párhuzamosan.
6. **PIN / biometric policy** — egyetlen PIN, dual-PIN (m-of-n), on-card fingerprint, vagy opt-in kombinációk.
7. **Server-side Symphact HSM** — PCIe vagy network appliance a CI/CD pipeline-okhoz.

### F6-F7 idején (production)

8. **Revocation mechanizmus végső formája** — lokális list, OCSP-szerű query, vagy hibrid.
9. **Open source kontribúciós infrastruktúra** — per-project sub-CA provisioning folyamat.
10. **Emergency response protocol** — m-of-n quorum szabályok, audit-logging követelmények.

Ezek a kérdések **nem blokkolják** az alsóbb fázisokat — a v1.0 modell konzisztens döntéseket enged az egyes dimenziókban.

## F-fázis bevezetés <a name="fazisok"></a>

| Fázis | AuthCode + CodeLock + Symphact HSM Card szerepe |
|-------|------------------------------------------------|
| F0–F2 (szimulátor) | Szoftveres emuláció a `TCpu`-ban: AuthCode verify mock, CodeLock mint runtime check; a `.acode` konténer formátuma véglegesíthető itt |
| F3 (Tiny Tapeout) | Nincs hardveres AuthCode (terület-korlát), de a CIL-T0 ISA már rögzíti a `hot_code_loader` interfészt |
| F4 (multi-core szim) | Teljes szoftveres AuthCode flow, BitIce library integrálva a szimulátorba; **szimulált Symphact HSM Card** unit tesztekhez |
| **F5 (RTL prototípus)** | Első hardveres SHA-256 + WOTS+ verifier; **valódi Symphact HSM Card** prototípus (dev kit); a Symphact HSM Applet első verziója |
| F6 (ChipIgnite tape-out) | Teljes hardveres AuthCode + CodeLock + eFuse; production Symphact HSM Card elérhető fejlesztőknek |
| F6.5 (Secure Edition) | Finomabb revocation mechanizmus, dual-cert support (pl. FIPS tanúsítási útra) |
| F7 (silicon iter 2) | Emergency response protocol, globális revocation-grid |

## Referenciák <a name="referenciak"></a>

### Belső dokumentumok

- `docs/quench-ram-hu.md` — a Quench-RAM memóriacella, amin a CodeLock mechanizmusa alapul
- `docs/security-hu.md` — a CFPU biztonsági modell, amit az AuthCode kibővít
- [`Symphact/docs/vision-hu.md`](https://github.com/FenySoft/Symphact/blob/main/docs/vision-hu.md) — a `hot_code_loader` aktor és a capability-modell
- `docs/architecture-hu.md` — a CFPU Harvard-architektúra, amire a CodeLock épül
- `docs/secure-element-hu.md` — a Secure Edition (F6.5) potenciálisan ezt a mechanizmust használja a TEE-jéhez

### Külső hivatkozások

- BitIce projekt: `github.com/BitIce.io/BitIce`
- NIST SP 800-208: Recommendation for Stateful Hash-Based Signature Schemes
- NIST FIPS 205: Stateless Hash-Based Digital Signature Standard (SLH-DSA)
- NIST FIPS 180-4: SHA-256 specification
- RFC 8554: Leighton-Micali Hash-Based Signatures (LMS)
- RFC 8391: XMSS: eXtended Merkle Signature Scheme

## Changelog <a name="changelog"></a>

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 1.0 | 2026-04-16 | Kezdeti vízió-szintű kiadás. AuthCode (load-time verify) + CodeLock (W⊕X hardveres) + BitIce WOTS+/LMS integráció + Symphact HSM Card (dedikált JavaCard applet). A részletes paraméterek (AID, form factor, HSS mélység, PIN policy, revocation, CI/CD HSM) F-fázis-függő nyitott kérdések. |
