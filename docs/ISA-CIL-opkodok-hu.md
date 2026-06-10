---
status: living
---

# ECMA-335 CIL — Teljes opkód referencia

> Version: 1.1

Ez a dokumentum az **ECMA-335 CIL teljes utasításkészletét** tartalmazza, minden opkódhoz megjelölve a **CLI-CPU implementációs státuszát** és az **utasítás bájtban mért hosszát**.

## Státusz jelölések

| Jelölés | Jelentés |
|---------|----------|
| **T0** | CIL-T0-ban megvalósítva — Nano core (F3) |
| **Rich** | Rich core-ban tervezett (F5, teljes ECMA-335) |
| **Skip** | ECMA-335-ben definiált, Roslyn modern C#-ból nem generálja; kihagyható |

## Hossz értelmezése

| Operandus típus | Opkód bájtok | Operandus | Összesen |
|----------------|-------------|-----------|----------|
| nincs (1-bájtos opkód) | 1 | 0 | **1 bájt** |
| `<i1>` / `<ui1>` (1-bájtos opkód) | 1 | 1 | **2 bájt** |
| `<i4>` / `<ui4>` / `<token>` / `<f4>` (1-bájtos opkód) | 1 | 4 | **5 bájt** |
| `<i8>` / `<f8>` (1-bájtos opkód) | 1 | 8 | **9 bájt** |
| nincs (0xFE prefix) | 2 | 0 | **2 bájt** |
| `<ui1>` (0xFE prefix) | 2 | 1 | **3 bájt** |
| `<ui2>` (0xFE prefix) | 2 | 2 | **4 bájt** |
| `<token>` (0xFE prefix) | 2 | 4 | **6 bájt** |
| `switch` | 1 | 4 + n×4 | **5 + n×4 bájt** |

---

## 1. Verem-kezelés

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x00` | `nop` | — | 1 | … → … | Nincs művelet | **T0** |
| `0x01` | `break` | — | 1 | … → … | Debugger törési pont (standard) | **Rich** |
| `0x25` | `dup` | — | 1 | …, v → …, v, v | TOS duplikálása | **T0** |
| `0x26` | `pop` | — | 1 | …, v → … | TOS eldobása | **T0** |

> **T0 debug-break:** A CIL-T0 a `0xDD` bájtot (`leave` a standard ECMA-335-ben) használja debug-trapként, mivel `leave` exception handler nélkül értelmetlen. A standard `break` (0x01) Rich core-on lesz elérhető.

---

## 2. Konstansok betöltése

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x14` | `ldnull` | — | 1 | … → …, null | null push (T0: 0 mint I4) | **T0** |
| `0x15` | `ldc.i4.m1` | — | 1 | … → …, −1 | −1 push int32-ként | **T0** |
| `0x16` | `ldc.i4.0` | — | 1 | … → …, 0 | 0 push int32-ként | **T0** |
| `0x17` | `ldc.i4.1` | — | 1 | … → …, 1 | 1 push int32-ként | **T0** |
| `0x18` | `ldc.i4.2` | — | 1 | … → …, 2 | 2 push int32-ként | **T0** |
| `0x19` | `ldc.i4.3` | — | 1 | … → …, 3 | 3 push int32-ként | **T0** |
| `0x1A` | `ldc.i4.4` | — | 1 | … → …, 4 | 4 push int32-ként | **T0** |
| `0x1B` | `ldc.i4.5` | — | 1 | … → …, 5 | 5 push int32-ként | **T0** |
| `0x1C` | `ldc.i4.6` | — | 1 | … → …, 6 | 6 push int32-ként | **T0** |
| `0x1D` | `ldc.i4.7` | — | 1 | … → …, 7 | 7 push int32-ként | **T0** |
| `0x1E` | `ldc.i4.8` | — | 1 | … → …, 8 | 8 push int32-ként | **T0** |
| `0x1F` | `ldc.i4.s` | `<i1>` | 2 | … → …, n | 8-bit signed immediate sign-extend push | **T0** |
| `0x20` | `ldc.i4` | `<i4>` | 5 | … → …, n | 32-bit immediate push (little-endian) | **T0** |
| `0x21` | `ldc.i8` | `<i8>` | 9 | … → …, n | 64-bit immediate push | **Rich** |
| `0x22` | `ldc.r4` | `<f4>` | 5 | … → …, n | 32-bit float immediate push | **Rich** |
| `0x23` | `ldc.r8` | `<f8>` | 9 | … → …, n | 64-bit float immediate push | **Rich** |
| `0x72` | `ldstr` | `<token>` | 5 | … → …, str | String literál push (heap-ből) | **Rich** |

---

## 3. Argumentumok és lokális változók

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x02` | `ldarg.0` | — | 1 | … → …, v | 0. argumentum push | **T0** |
| `0x03` | `ldarg.1` | — | 1 | … → …, v | 1. argumentum push | **T0** |
| `0x04` | `ldarg.2` | — | 1 | … → …, v | 2. argumentum push | **T0** |
| `0x05` | `ldarg.3` | — | 1 | … → …, v | 3. argumentum push | **T0** |
| `0x0E` | `ldarg.s` | `<ui1>` | 2 | … → …, v | n. argumentum push (0–255) | **T0** |
| `0x10` | `starg.s` | `<ui1>` | 2 | …, v → … | TOS → n. argumentum (0–255) | **T0** |
| `0x06` | `ldloc.0` | — | 1 | … → …, v | 0. lokális push | **T0** |
| `0x07` | `ldloc.1` | — | 1 | … → …, v | 1. lokális push | **T0** |
| `0x08` | `ldloc.2` | — | 1 | … → …, v | 2. lokális push | **T0** |
| `0x09` | `ldloc.3` | — | 1 | … → …, v | 3. lokális push | **T0** |
| `0x11` | `ldloc.s` | `<ui1>` | 2 | … → …, v | n. lokális push (0–255) | **T0** |
| `0x12` | `ldloca.s` | `<ui1>` | 2 | … → …, &v | n. lokális **cím** push | **Rich** |
| `0x13` | `stloc.s` | `<ui1>` | 2 | …, v → … | TOS → n. lokális (0–255) | **T0** |
| `0x0A` | `stloc.0` | — | 1 | …, v → … | TOS → 0. lokális | **T0** |
| `0x0B` | `stloc.1` | — | 1 | …, v → … | TOS → 1. lokális | **T0** |
| `0x0C` | `stloc.2` | — | 1 | …, v → … | TOS → 2. lokális | **T0** |
| `0x0D` | `stloc.3` | — | 1 | …, v → … | TOS → 3. lokális | **T0** |
| `0xFE 0x09` | `ldarg` | `<ui2>` | 4 | … → …, v | n. argumentum push (hosszú, 0–65535) | **Rich** |
| `0xFE 0x0A` | `ldarga` | `<ui2>` | 4 | … → …, &v | n. argumentum **cím** push (hosszú) | **Rich** |
| `0xFE 0x0B` | `starg` | `<ui2>` | 4 | …, v → … | TOS → n. argumentum (hosszú) | **Rich** |
| `0xFE 0x0C` | `ldloc` | `<ui2>` | 4 | … → …, v | n. lokális push (hosszú) | **Rich** |
| `0xFE 0x0D` | `ldloca` | `<ui2>` | 4 | … → …, &v | n. lokális **cím** push (hosszú) | **Rich** |
| `0xFE 0x0E` | `stloc` | `<ui2>` | 4 | …, v → … | TOS → n. lokális (hosszú) | **Rich** |

---

## 4. Aritmetika és logika

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x58` | `add` | — | 1 | …, v1, v2 → …, r | v1 + v2 (wrap) | **T0** |
| `0x59` | `sub` | — | 1 | …, v1, v2 → …, r | v1 − v2 (wrap) | **T0** |
| `0x5A` | `mul` | — | 1 | …, v1, v2 → …, r | v1 × v2 (wrap) | **T0** |
| `0x5B` | `div` | — | 1 | …, v1, v2 → …, r | v1 / v2 (signed) | **T0** |
| `0x5C` | `div.un` | — | 1 | …, v1, v2 → …, r | v1 / v2 (unsigned) | **Rich** |
| `0x5D` | `rem` | — | 1 | …, v1, v2 → …, r | v1 % v2 (signed) | **T0** |
| `0x5E` | `rem.un` | — | 1 | …, v1, v2 → …, r | v1 % v2 (unsigned) | **Rich** |
| `0x5F` | `and` | — | 1 | …, v1, v2 → …, r | v1 AND v2 | **T0** |
| `0x60` | `or` | — | 1 | …, v1, v2 → …, r | v1 OR v2 | **T0** |
| `0x61` | `xor` | — | 1 | …, v1, v2 → …, r | v1 XOR v2 | **T0** |
| `0x62` | `shl` | — | 1 | …, v1, v2 → …, r | v1 << (v2 & 31) | **T0** |
| `0x63` | `shr` | — | 1 | …, v1, v2 → …, r | v1 >> (v2 & 31) aritmetikai | **T0** |
| `0x64` | `shr.un` | — | 1 | …, v1, v2 → …, r | v1 >> (v2 & 31) logikai | **T0** |
| `0x65` | `neg` | — | 1 | …, v → …, −v | Negálás | **T0** |
| `0x66` | `not` | — | 1 | …, v → …, ~v | Bitwise NOT | **T0** |
| `0xD6` | `add.ovf` | — | 1 | …, v1, v2 → …, r | v1 + v2 (signed, overflow trap) | **Rich** |
| `0xD7` | `add.ovf.un` | — | 1 | …, v1, v2 → …, r | v1 + v2 (unsigned, overflow trap) | **Rich** |
| `0xD8` | `mul.ovf` | — | 1 | …, v1, v2 → …, r | v1 × v2 (signed, overflow trap) | **Rich** |
| `0xD9` | `mul.ovf.un` | — | 1 | …, v1, v2 → …, r | v1 × v2 (unsigned, overflow trap) | **Rich** |
| `0xDA` | `sub.ovf` | — | 1 | …, v1, v2 → …, r | v1 − v2 (signed, overflow trap) | **Rich** |
| `0xDB` | `sub.ovf.un` | — | 1 | …, v1, v2 → …, r | v1 − v2 (unsigned, overflow trap) | **Rich** |

---

## 5. Típuskonverzió

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x67` | `conv.i1` | — | 1 | …, v → …, r | → int8 (sign-extend, nincs trap) | **Rich** |
| `0x68` | `conv.i2` | — | 1 | …, v → …, r | → int16 (sign-extend, nincs trap) | **Rich** |
| `0x69` | `conv.i4` | — | 1 | …, v → …, r | → int32 | **Rich** |
| `0x6A` | `conv.i8` | — | 1 | …, v → …, r | → int64 | **Rich** |
| `0x6B` | `conv.r4` | — | 1 | …, v → …, r | → float32 | **Rich** |
| `0x6C` | `conv.r8` | — | 1 | …, v → …, r | → float64 | **Rich** |
| `0x6D` | `conv.u4` | — | 1 | …, v → …, r | → uint32 | **Rich** |
| `0x6E` | `conv.u8` | — | 1 | …, v → …, r | → uint64 | **Rich** |
| `0x76` | `conv.r.un` | — | 1 | …, v → …, r | unsigned int → float (runtime méret) | **Rich** |
| `0xD1` | `conv.u2` | — | 1 | …, v → …, r | → uint16 (nincs trap) | **Rich** |
| `0xD2` | `conv.u1` | — | 1 | …, v → …, r | → uint8 (nincs trap) | **Rich** |
| `0xD3` | `conv.i` | — | 1 | …, v → …, r | → native int | **Rich** |
| `0xD4` | `conv.ovf.i` | — | 1 | …, v → …, r | → native int (overflow trap) | **Rich** |
| `0xD5` | `conv.ovf.u` | — | 1 | …, v → …, r | → native uint (overflow trap) | **Rich** |
| `0xE0` | `conv.u` | — | 1 | …, v → …, r | → native uint (nincs trap) | **Rich** |
| `0xC3` | `ckfinite` | — | 1 | …, v → …, v | FP végtelen/NaN ellenőrzés, trap ha igaz | **Rich** |
| `0xB3` | `conv.ovf.i1` | — | 1 | …, v → …, r | → int8 (overflow trap) | **Rich** |
| `0xB4` | `conv.ovf.u1` | — | 1 | …, v → …, r | → uint8 (overflow trap) | **Rich** |
| `0xB5` | `conv.ovf.i2` | — | 1 | …, v → …, r | → int16 (overflow trap) | **Rich** |
| `0xB6` | `conv.ovf.u2` | — | 1 | …, v → …, r | → uint16 (overflow trap) | **Rich** |
| `0xB7` | `conv.ovf.i4` | — | 1 | …, v → …, r | → int32 (overflow trap) | **Rich** |
| `0xB8` | `conv.ovf.u4` | — | 1 | …, v → …, r | → uint32 (overflow trap) | **Rich** |
| `0xB9` | `conv.ovf.i8` | — | 1 | …, v → …, r | → int64 (overflow trap) | **Rich** |
| `0xBA` | `conv.ovf.u8` | — | 1 | …, v → …, r | → uint64 (overflow trap) | **Rich** |
| `0x82` | `conv.ovf.i1.un` | — | 1 | …, v → …, r | unsigned → int8 (overflow trap) | **Rich** |
| `0x83` | `conv.ovf.i2.un` | — | 1 | …, v → …, r | unsigned → int16 (overflow trap) | **Rich** |
| `0x84` | `conv.ovf.i4.un` | — | 1 | …, v → …, r | unsigned → int32 (overflow trap) | **Rich** |
| `0x85` | `conv.ovf.i8.un` | — | 1 | …, v → …, r | unsigned → int64 (overflow trap) | **Rich** |
| `0x86` | `conv.ovf.u1.un` | — | 1 | …, v → …, r | unsigned → uint8 (overflow trap) | **Rich** |
| `0x87` | `conv.ovf.u2.un` | — | 1 | …, v → …, r | unsigned → uint16 (overflow trap) | **Rich** |
| `0x88` | `conv.ovf.u4.un` | — | 1 | …, v → …, r | unsigned → uint32 (overflow trap) | **Rich** |
| `0x89` | `conv.ovf.u8.un` | — | 1 | …, v → …, r | unsigned → uint64 (overflow trap) | **Rich** |
| `0x8A` | `conv.ovf.i.un` | — | 1 | …, v → …, r | unsigned → native int (overflow trap) | **Rich** |
| `0x8B` | `conv.ovf.u.un` | — | 1 | …, v → …, r | unsigned → native uint (overflow trap) | **Rich** |

---

## 6. Branch utasítások

### 6a. Rövid branch (8-bit offset, −128…+127 bájt)

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x2B` | `br.s` | `<i1>` | 2 | … → … | Feltétel nélküli ugrás | **T0** |
| `0x2C` | `brfalse.s` | `<i1>` | 2 | …, v → … | Ugrás ha v == 0 | **T0** |
| `0x2D` | `brtrue.s` | `<i1>` | 2 | …, v → … | Ugrás ha v != 0 | **T0** |
| `0x2E` | `beq.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 == v2 | **T0** |
| `0x2F` | `bge.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 ≥ v2 signed | **T0** |
| `0x30` | `bgt.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 > v2 signed | **T0** |
| `0x31` | `ble.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 ≤ v2 signed | **T0** |
| `0x32` | `blt.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 < v2 signed | **T0** |
| `0x33` | `bne.un.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 != v2 | **T0** |
| `0x34` | `bge.un.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 ≥ v2 unsigned | **Rich** |
| `0x35` | `bgt.un.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 > v2 unsigned | **Rich** |
| `0x36` | `ble.un.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 ≤ v2 unsigned | **Rich** |
| `0x37` | `blt.un.s` | `<i1>` | 2 | …, v1, v2 → … | Ugrás ha v1 < v2 unsigned | **Rich** |

### 6b. Hosszú branch (32-bit offset)

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x38` | `br` | `<i4>` | 5 | … → … | Feltétel nélküli ugrás (hosszú) | **Rich** |
| `0x39` | `brfalse` | `<i4>` | 5 | …, v → … | Ugrás ha v == 0 (hosszú) | **Rich** |
| `0x3A` | `brtrue` | `<i4>` | 5 | …, v → … | Ugrás ha v != 0 (hosszú) | **Rich** |
| `0x3B` | `beq` | `<i4>` | 5 | …, v1, v2 → … | v1 == v2 (hosszú) | **Rich** |
| `0x3C` | `bge` | `<i4>` | 5 | …, v1, v2 → … | v1 ≥ v2 signed (hosszú) | **Rich** |
| `0x3D` | `bgt` | `<i4>` | 5 | …, v1, v2 → … | v1 > v2 signed (hosszú) | **Rich** |
| `0x3E` | `ble` | `<i4>` | 5 | …, v1, v2 → … | v1 ≤ v2 signed (hosszú) | **Rich** |
| `0x3F` | `blt` | `<i4>` | 5 | …, v1, v2 → … | v1 < v2 signed (hosszú) | **Rich** |
| `0x40` | `bne.un` | `<i4>` | 5 | …, v1, v2 → … | v1 != v2 (hosszú) | **Rich** |
| `0x41` | `bge.un` | `<i4>` | 5 | …, v1, v2 → … | v1 ≥ v2 unsigned (hosszú) | **Rich** |
| `0x42` | `bgt.un` | `<i4>` | 5 | …, v1, v2 → … | v1 > v2 unsigned (hosszú) | **Rich** |
| `0x43` | `ble.un` | `<i4>` | 5 | …, v1, v2 → … | v1 ≤ v2 unsigned (hosszú) | **Rich** |
| `0x44` | `blt.un` | `<i4>` | 5 | …, v1, v2 → … | v1 < v2 unsigned (hosszú) | **Rich** |
| `0x45` | `switch` | `<n, i4[]>` | 5+n×4 | …, v → … | Jump table: v indexeli az offset-tömböt | **Rich** |

---

## 7. Összehasonlítás (0xFE prefix)

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0xFE 0x01` | `ceq` | — | 2 | …, v1, v2 → …, r | 1 ha v1 == v2, egyébként 0 | **T0** |
| `0xFE 0x02` | `cgt` | — | 2 | …, v1, v2 → …, r | 1 ha v1 > v2 signed, egyébként 0 | **T0** |
| `0xFE 0x03` | `cgt.un` | — | 2 | …, v1, v2 → …, r | 1 ha v1 > v2 unsigned, egyébként 0 | **T0** |
| `0xFE 0x04` | `clt` | — | 2 | …, v1, v2 → …, r | 1 ha v1 < v2 signed, egyébként 0 | **T0** |
| `0xFE 0x05` | `clt.un` | — | 2 | …, v1, v2 → …, r | 1 ha v1 < v2 unsigned, egyébként 0 | **T0** |

---

## 8. Hívás és visszatérés

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x28` | `call` | `<token>` | 5 | …, a0…an → …, [rv] | Statikus metódus hívás (pre-linked RVA) | **T0** |
| `0x2A` | `ret` | — | 1 | [v] → | Visszatérés; return value a hívó veremre kerül | **T0** |
| `0x27` | `jmp` | `<token>` | 5 | — | Teljes stack-cserés tail-call | **Skip** |
| `0x29` | `calli` | `<sig>` | 5 | …, fptr, a0…an → …, [rv] | Indirekt hívás fn-pointeren át | **Rich** |
| `0x6F` | `callvirt` | `<token>` | 5 | …, obj, a0…an → …, [rv] | Virtuális / interface metódus hívás | **Rich** |
| `0xFE 0x06` | `ldftn` | `<token>` | 6 | … → …, fptr | Statikus metódus pointer push | **Rich** |
| `0xFE 0x07` | `ldvirtftn` | `<token>` | 6 | …, obj → …, fptr | Virtuális metódus pointer push | **Rich** |
| `0xD0` | `ldtoken` | `<token>` | 5 | … → …, handle | RuntimeHandle push (type / method / field) | **Rich** |

> **Skip — jmp:** Roslyn soha nem generálja; a tail-call optimalizálást a `tail.` prefix + `call/callvirt` végzi.

---

## 9. Közvetett memória-hozzáférés

### 9a. Betöltés (ldind)

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x46` | `ldind.i1` | — | 1 | …, addr → …, v | Olvasás → int8 sign-extend | **Rich** |
| `0x47` | `ldind.u1` | — | 1 | …, addr → …, v | Olvasás → uint8 zero-extend | **Rich** |
| `0x48` | `ldind.i2` | — | 1 | …, addr → …, v | Olvasás → int16 sign-extend | **Rich** |
| `0x49` | `ldind.u2` | — | 1 | …, addr → …, v | Olvasás → uint16 zero-extend | **Rich** |
| `0x4A` | `ldind.i4` | — | 1 | …, addr → …, v | Olvasás → int32 (little-endian) | **T0** |
| `0x4B` | `ldind.u4` | — | 1 | …, addr → …, v | Olvasás → uint32 | **Rich** |
| `0x4C` | `ldind.i8` | — | 1 | …, addr → …, v | Olvasás → int64 | **Rich** |
| `0x4D` | `ldind.i` | — | 1 | …, addr → …, v | Olvasás → native int | **Rich** |
| `0x4E` | `ldind.r4` | — | 1 | …, addr → …, v | Olvasás → float32 | **Rich** |
| `0x4F` | `ldind.r8` | — | 1 | …, addr → …, v | Olvasás → float64 | **Rich** |
| `0x50` | `ldind.ref` | — | 1 | …, addr → …, v | Olvasás → object ref | **Rich** |

### 9b. Tárolás (stind)

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x51` | `stind.ref` | — | 1 | …, addr, v → … | Tárolás → object ref | **Rich** |
| `0x52` | `stind.i1` | — | 1 | …, addr, v → … | Tárolás → 8-bit | **Rich** |
| `0x53` | `stind.i2` | — | 1 | …, addr, v → … | Tárolás → 16-bit | **Rich** |
| `0x54` | `stind.i4` | — | 1 | …, addr, v → … | Tárolás → 32-bit (little-endian) | **T0** |
| `0x55` | `stind.i8` | — | 1 | …, addr, v → … | Tárolás → 64-bit | **Rich** |
| `0x56` | `stind.r4` | — | 1 | …, addr, v → … | Tárolás → float32 | **Rich** |
| `0x57` | `stind.r8` | — | 1 | …, addr, v → … | Tárolás → float64 | **Rich** |
| `0xDF` | `stind.i` | — | 1 | …, addr, v → … | Tárolás → native int | **Rich** |

---

## 10. Objektummodell

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x73` | `newobj` | `<token>` | 5 | …, a0…an → …, obj | Heap allokáció + konstruktor hívás | **Rich** |
| `0x7B` | `ldfld` | `<token>` | 5 | …, obj → …, v | Instance field betöltés | **Rich** |
| `0x7C` | `ldflda` | `<token>` | 5 | …, obj → …, &v | Instance field **cím** betöltés | **Rich** |
| `0x7D` | `stfld` | `<token>` | 5 | …, obj, v → … | Instance field tárolás | **Rich** |
| `0x7E` | `ldsfld` | `<token>` | 5 | … → …, v | Statikus field betöltés | **Rich** |
| `0x7F` | `ldsflda` | `<token>` | 5 | … → …, &v | Statikus field **cím** betöltés | **Rich** |
| `0x80` | `stsfld` | `<token>` | 5 | …, v → … | Statikus field tárolás | **Rich** |
| `0x71` | `ldobj` | `<token>` | 5 | …, addr → …, v | Value type másolás veremre | **Rich** |
| `0x81` | `stobj` | `<token>` | 5 | …, addr, v → … | Value type tárolás memóriába | **Rich** |
| `0x70` | `cpobj` | `<token>` | 5 | …, dst, src → … | Value type másolás (src cím → dst cím) | **Skip** |
| `0xFE 0x15` | `initobj` | `<token>` | 6 | …, addr → … | Value type nullázás | **Rich** |
| `0xFE 0x0F` | `localloc` | — | 2 | …, n → …, addr | n bájt allokálása a stack-en | **Rich** |

> **Skip — cpobj:** Roslyn `ldobj` + `stobj` párt generál helyette.

---

## 11. Tömbök

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x8D` | `newarr` | `<token>` | 5 | …, n → …, arr | n-elemű 1D tömb allokálása | **Rich** |
| `0x8E` | `ldlen` | — | 1 | …, arr → …, n | Tömb hossz (uint32-ként) | **Rich** |
| `0x8F` | `ldelema` | `<token>` | 5 | …, arr, i → …, &e | Tömb elem **cím** | **Rich** |
| `0x90` | `ldelem.i1` | — | 1 | …, arr, i → …, v | Tömb elem → int8 | **Rich** |
| `0x91` | `ldelem.u1` | — | 1 | …, arr, i → …, v | Tömb elem → uint8 | **Rich** |
| `0x92` | `ldelem.i2` | — | 1 | …, arr, i → …, v | Tömb elem → int16 | **Rich** |
| `0x93` | `ldelem.u2` | — | 1 | …, arr, i → …, v | Tömb elem → uint16 | **Rich** |
| `0x94` | `ldelem.i4` | — | 1 | …, arr, i → …, v | Tömb elem → int32 | **Rich** |
| `0x95` | `ldelem.u4` | — | 1 | …, arr, i → …, v | Tömb elem → uint32 | **Rich** |
| `0x96` | `ldelem.i8` | — | 1 | …, arr, i → …, v | Tömb elem → int64 | **Rich** |
| `0x97` | `ldelem.i` | — | 1 | …, arr, i → …, v | Tömb elem → native int | **Rich** |
| `0x98` | `ldelem.r4` | — | 1 | …, arr, i → …, v | Tömb elem → float32 | **Rich** |
| `0x99` | `ldelem.r8` | — | 1 | …, arr, i → …, v | Tömb elem → float64 | **Rich** |
| `0x9A` | `ldelem.ref` | — | 1 | …, arr, i → …, v | Tömb elem → object ref | **Rich** |
| `0xA3` | `ldelem` | `<token>` | 5 | …, arr, i → …, v | Tömb elem generikus betöltés | **Rich** |
| `0x9B` | `stelem.i` | — | 1 | …, arr, i, v → … | Tömb tárolás → native int | **Rich** |
| `0x9C` | `stelem.i1` | — | 1 | …, arr, i, v → … | Tömb tárolás → int8 | **Rich** |
| `0x9D` | `stelem.i2` | — | 1 | …, arr, i, v → … | Tömb tárolás → int16 | **Rich** |
| `0x9E` | `stelem.i4` | — | 1 | …, arr, i, v → … | Tömb tárolás → int32 | **Rich** |
| `0x9F` | `stelem.i8` | — | 1 | …, arr, i, v → … | Tömb tárolás → int64 | **Rich** |
| `0xA0` | `stelem.r4` | — | 1 | …, arr, i, v → … | Tömb tárolás → float32 | **Rich** |
| `0xA1` | `stelem.r8` | — | 1 | …, arr, i, v → … | Tömb tárolás → float64 | **Rich** |
| `0xA2` | `stelem.ref` | — | 1 | …, arr, i, v → … | Tömb tárolás → object ref | **Rich** |
| `0xA4` | `stelem` | `<token>` | 5 | …, arr, i, v → … | Tömb tárolás generikus | **Rich** |

---

## 12. Típusellenőrzés és boxing

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x74` | `castclass` | `<token>` | 5 | …, obj → …, obj | Cast; InvalidCastException ha típus nem egyezik | **Rich** |
| `0x75` | `isinst` | `<token>` | 5 | …, obj → …, obj\|null | Null ha nem illeszkedik, egyébként obj | **Rich** |
| `0x8C` | `box` | `<token>` | 5 | …, v → …, obj | Value type becsomagolása heap-objektumba | **Rich** |
| `0x79` | `unbox` | `<token>` | 5 | …, obj → …, &v | Boxed value type **cím** kicsomagolása | **Rich** |
| `0xA5` | `unbox.any` | `<token>` | 5 | …, obj → …, v | Kicsomagolás + érték másolás veremre | **Rich** |
| `0xC2` | `refanyval` | `<token>` | 5 | …, ref → …, &v | Typed reference értékének kinyerése | **Skip** |
| `0xC6` | `mkrefany` | `<token>` | 5 | …, &v → …, ref | Typed reference létrehozása | **Skip** |
| `0xFE 0x1D` | `refanytype` | — | 2 | …, ref → …, type | Typed reference típusának kinyerése | **Skip** |

> **Skip — refanyval / mkrefany / refanytype:** Typed references — ECMA-335 reliktum, Roslyn modern C#-ból soha nem generálja.

---

## 13. Kivételkezelés

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0x7A` | `throw` | — | 1 | …, obj → | Kivétel dobás | **Rich** |
| `0xFE 0x1A` | `rethrow` | — | 2 | … → | Kivétel újradobás catch blokkon belül | **Rich** |
| `0xDD` | `leave` | `<i4>` | 5 | … → | Protected régióból kilépés (hosszú offset)¹ | **Rich** |
| `0xDE` | `leave.s` | `<i1>` | 2 | … → | Protected régióból kilépés (rövid offset) | **Rich** |
| `0xDC` | `endfinally` | — | 1 | … → | `finally` / `fault` blokk vége | **Rich** |
| `0xFE 0x11` | `endfilter` | — | 2 | …, v → | `filter` blokk vége (v=0: nem kezeli, v=1: kezeli) | **Rich** |

> ¹ **T0 eltérés:** A CIL-T0 a `0xDD` bájtot debug-trapként (`Break`) kezeli, mert `leave` exception handler nélküli kódban értelmetlen. Standard `leave` Rich core-on lesz elérhető.

---

## 14. Memóriakezelés

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0xFE 0x17` | `cpblk` | — | 2 | …, dst, src, n → … | n bájt másolása (src → dst) | **Rich** |
| `0xFE 0x18` | `initblk` | — | 2 | …, addr, v, n → … | n bájt feltöltése v értékkel | **Rich** |

---

## 15. Előtag utasítások (prefix)

Az előtag utasítások a következő utasítást módosítják; önmagukban nem hajtódnak végre.

| Hex | Mnemonic | Operandus | Hossz | Leírás | Státusz |
|-----|----------|-----------|-------|--------|---------|
| `0xFE 0x12` | `unaligned.` | `<ui1>` | 3 | Következő ldind/stind nem igazított hozzáférés (1/2/4 bájt) | **Rich** |
| `0xFE 0x13` | `volatile.` | — | 2 | Következő mem-hozzáférés volatile (nincs cache, nincs reorder) | **Rich** |
| `0xFE 0x14` | `tail.` | — | 2 | Következő call/calli/callvirt tail-call optimalizálható | **Rich** |
| `0xFE 0x16` | `constrained.` | `<token>` | 6 | Következő `callvirt` kényszerített típusra (generics) | **Rich** |
| `0xFE 0x19` | `no.` | `<ui1>` | 3 | Következő utasítás ellenőrzéseinek kihagyása (typecheck/null/range) | **Rich** |

---

## 16. Egyéb 0xFE prefix utasítások

| Hex | Mnemonic | Operandus | Hossz | Verem | Leírás | Státusz |
|-----|----------|-----------|-------|-------|--------|---------|
| `0xFE 0x00` | `arglist` | — | 2 | … → …, arglist | Varargs argumentumlista handle | **Skip** |
| `0xFE 0x1C` | `sizeof` | `<token>` | 6 | … → …, n | Típus byte-mérete (AOT-ban fordítási idejű konstans) | **Rich** |

> **Skip — arglist:** C-stílusú varargs (`__arglist`); Roslyn modern C#-ból soha nem generálja.

---

## Összefoglaló

| Státusz | Darab | Megjegyzés |
|---------|-------|-----------|
| **T0** | 64 | Implementálva F3-ban (`src/CilCpu.Sim/TOpcode.cs`) |
| **Rich** | ~145 | F5-ben tervezett (teljes ECMA-335) |
| **Skip** | 7 | Legacy / Roslyn nem generálja |
| **Összesen** | ~216 | — |

> **T0 darabszám:** Az ISA-CIL-T0 spec v1.0 48-at jelölt meg; az F1.5 implementáció 64-re bővült (ldc.i4.0–8 rövidalak-sorozat + starg.s + ldloc.s/stloc.s kiegészítések).

---

## Hivatkozások

- ECMA-335 — Common Language Infrastructure, Partition III: CIL Instruction Set
- `docs/ISA-CIL-T0-hu.md` — CIL-T0 részletes spec (Nano core, F3)
- `src/CilCpu.Sim/TOpcode.cs` — implementált T0 opkódok enum-ja
- `docs/roadmap-hu.md` — F5 Rich core tervezett opkód-lista
