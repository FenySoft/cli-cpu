# CIL-Seal — ISA Specifikáció

> English version: [ISA-CIL-Seal-en.md](ISA-CIL-Seal-en.md)

> Version: 0.1 (draft)

Ez a dokumentum a **CIL-Seal** utasításkészletet specifikálja, amely a Seal Core firmware-jének ISA-ja. A CIL-Seal a CIL-T0 **superset-je**: minden CIL-T0 opkód elérhető, plusz tömb-kezelés és external hardware unit hívás.

## Áttekintés

A Seal Core firmware-je **C# forráskód**, amelyet a Roslyn fordít .dll-re, a TCliCpuLinker (vagy annak bővített változata) linkel CIL-Seal binárisra, és a `TSealCpu` szimulátor futtatja. A firmware a chip gyártásakor **mask ROM-ba / eFuse-ba** kerül — futás közben nem módosítható.

### Tervezési elvek

1. **A Roslyn fordítja** — a firmware C# forrásból származik, a Roslyn által generált CIL-ből épül. Nincs kézi assembly.
2. **CIL-T0 kompatibilis alap** — minden CIL-T0 opkód változatlanul működik.
3. **Tömb-támogatás** — `byte[]` kezelés szükséges a kriptográfiai bufferekhez (SHA-256 input/output, cert adatok).
4. **External call = HW unit** — a `static extern` metódusok hardveres gyorsítókat képviselnek (SHA-256, WOTS+, Merkle). A szimulátorban ezek szoftveres implementációk.
5. **Nincs GC** — a tömbök a heap-en élnek, de nincs garbage collector. A firmware determinisztikus élettartamú buffereket használ (alloc → use → discard a frame végén).

## Memória modell

A Seal Core 64 KB SRAM-mal rendelkezik, amely két régióra oszlik:

```
┌─────────────────────────────────┐ 0xFFFF (64 KB vége)
│                                 │
│  Heap (felülről lefelé nő)      │
│  byte[] allokációk              │
│                                 │
├─────────────── HP ──────────────┤
│         szabad terület          │
├─────────────── SP ──────────────┤
│                                 │
│  Stack (alulról felfelé nő)     │
│  call frames + eval stack       │
│                                 │
└─────────────────────────────────┘ 0x0000
```

| Régió | Irány | Tartalom |
|-------|-------|----------|
| **Stack** | alulról felfelé | Call frame-ek (header + args + locals + eval stack) — kompatibilis a TCpu-val |
| **Heap** | felülről lefelé | Tömb objektumok (header + adat) |

**Stack pointer (SP):** a stack teteje, 0-ról indul, felfelé nő — azonos a meglévő TCpu viselkedéssel.

**Heap pointer (HP):** a következő szabad heap-cím. Kezdetben `SRAM_SIZE` (0xFFFF). A `newarr` a HP-t **lefelé** lépteti (HP -= allokációs méret), majd a HP-re allokál.

**Collision trap:** ha `SP >= HP` (a stack és a heap összeérne), `SRAM_OVERFLOW` trap.

### Tömb objektum layout a heap-en

```
Offset   Méret    Mező
────────────────────────────────
0x00     4        Length (elemszám, int32)
0x04     Length   Data (byte tömb elemei, tömören)
         padding  4-byte alignment-re kerekítve
```

A stacken a tömbre egy **heap-cím** (int32) hivatkozik — ez a tömb objektum layout kezdőcíme a heap-en.

**Null referencia:** a 0xFFFFFFFF érték jelöli a null-t (a heap soha nem nő eddig). A null referenciára végrehajtott `ldelem`/`stelem`/`ldlen` `NULL_REFERENCE` trap-et dob.

## A CIL-T0-hoz képest új opkódok

### Tömb opkódok

| Bájt | Opkód | Hossz | Stack | Leírás |
|------|-------|-------|-------|--------|
| `0x8D` | `newarr <token>` | 5 | `(I4 → ref)` | TOS = length; allokál `length` byte-os tömböt a heap-en; push a tömb heap-címét. Token: ignorált (mindig byte[]). |
| `0x8E` | `ldlen` | 1 | `(ref → I4)` | TOS = tömb ref; push a tömb Length mezőjét. |
| `0x90` | `ldelem.u1` | 1 | `(ref, I4 → I4)` | TOS = index, TOS-1 = tömb ref; push `array[index]` zero-extended byte-ként. |
| `0x9C` | `stelem.i1` | 1 | `(ref, I4, I4 →)` | TOS = value, TOS-1 = index, TOS-2 = tömb ref; `array[index] = (byte)value`. |

**Trap feltételek:**

| Trap | Feltétel |
|------|----------|
| `SRAM_OVERFLOW` | `newarr`: a heap és a stack összeérne |
| `NULL_REFERENCE` | `ldlen`/`ldelem`/`stelem`: ref == 0xFFFFFFFF |
| `INDEX_OUT_OF_RANGE` | `ldelem`/`stelem`: index < 0 vagy index >= length |
| `NEGATIVE_ARRAY_SIZE` | `newarr`: length < 0 |

### External call (HW unit dispatch)

Az external metódusok a standard `call` opkódot használják (`0x28`), de a linker egy **speciális RVA tartományba** oldja fel őket:

```
Normál metódus RVA:    0x0000_0000 – 0xFFFE_FFFF
External HW dispatch:  0xFFFF_0000 – 0xFFFF_FFFF
```

Amikor a CPU végrehajtja a `call` opkódot és a cél RVA >= `0xFFFF_0000`:
- **Nem** ugrik a CODE régióba
- Az alsó 16 bit a **HW unit dispatch index**
- A CPU a dispatch táblából kikeresi a megfelelő HW unit-ot, végrehajtja, és visszatér

### Linker felismerés — `[CryptoCall]` attribútum

A Roslyn a `static extern` metódusokhoz **nem generál IL body-t** (RVA = 0 a PE-ben). A felismerés a `[CryptoCall(index)]` custom attribute alapján történik:

```csharp
[AttributeUsage(AttributeTargets.Method)]
public sealed class CryptoCallAttribute : Attribute
{
    public CryptoCallAttribute(ushort ADispatchIndex)
    {
        DispatchIndex = ADispatchIndex;
    }

    public ushort DispatchIndex { get; }
}
```

A linker:
1. Felismeri: `MethodDef` aminek RVA == 0 (nincs IL body) **és** rendelkezik `[CryptoCall]` attribútummal
2. Kiolvassa a `DispatchIndex` értéket az attribútum konstruktor-argumentumából
3. A `call` token-t `0xFFFF_0000 + DispatchIndex`-re írja

**Előny:** a dispatch index explicit a forráskódban — nincs string-alapú lookup, nincs félreértés.

### HW unit dispatch tábla (v0.1)

| Index | Dispatch RVA | C# szignatúra | HW unit | Leírás |
|-------|--------------|---------------|---------|--------|
| 0x0000 | `0xFFFF_0000` | `Sha256.Compute(byte[] AInput, int ALength) → byte[]` | SHA-256 | Kiszámítja a 32 byte-os SHA-256 hash-t |
| 0x0001 | `0xFFFF_0001` | `Sha256.ComputeBlock(byte[] AState, byte[] ABlock) → byte[]` | SHA-256 | Egyetlen 64-byte blokk feldolgozása (pipeline) |
| 0x0002 | `0xFFFF_0002` | `WotsPlus.Verify(byte[] APublicKey, byte[] ASignature, byte[] AMessage) → int` | WOTS+ | WOTS+ aláírás verifikáció. Return: 1=valid, 0=invalid |
| 0x0003 | `0xFFFF_0003` | `MerklePath.Verify(byte[] ARoot, byte[] ALeaf, byte[] APath, int AIndex) → int` | Merkle | Merkle-fa útvonal verifikáció. Return: 1=valid, 0=invalid |

## Seal Core specifikus regiszterek és állapotok

### Belső állapot

| Állapot | Típus | Leírás |
|---------|-------|--------|
| PC | int32 | Program Counter — a CODE (ROM) régióban |
| SP | int32 | Stack Pointer — az SRAM stack teteje (felülről lefelé) |
| HP | int32 | Heap Pointer — a heap következő szabad címe (alulról felfelé) |
| FP | int32 | Frame Pointer — az aktuális frame bázisa |
| Halted | bool | A core leállt-e |
| State | enum | Boot, SelfTest, Ready, Faulted |

### Seal Core állapotgép

```
┌─────────┐     ┌──────────┐     ┌─────────┐
│ PowerOff│────>│ Booting  │────>│SelfTest │
└─────────┘     └──────────┘     └────┬────┘
                                      │
                           ┌──────────┼──────────┐
                           │ OK                   │ FAIL
                           ▼                      ▼
                     ┌─────────┐           ┌──────────┐
                     │  Ready  │           │ Faulted  │
                     └─────────┘           └──────────┘
```

## Trap típusok (CIL-T0 + Seal bővítés)

A CIL-T0 összes trap-je érvényes, plusz:

| Trap # | Név | Leírás |
|--------|-----|--------|
| 0x0D | `NULL_REFERENCE` | Null tömb referenciára ldlen/ldelem/stelem |
| 0x0E | `INDEX_OUT_OF_RANGE` | Tömb index a határokon kívül |
| 0x0F | `NEGATIVE_ARRAY_SIZE` | newarr negatív mérettel |
| 0x10 | `SRAM_OVERFLOW` | Heap és stack összeér |
| 0x11 | `INVALID_EXTERNAL_CALL` | Ismeretlen dispatch index |

## CIL-Seal bináris formátum

Azonos a CIL-T0 bináris formátummal (`.t0` header, metódus fejlécek), de:

- **Magic:** `"TSCL"` (0x4C 0x43 0x53 0x54) — "T0 Seal" megkülönböztetés
- **Version:** 0x0002
- A `call` tokenek tartalmazhatnak `0xFFFF_xxxx` értékeket (external dispatch)

## A firmware mint C# projekt

```csharp
// A Seal Core firmware belépési pontja
public static class SealFirmware
{
    // Belépési pont — a ROM elejéről indul (RVA = 0x0000)
    public static void Boot()
    {
        // 1. Self-test
        if (!SelfTest())
        {
            Trap.Fault();
            return;
        }

        // 2. Ready loop — .acode konténerek fogadása
        while (true)
        {
            // Mailbox-ból olvas, AuthCode verify, code-load
        }
    }

    private static bool SelfTest()
    {
        // SHA-256 unit teszt: ismert input → ismert output
        byte[] testInput = new byte[] { 0x61, 0x62, 0x63 }; // "abc"
        byte[] hash = Sha256.Compute(testInput, 3);

        // Elvárt: BA7816BF 8F01CFEA 414140DE 5DAE2223
        //         B00361A3 96177A9C B410FF61 F20015AD
        return hash[0] == 0xBA && hash[1] == 0x78; // ...stb
    }
}

// External HW unit deklarációk — [CryptoCall] attribútummal
public static class Sha256
{
    [CryptoCall(0x0000)]
    public static extern byte[] Compute(byte[] AInput, int ALength);

    [CryptoCall(0x0001)]
    public static extern byte[] ComputeBlock(byte[] AState, byte[] ABlock);
}

public static class WotsPlus
{
    [CryptoCall(0x0002)]
    public static extern int Verify(byte[] APublicKey, byte[] ASignature, byte[] AMessage);
}

public static class MerklePath
{
    [CryptoCall(0x0003)]
    public static extern int Verify(byte[] ARoot, byte[] ALeaf, byte[] APath, int AIndex);
}
```

## Eldöntött kérdések

1. **Stack irány** — alulról felfelé, kompatibilis a meglévő TCpu szimulátorral. A heap felülről lefelé nő, egymás felé haladnak.
2. **External call jelölés** — `[CryptoCall(index)]` custom attribute a `static extern` metódusokon. A dispatch index explicit a forráskódban, a linker a metaadat custom attribute-ból olvassa.
3. **Cella méret: 16B header + 64B payload = 80 byte** — az interconnect spec (v2.0) szerinti fix cella. A 128B payload elvetett opció: a tipikus actor workload ~80%-a ≤48 byte, a 64B cella ~38%-kal jobb aggregált throughput-ot ad a 10 000 core-os mesh-ben (kevesebb link-foglalás kicsi üzenetekre, alacsonyabb HOL blocking). A code-load throughput kérdése multi-cell streaming-gel megoldott (256 cella = 16KB, ~8μs @ 500 MHz). Az ML-Max saját systolic routert használ, nem a fő mesh-t.

## Nyitott kérdések

1. **Heap GC** — a firmware kicsi és determinisztikus, tehát a heap-et "arena allocator" módon kezelhetjük (boot-kor vagy feladatonként reset). Kell-e `free` mechanizmus?
2. **byte[] vs int32[]** — a jelenlegi CIL-T0 int32-only. A `byte[]` bevezetése minimum `ldelem.u1` és `stelem.i1` opkódokat igényli. Kell-e `int[]` is (pl. hash állapotnak)?
3. **newarr token** — a Roslyn `newarr` opkódja egy type token-t kap. A linkernek ezt hogyan kell kezelnie? Javaslat: ignorálni (mindig byte[]-nak tekinteni), vagy megkülönböztetni byte[]/int[] típust.
4. **External call visszatérési érték** — a `byte[] Compute(...)` egy heap-allokált tömböt ad vissza. Ki allokálja: a HW unit (a szimulátor maga allokál a heap-en és visszaadja a címet), vagy a firmware explicit `newarr`-ral előkészít egy buffert, és a HW unit abba ír?

## Kapcsolódó dokumentumok

- `docs/ISA-CIL-T0-hu.md` — a CIL-T0 alap ISA (48 opkód)
- `docs/sealcore-hu.md` — a Seal Core architektúra és szerepe
- `docs/authcode-hu.md` — az AuthCode mechanizmus, amit a firmware futtat
- `docs/quench-ram-hu.md` — a QRAM memóriacella (SEAL/RELEASE trigger)

## Changelog

| Verzió | Dátum | Összefoglaló |
|--------|-------|-------------|
| 0.1 | 2026-04-20 | Kezdeti draft. CIL-T0 superset: tömb opkódok (newarr, ldlen, ldelem.u1, stelem.i1), external call dispatch (SHA-256, WOTS+, Merkle), heap memória modell, Seal Core állapotgép. |
