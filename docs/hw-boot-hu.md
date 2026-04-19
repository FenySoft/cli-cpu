# Hardveres Boot Szekvencia (HW Boot)

> English version: [hw-boot-en.md](hw-boot-en.md)

> Version: 1.0

A CFPU chip bekapcsolásától a Rich core indulásáig tartó **tisztán hardveres** folyamat. Ez a szekvencia az operációs rendszer (Neuron OS) indulása **előtt** történik — szoftver nem vesz részt benne.

> A Neuron OS boot szekvenciáját (4-11. lépés) lásd: [FenySoft/NeuronOS — boot-sequence-hu.md](https://github.com/FenySoft/NeuronOS/docs/boot-sequence-hu.md)

## Tartalom

1. [Áttekintés](#attekintes)
2. [1. lépés — Power-On Reset (POR)](#por)
3. [2. lépés — Seal Core boot](#sealcore)
4. [3. lépés — Rich core start](#richcore)
5. [HW Register összesítés (MMIO)](#mmio)
6. [SRAM Layout (Rich core)](#sram)
7. [Core típusok boot-szempontból](#coretipusok)
8. [Changelog](#changelog)

---

## Áttekintés <a name="attekintes"></a>

```
[Tápfeszültség]
     │
     ▼
[1. Power-On Reset] ──── POR circuit, minden core reset
     │
     ▼
[2. Seal Core indul] ──── Mask ROM firmware (immutable)
     │                     Self-test, eFuse root hash olvasás
     │                     QSPI flash → SRAM másolás
     │                     SHA-256 + WOTS+/LMS HW verifikáció
     │
     ├── FAIL → ZEROIZATION + HALT
     │
     ▼ OK
[3. Rich core indul] ──── Seal Core jelzi: verified code ready
     │                     Rich core Quench-RAM CODE régióból indul
     ▼
[Neuron OS boot] ────── Innentől szoftver (→ NeuronOS repo)
```

---

## 1. lépés — Power-On Reset (POR) <a name="por"></a>

A POR circuit a tápfeszültség stabilizálódásáig aktív reset jelet tart minden core-on.

| Elem | Állapot POR után |
|------|-----------------|
| Seal Core | **Elsőként indul** — mask ROM entry point |
| Rich core | Reset-ben **vár** — a Seal Core engedélyezésére |
| Nano core-ok (10 000+) | **Sleep módban** — wake-on-mailbox-interrupt |
| Minden SRAM | Tartalom undefined |
| Mailbox FIFO-k | Üresek |
| Program counter | 0 (minden core) |

**HW követelmény:**
- POR (Power-On Reset) circuit
- Seal Core mask ROM address hardwired
- Rich core reset latch (Seal Core által vezérelve)
- Nano core-ok default sleep state

---

## 2. lépés — Seal Core boot <a name="sealcore"></a>

A Seal Core egy **dedikált, nem-programozható biztonsági core**. Mask ROM firmware-rel fut — nem flash-ről, nem SRAM-ból. Részletes leírás: [sealcore-hu.md](sealcore-hu.md)

### 2a. Self-test

A Seal Core ellenőrzi saját integritását:
- SHA-256 HW unit működik?
- WOTS+ HW verifier működik?
- SRAM tiszta (minden 0)?
- eFuse root hash olvasható?

### 2b. eFuse root hash olvasás

32 byte SHA-256 hash — gyártáskor beégetve, **immutable**, 30+ év élettartam.

Ez a trust chain gyökere. Részletes trust-lánc leírás: [authcode-hu.md §7](authcode-hu.md#trustchain)

### 2c. QSPI flash olvasás

A Seal Core MMIO-n (`0xF0001000`) keresztül olvassa a külső flash-t:
- Neuron OS CIL binary
- Hozzá tartozó aláírás és tanúsítvány

### 2d. Hardveres kriptográfiai verifikáció

A verifikáció **teljes egészében HW-ben** történik, dedikált accelerátorokkal:

```
1. SHA-256(CIL bytecode) kiszámítás           ← HW SHA-256 unit (~80 cycle/block)
2. Összehasonlítás a tanúsítvány hash mezőjével ← code-hash check
3. WOTS+ public key rekonstrukció              ← HW WOTS+ verifier (~500 SHA-256 op)
4. Leaf hash → Merkle root kiszámítás          ← HW Merkle path verifier (h=10 → 10 hash)
5. Összehasonlítás az eFuse root hash-sel      ← root-of-trust check
```

**Teljes verifikáció:** ~512 SHA-256 művelet = ~41 000 ciklus @ 1 GHz = **~41 µs**

A tanúsítvány formátumot és az aláírási modellt (PQC, WOTS+/LMS) lásd: [authcode-hu.md](authcode-hu.md)

### Seal Core HW accelerátorok

| Egység | Gate count | Funkció |
|--------|-----------|---------|
| SHA-256 HW unit | ~5K gate | ~80 cycle/block (512-bit input) |
| WOTS+ verifier | ~3K gate | SHA-256 chain rekonstrukció (67 chain × ~7.5 hash) |
| Merkle path verifier | ~2K gate | h=10 iteráció = 10 SHA-256 hash |
| **Összesen** | **~10K gate** | Teljes verify ~41 µs |

### Verifikáció eredménye

| Eredmény | Mi történik |
|----------|-------------|
| **VALID** | A verified kód a **Quench-RAM CODE régióba** kerül, SEAL-elődik (immutable), Seal Core jelzi a Rich core-nak: indulhat. |
| **INVALID** | **ZEROIZATION** — minden RAM és cache törlődik. Chip **lockdown** módba kerül. Semmilyen kód nem fut. |

---

## 3. lépés — Rich core start <a name="richcore"></a>

| Esemény | Leírás |
|---------|--------|
| Seal Core → Rich core jelzés | `0xF0002024` regiszter: `0` = wait, `1` = verified + go, `2` = fail + halt |
| Rich core reset elengedődik | A Rich core a Quench-RAM CODE régióból indul |
| CODE régió read-only | SEAL-elt — a Rich core nem tudja módosítani |
| CIL execution engine aktív | Eval stack, locals, call frames inicializálódnak |

A Rich core az első CIL metódust hívja: `NeuronOS.Boot.Main()` — **innentől szoftver** (→ [NeuronOS repo](https://github.com/FenySoft/NeuronOS)).

**HW követelmény:**
- Quench-RAM CODE régió (SEAL-elt, R/O a Rich core számára)
- Rich core start signal fogadás (`0xF0002024`)
- CIL execution engine

---

## HW Register összesítés (MMIO) <a name="mmio"></a>

Boot-releváns regiszterek. A teljes MMIO térképet lásd: [osreq-002 — MMIO Memory Map](osreq-from-os/osreq-002-mmio-memory-map-hu.md)

### Seal Core regiszterek

| Register | Cím | Típus | Méret | Leírás |
|----------|-----|-------|-------|--------|
| eFuse root hash | `0xF0002000` | R/O | 32 byte | SHA-256 root hash — gyártáskor beégetve, **immutable** |
| Seal Core status | `0xF0002020` | R/O | 4 byte | Self-test result, verify result, heartbeat |
| Seal Core → Rich core signal | `0xF0002024` | R/O | 4 byte | 0 = wait, 1 = verified + go, 2 = fail + halt |
| Quench-RAM CODE base | `0xF0002030` | R/O | 4 byte | Verified CIL binary kezdőcíme |
| Quench-RAM CODE size | `0xF0002034` | R/O | 4 byte | Verified CIL binary mérete |

### Flash controller

| Register | Cím | Típus | Méret | Leírás |
|----------|-----|-------|-------|--------|
| QSPI config | `0xF0001000` | R/W | 4 byte | Enable, SPI mode, clock divider |
| QSPI flash addr | `0xF0001004` | R/W | 4 byte | Flash olvasási cím |
| QSPI binary size | `0xF0001008` | R/O | 4 byte | Binary méret (flash header-ből) |
| QSPI data | `0xF000100C` | R/O | 1 byte | Következő byte a flash-ről |

### Core discovery és vezérlés

| Register | Cím | Típus | Méret | Leírás |
|----------|-----|-------|-------|--------|
| Core count (Nano) | `0xF0000100` | R/O | 4 byte | Nano core-ok száma |
| Core count (Rich) | `0xF0000104` | R/O | 4 byte | Rich core-ok száma |
| Mailbox base address | `0xF0000200` | R/O | 4 byte | Mailbox FIFO-k fizikai címtartomány kezdete |
| Mailbox enable (per core) | `0xF0000300 + core_id × 4` | R/W | 4 byte | Mailbox FIFO aktiválás bit |
| Core status (per core) | `0xF0000400 + core_id × 4` | R/O | 4 byte | Sleeping / Running / Error / Reset |
| Interrupt controller | `0xF0000600` | R/W | 16 byte | Interrupt vektor beállítás |
| Mailbox address table | `0xF0000800 + core_id × 4` | R/O | 4 byte | core-id → mailbox FIFO fizikai cím |

---

## SRAM Layout (Rich core) <a name="sram"></a>

A Rich core SRAM tartalma a HW boot (3. lépés) végén, mielőtt a Neuron OS elindul:

```
┌─────────────────────────────────┐ 0x00000000
│ CIL Code (Seal Core által SEAL) │ ~16-48 KB (NeuronOS binary, VERIFIED, R/O)
├─────────────────────────────────┤ 0x0000C000
│ Eval Stack                      │ ~2-4 KB (CIL execution stack)
├─────────────────────────────────┤ 0x0000D000
│ Call Frames + Local Variables   │ ~4-8 KB (metódus hívások)
├─────────────────────────────────┤ 0x0000F000
│ Heap (szabad)                   │ ~16-64 KB (OS inicializálás után töltődik)
├─────────────────────────────────┤ 0x0002F000
│ Mailbox FIFO (Rich core saját)  │ ~64-512 byte (8-64 slot)
├─────────────────────────────────┤ 0x0002F200
│ Szabad                          │
└─────────────────────────────────┘ 0x0003FFFF (256 KB)
```

---

## Core típusok boot-szempontból <a name="coretipusok"></a>

| Tulajdonság | Seal Core | Rich Core | Nano Core |
|-------------|-----------|-----------|-----------|
| **Boot sorrend** | **ELSŐ** | Második (Seal Core után) | Utolsó (OS indítja) |
| **Firmware** | Mask ROM (immutable) | Flash-ről (verified) | Flash-ről (verified, T0) |
| **Programozható?** | **NEM** (HW-burned) | Igen | Igen |
| **SRAM** | 64 KB (trusted zone) | 64-256 KB | 4-16 KB |
| **SHA-256 + WOTS+ HW** | **Igen** (dedikált) | Nem | Nem |
| **Mailbox FIFO** | Nincs (nem actor) | Van (HW) | Van (HW) |
| **Darabszám / chip** | 1 (vagy 2, redundancia) | 1-4 | 10 000+ |

Részletes core leírás: [core-types-hu.md](core-types-hu.md)

---

## Changelog <a name="changelog"></a>

| Verzió | Dátum | Változás |
|--------|-------|---------|
| 1.0 | 2026-04-19 | Első verzió — HW boot szétválasztva a NeuronOS boot-sequence-hu.md-ből |
