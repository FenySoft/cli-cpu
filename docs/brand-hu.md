# Brand- és elnevezési útmutató — Cognitive Fabric, CFPU, CLI-CPU

> English version: [brand-en.md](brand-en.md)

> Version: 1.0

Ez a dokumentum a **kanonikus referencia** arra a három névre, amelyek együtt szerepelnek a projektben: **Cognitive Fabric**, **CFPU**, és **CLI-CPU**. Nem szinonimák. Mindegyik más réteget jelöl (architektúra-család, processzor-kategória, referencia-implementáció), és a rossz választás egy mondaton belül észrevétlenül torzítja a jelentést.

Ha csak egy szakaszra van időd, olvasd el a [§ 4 — Mikor melyik nevet használd](#4-mikor-melyik-nevet-használd) részt.

---

## 1. A három réteg

```
Cognitive Fabric          ← architektúra-család / vízió
  │
  └── CFPU                ← a processzor-egység kategóriája
        │   (Cognitive Fabric Processing Unit — testvér: CPU/GPU/TPU/NPU)
        │
        ├── CFPU Nano     ← integer-only worker core         (termékvonal)
        ├── CFPU Actor    ← actor-natív, eseményvezérelt core (termékvonal)
        ├── CFPU Rich     ← teljes CIL + GC + FPU + supervisor (termékvonal)
        ├── CFPU Matrix   ← MAC-slice ML gyorsító            (termékvonal)
        └── CFPU Seal     ← biztonságos boot / trust anchor  (termékvonal)
        │
        └── CLI-CPU       ← a CFPU kategória nyílt forráskódú
              │             referencia-implementációja — ez a projekt
              ├── repo:       github.com/FenySoft/CLI-CPU
              ├── szimulátor: CilCpu.Sim
              ├── linker:     CilCpu.Linker
              ├── ISA spec:   CIL-T0 (és CIL-Seal a Seal core-hoz)
              └── licenc:     CERN-OHL-S (hardware) + Apache-2.0 (software)
```

A minta ismerős az iparban:

| Vízió / család | Kategória | Referencia-implementáció |
|----------------|-----------|--------------------------|
| Unix-szerű OS  | OS kernel | **Linux** (Linus Torvalds, 1991) |
| Nyílt böngésző | Browser engine | **Chromium** (Google, 2008) |
| Nyílt WebKit   | Browser engine | **WebKit** (Apple/KDE, 2001) |
| **Cognitive Fabric** | **CFPU** | **CLI-CPU** (FenySoft, 2026) |

Ahogy a Linux *egy* megvalósítása a Unix-szerű OS gondolatnak, úgy a **CLI-CPU egy megvalósítása a CFPU kategóriának**. Más CFPU-implementációk követhetnek — a kategória nyitott.

---

## 2. Definíciók

### 2.1 Cognitive Fabric

**Definíció:** az architektúra-*család* — a magas szintű vízió és a marketing-narratíva.

A Cognitive Fabric egy chip (vagy több chip), amely **sok kis, független, CIL-natív core-ból** áll, és **shared-nothing üzenet-átadással** kommunikálnak. Nincs megosztott memória, nincs cache-koherencia protokoll, nincs lock-contention. Minden core egy teljes programot futtat saját lokális állapottal; a core-ok bejövő üzenetekre ébrednek.

Ez a *vízió* szintje. Nem köteleződik el konkrét core-szám, ISA-részhalmaz, package-formátum vagy gyártási node mellett. A „Cognitive Fabric" az, amit slide-okra, blogokba, lift-pitchbe írunk.

**Iparági testvérek:** *neuromorphic*, *dataflow*, *systolic*, *manycore* — de a Cognitive Fabric **MIMD actor-natív** (minden core *másik* programot futtat), ami megkülönbözteti mind a négytől.

### 2.2 CFPU — Cognitive Fabric Processing Unit

**Definíció:** a processzor-egység *kategóriája* — testvér a CPU, GPU, TPU, NPU mellett.

A CFPU az, hogy *milyen fajta* chip ez. **Nem** termékvédjegy és **nem** projektnév. Kategória, amelyet jövőbeli implementációk (a FenySofttól vagy másoktól) megtölthetnek tartalommal — ahogy a „GPU" lefedi az NVIDIA, AMD és Intel részeit.

| Kategória | Paradigma | Példa workload |
|-----------|-----------|----------------|
| CPU       | SISD / MIMD (megosztott memória) | általános célú |
| GPU       | SIMD (data parallel) | mátrix, shader |
| TPU       | Systolic array | neurális inferencia (fix) |
| NPU       | Fix neuron-modell | neurális inferencia (edge) |
| **CFPU**  | **MIMD (shared-nothing, actor)** | **actor rendszerek, SNN, multi-agent, IoT edge** |

A CFPU-n belül **termékvonalak** (core típusok) vannak, mindegyiknek van suffixe:

| Termékvonal | Suffix | Szerep |
|-------------|--------|--------|
| CFPU Nano   | -N     | Integer-only worker, legkisebb terület |
| CFPU Actor  | -A     | Eseményvezérelt actor core |
| CFPU Rich   | -R     | Teljes CIL GC-vel, FPU-val, supervisorral |
| CFPU Matrix | -ML    | MAC-slice ML gyorsító |
| CFPU Seal   | -H     | Hardenelt secure-boot / trust anchor |

Részletek: [docs/core-types-hu.md](core-types-hu.md).

**Miért nem „CFP":** a **CFP** rövidítés erősen lefoglalt a hardver-iparban (*C Form-factor Pluggable* — 100G/400G optikai transceiver MSA). A **CFPU** záró **\*PU** suffixe egyértelműen processzor-egység, iparági ütközés nélkül.

### 2.3 CLI-CPU

**Definíció:** a *projekt* — ez a nyílt forráskódú repository és minden, ami belőle születik.

A CLI-CPU az **első** referencia-implementációja a CFPU kategóriának. Ide tartozik:

- **GitHub repo:** [github.com/FenySoft/CLI-CPU](https://github.com/FenySoft/CLI-CPU)
- **C# szimulátor** (`CilCpu.Sim`) — cycle-accurate referencia modell
- **Linker** (`CilCpu.Linker`) — Roslyn `.dll` → CIL-T0 binári
- **CLI runner** (`CilCpu.Sim.Runner`) — `run` és `link` parancsok
- **ISA spec** (`CIL-T0`) — a bytecode, amit a szilícium végrehajt
- **RTL** (jövőben, F4–F6) — a Verilog/Chisel, amiből a chip lesz
- **NLnet pályázat** és projekt terv

Minden, ami **build artefakt**, **commit**, **teszt cél**, **roadmap mérföldkő**, vagy **licenc-deklaráció**, az a *CLI-CPU*-hoz tartozik. A név megjelenik a `git log`-ban, a `.csproj` fájlokban, az issue trackeren, a pályázati anyagban.

A CLI-CPU volt az *első* név (a „Cognitive Fabric" megalkotása előtt), ezért hordozza a repo, a GitHub szervezet, a szimulátor és az ISA. A név a projektnek állandó — de a chipek, amik kijönnek belőle, **CFPU** termékneveket viselnek.

---

## 3. Miért három név egy helyett

A három-rétegű felosztás azért létezik, mert mindegyik név olyan munkát végez, amit a többi nem tud:

- Egy **terméknek** (pl. „CFPU-R Rich core") eladhatónak, brand-elhetőnek, és GPU/TPU/NPU-val kategória-szinten összehasonlíthatónak kell lennie. A „CLI-CPU Rich" nevet adva minden termékoldal úgy nézne ki, mintha egy szoftverprojektről, nem szilíciumról szólna.
- Egy **projektnek** (pl. „a CLI-CPU szimulátor") kereshetőnek, idézhetőnek, licenc-rögzíthetőnek kell lennie, és stabil GitHub URL-lel kell rendelkeznie. Ha „a CFPU projekt"-nek hívjuk, összemossuk a nyílt forráskódú erőfeszítést jövőbeli, esetleg zárt forráskódú CFPU chipekkel.
- Egy **víziónak** (pl. „a Cognitive Fabric a Neuron OS szubsztrátuma") evokatívnak, marketing-késznek, és bármely konkrét utasításkészlettől vagy core-típustól függetlennek kell lennie. Ez kerül egy-soros pitch-deck slide-ra.

Ha a hármat egy névbe olvasztjuk, minden külső felület — tudományos cikk, termék-datasheet, pályázat, README, blog — rossz rétegbe szivárogtatja a jelentést.

---

## 4. Mikor melyik nevet használd

### 4.1 **CLI-CPU**, ha

- A **projektről**, a **repóról**, a **kódbázisról**, vagy **build artefaktumokról** beszélsz.
- A szimulátort, a linkert, a runnert, vagy az ISA-implementációt idézed.
- Roadmap fázisokra (F0–F7), teszt célokra, NLnet pályázatra, licencre hivatkozol.
- Bármi, aminek `git log` bejegyzése, `.csproj`-ja, vagy GitHub issue-ja van.

**Példák:**

> *„A CLI-CPU projekt státusza F1.5 KÉSZ."*
>
> *„Klónozás: `git clone https://github.com/FenySoft/CLI-CPU`"*
>
> *„A CLI-CPU referencia szimulátorhoz 250+ teszt tartozik."*
>
> *„A CLI-CPU CERN-OHL-S (hardver) és Apache-2.0 (szoftver) alatt licencelt."*

### 4.2 **CFPU**, ha

- A **chip-kategóriáról** vagy az **architektúra-szintű processzor-típusról** beszélsz.
- CPU / GPU / TPU / NPU-val hasonlítasz össze.
- **Termékvonalakat** nevezel (CFPU Nano, CFPU Rich, CFPU-ML Matrix, CFPU-H Seal stb.).
- **Szilícium-szintű feature-öket** (mikroarchitektúra, mailbox, NoC, secure element) tárgyalsz.
- Chip datasheetet, biztonsági modellt, threat-analízist, certifikációs dokumentumot írsz.

**Példák:**

> *„A CFPU egy új processzor-egység kategória."*
>
> *„CFPU-N Nano vs. CFPU-R Rich heterogén multi-core."*
>
> *„CFPU Security Model — támadási felület és mitigációk."*
>
> *„A CFPU mailbox shared-nothing; a koherencia nem alkalmazandó."*

### 4.3 **Cognitive Fabric**, ha

- Az **architektúra-családról**, **vízióról**, vagy **marketing-narratíváról** beszélsz.
- **Chipeket** nevezel meg (pl. *Cognitive Fabric One* — az F6 referencia-szilícium).
- Az **ötletet** pitcheled bármely konkrét implementációtól függetlenül.
- A **Neuron OS**-hez mint runtime-rétegez kapcsolod.

**Példák:**

> *„A Cognitive Fabric szubsztrátum actor-natív, eseményvezérelt workloadokhoz."*
>
> *„Cognitive Fabric One — az F6-Silicon referencia chip (6R+16N+1S, 15 mm²)."*
>
> *„Cognitive Fabric + Neuron OS a Linux-on-commodity-CPU utódja."*

---

## 5. Do / Don't tábla

| Ne ❌ | Tedd ✅ | Miért |
|------|--------|-------|
| „a CLI-CPU Security Model" (chip-szintű threat-doc-ban) | „a CFPU Security Model" | A támadási felület szilícium-szintű, nem projekt-szintű |
| „CFPU repo" / „CFPU pull request" | „CLI-CPU repo" / „CLI-CPU pull request" | A repo a projekt, nem a kategória |
| „CFPU projekt-terv" | „CLI-CPU projekt-terv" | A projekt-tervek projektekhez tartoznak |
| „CLI-CPU Nano" / „CLI-CPU Rich" | „CFPU Nano" / „CFPU Rich" | A termékvonalak a kategóriához tartoznak |
| „a Cognitive Fabric repo" | „a CLI-CPU repo" | A vízió nem repo |
| „a CLI-CPU egy új processzor-kategória" | „a CFPU egy új processzor-kategória" | A projekt nem kategória |
| „vegyél egy CLI-CPU-t" | „vegyél egy Cognitive Fabric One chipet" / „vegyél egy CFPU-R-t" | Chipet veszel, nem projektet |
| „CFPU CERN-OHL-S alatt" | „CLI-CPU CERN-OHL-S alatt" | A licenc a projekthez fűződik |

---

## 6. Határesetek és átfedések

Néhány mondat jogosan ível át két rétegen. Az ökölszabály: **a fő nevet abból a rétegből vedd, amelyhez a főnév tartozik, a másikat zárójelben említsd.**

- **Referencia-implementáció:** vezess a CFPU-val, nevezd meg a CLI-CPU-t mint implementációt.
  > *„A CFPU kategória nyitott; az első referencia-implementáció a **CLI-CPU** projekt."*

- **Egy kategória projekt-státusza:** vezess a CLI-CPU-val, nevezd meg a CFPU-t mint kategóriát.
  > *„A **CLI-CPU** projekt F1.5-nél tart; a **CFPU** szilícium (Cognitive Fabric One) F6-ra van célozva."*

- **Marketing one-liner:** vezess a Cognitive Fabric-kal, nevezd meg a CFPU-t és CLI-CPU-t mint kategóriát és referenciát.
  > *„A **Cognitive Fabric** új architektúra-család. Processzor-egység kategóriája a **CFPU**. Nyílt forráskódú referencia-implementációja a **CLI-CPU** projekt."*

---

## 7. Stílus-megjegyzések

- **Nagybetűzés:** mindhárom név nagybetűs a folyó szövegben (`Cognitive Fabric`, `CFPU`, `CLI-CPU`). Ne írj `cli-cpu` vagy `cfpu` formát body text-ben. Kód-azonosítókban (`CilCpu.Sim`, `CFPU_NANO` stb.) a nyelv konvencióját kövesd.
- **Kötőjel:** `CLI-CPU` mindig kötőjeles. `CFPU` soha (ne írd `CF-PU`-t).
- **Többes szám:** `CFPU-k` (nem aposztróffal). A `CLI-CPU-k` esetlen — inkább „CLI-CPU-példányok" vagy „CLI-CPU-implementációk".
- **Első említés egy dokumentumban:** legalább egy rövidítést írj ki teljesen első használatkor. pl. *„a **Cognitive Fabric Processing Unit (CFPU)** …"* vagy *„a **CLI-CPU** projekt (a CFPU kategória nyílt forráskódú referencia-implementációja) …"*.

---

## 8. Lásd még

- [docs/faq-hu.md § 1](faq-hu.md#1-mi-a-cfpu-és-mi-a-kapcsolata-a-cli-cpu-val) — ennek az útmutatónak a rövid változata.
- [docs/architecture-hu.md](architecture-hu.md) — CFPU mikroarchitektúra.
- [docs/core-types-hu.md](core-types-hu.md) — CFPU termékvonalak (Nano / Actor / Rich / Matrix / Seal).
- [docs/security-hu.md](security-hu.md) — CFPU biztonsági modell.
- [docs/roadmap-hu.md](roadmap-hu.md) — CLI-CPU projekt fázisok F0–F7.
