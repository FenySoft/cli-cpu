---
status: draft
---

# CIL-Seal — ISA Specification

> Magyar verzió: [ISA-CIL-Seal-hu.md](ISA-CIL-Seal-hu.md)

> Version: 0.2 (draft)

This document specifies the **CIL-Seal** instruction set, which is the ISA for the Seal Core firmware. CIL-Seal is a **superset of CIL-T0**: all CIL-T0 opcodes are available, plus array handling and external hardware unit calls.

## Overview

The Seal Core firmware is **C# source code**, compiled by Roslyn into a .dll, linked by TCliCpuLinker (or its extended variant) into a CIL-Seal binary, and executed by the `TSealCpu` simulator. The firmware is burned into **mask ROM / eFuse** during chip fabrication — it cannot be modified at runtime.

### Design Principles

1. **Compiled by Roslyn** — the firmware originates from C# source code, built from Roslyn-generated CIL. No hand-written assembly.
2. **CIL-T0 compatible base** — all CIL-T0 opcodes work unchanged.
3. **Array support** — `byte[]` handling is required for cryptographic buffers (SHA-256 input/output, cert data).
4. **External call = HW unit** — `static extern` methods represent hardware accelerators (SHA-256, WOTS+, Merkle). In the simulator, these are software implementations.
5. **No GC** — arrays live on the heap, but there is no garbage collector. The firmware uses deterministic-lifetime buffers (alloc → use → discard at frame end).

## Memory Model

The Seal Core has 64 KB of SRAM, divided into two regions:

```
┌─────────────────────────────────┐ 0xFFFF (end of 64 KB)
│                                 │
│  Heap (grows top-down)          │
│  byte[] allocations             │
│                                 │
├─────────────── HP ──────────────┤
│         free space              │
├─────────────── SP ──────────────┤
│                                 │
│  Stack (grows bottom-up)        │
│  call frames + eval stack       │
│                                 │
└─────────────────────────────────┘ 0x0000
```

| Region | Direction | Contents |
|--------|-----------|----------|
| **Stack** | bottom-up | Call frames (header + args + locals + eval stack) — compatible with TCpu |
| **Heap** | top-down | Array objects (header + data) |

**Stack pointer (SP):** top of the stack, starts at 0, grows upward — identical to existing TCpu behavior.

**Heap pointer (HP):** next free heap address. Initially `SRAM_SIZE` (0xFFFF). `newarr` decrements HP **downward** (HP -= allocation size), then allocates at HP.

**Collision trap:** if `SP >= HP` (the stack and heap would collide), `SRAM_OVERFLOW` trap.

### Array Object Layout on the Heap

```
Offset   Size     Field
────────────────────────────────
0x00     4        Length (element count, int32)
0x04     Length   Data (byte array elements, packed)
         padding  rounded to 4-byte alignment
```

On the stack, an array is referenced by a **heap address** (int32) — this is the starting address of the array object layout on the heap.

**Null reference:** the value 0xFFFFFFFF represents null (the heap never grows this far). `ldelem`/`stelem`/`ldlen` on a null reference throws a `NULL_REFERENCE` trap.

## New Opcodes Compared to CIL-T0

### Array Opcodes

| Byte | Opcode | Length | Stack | Description |
|------|--------|--------|-------|-------------|
| `0x8D` | `newarr <token>` | 5 | `(I4 → ref)` | TOS = length; allocates a `length`-byte array on the heap; pushes the array's heap address. Token: ignored (always byte[]). |
| `0x8E` | `ldlen` | 1 | `(ref → I4)` | TOS = array ref; pushes the array's Length field. |
| `0x90` | `ldelem.u1` | 1 | `(ref, I4 → I4)` | TOS = index, TOS-1 = array ref; pushes `array[index]` as a zero-extended byte. |
| `0x9C` | `stelem.i1` | 1 | `(ref, I4, I4 →)` | TOS = value, TOS-1 = index, TOS-2 = array ref; `array[index] = (byte)value`. |

**Trap conditions:**

| Trap | Condition |
|------|-----------|
| `SRAM_OVERFLOW` | `newarr`: the heap and stack would collide |
| `NULL_REFERENCE` | `ldlen`/`ldelem`/`stelem`: ref == 0xFFFFFFFF |
| `INDEX_OUT_OF_RANGE` | `ldelem`/`stelem`: index < 0 or index >= length |
| `NEGATIVE_ARRAY_SIZE` | `newarr`: length < 0 |

### External Call (HW Unit Dispatch)

External methods use the standard `call` opcode (`0x28`), but the linker resolves them into a **special RVA range**:

```
Normal method RVA:     0x0000_0000 – 0xFFFE_FFFF
External HW dispatch:  0xFFFF_0000 – 0xFFFF_FFFF
```

When the CPU executes the `call` opcode and the target RVA >= `0xFFFF_0000`:
- It does **not** jump into the CODE region
- The lower 16 bits are the **HW unit dispatch index**
- The CPU looks up the appropriate HW unit from the dispatch table, executes it, and returns

### Linker Recognition — `[CryptoCall]` Attribute

Roslyn **does not generate an IL body** for `static extern` methods (RVA = 0 in the PE). Recognition is based on the `[CryptoCall(index)]` custom attribute:

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

The linker:
1. Recognizes: `MethodDef` with RVA == 0 (no IL body) **and** having a `[CryptoCall]` attribute
2. Reads the `DispatchIndex` value from the attribute's constructor argument
3. Writes the `call` token as `0xFFFF_0000 + DispatchIndex`

**Advantage:** the dispatch index is explicit in the source code — no string-based lookup, no ambiguity.

### HW Unit Dispatch Table (v0.1)

| Index | Dispatch RVA | C# Signature | HW Unit | Description |
|-------|--------------|--------------|---------|-------------|
| 0x0000 | `0xFFFF_0000` | `Sha256.Compute(byte[] AInput, int ALength) → byte[]` | SHA-256 | Computes the 32-byte SHA-256 hash |
| 0x0001 | `0xFFFF_0001` | `Sha256.ComputeBlock(byte[] AState, byte[] ABlock) → byte[]` | SHA-256 | Processes a single 64-byte block (pipeline) |
| 0x0002 | `0xFFFF_0002` | `WotsPlus.Verify(byte[] APublicKey, byte[] ASignature, byte[] AMessage) → int` | WOTS+ | WOTS+ signature verification. Return: 1=valid, 0=invalid |
| 0x0003 | `0xFFFF_0003` | `MerklePath.Verify(byte[] ARoot, byte[] ALeaf, byte[] APath, int AIndex) → int` | Merkle | Merkle tree path verification. Return: 1=valid, 0=invalid |

## Seal Core Specific Registers and States

### Internal State

| State | Type | Description |
|-------|------|-------------|
| PC | int32 | Program Counter — in the CODE (ROM) region |
| SP | int32 | Stack Pointer — top of the SRAM stack (top-down) |
| HP | int32 | Heap Pointer — next free heap address (bottom-up) |
| FP | int32 | Frame Pointer — base of the current frame |
| Halted | bool | Whether the core has halted |
| State | enum | Boot, SelfTest, Ready, Faulted |

### Seal Core State Machine

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

## Trap Types (CIL-T0 + Seal Extension)

All CIL-T0 traps are valid, plus:

| Trap # | Name | Description |
|--------|------|-------------|
| 0x0D | `NULL_REFERENCE` | ldlen/ldelem/stelem on null array reference |
| 0x0E | `INDEX_OUT_OF_RANGE` | Array index out of bounds |
| 0x0F | `NEGATIVE_ARRAY_SIZE` | newarr with negative size |
| 0x10 | `SRAM_OVERFLOW` | Heap and stack collide |
| 0x11 | `INVALID_EXTERNAL_CALL` | Unknown dispatch index |

## CIL-Seal Binary Format

Identical to the CIL-T0 binary format (`.t0` header, method headers), except:

- **Magic:** `"TSCL"` (0x4C 0x43 0x53 0x54) — distinguishes "T0 Seal"
- **Version:** 0x0002
- `call` tokens may contain `0xFFFF_xxxx` values (external dispatch)

## The Firmware as a C# Project

```csharp
// Entry point for the Seal Core firmware
public static class SealFirmware
{
    // Entry point — starts from the beginning of ROM (RVA = 0x0000)
    public static void Boot()
    {
        // 1. Self-test
        if (!SelfTest())
        {
            Trap.Fault();
            return;
        }

        // 2. Ready loop — receiving .acode containers
        while (true)
        {
            // Read from mailbox, AuthCode verify, code-load
        }
    }

    private static bool SelfTest()
    {
        // SHA-256 unit test: known input → known output
        byte[] testInput = new byte[] { 0x61, 0x62, 0x63 }; // "abc"
        byte[] hash = Sha256.Compute(testInput, 3);

        // Expected: BA7816BF 8F01CFEA 414140DE 5DAE2223
        //           B00361A3 96177A9C B410FF61 F20015AD
        return hash[0] == 0xBA && hash[1] == 0x78; // ...etc
    }
}

// External HW unit declarations — with [CryptoCall] attribute
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

## Decided Questions

1. **Stack direction** — bottom-up, compatible with the existing TCpu simulator. The heap grows top-down, they grow toward each other.
2. **External call marking** — `[CryptoCall(index)]` custom attribute on `static extern` methods. The dispatch index is explicit in the source code, the linker reads it from the metadata custom attribute.
3. **Cell size: 16B header + max 128B payload = max 144 bytes** — per the interconnect spec (v3.1): fixed buffer, variable link occupancy (see `interconnect-en.md` v3.1, `specs/cell-format-en.md`, `decision-bus-rollback-en.md`). The 128-byte payload is the v3.1 default: the 16-byte header is exactly 1 flit on the 128-bit L0 bus (no padding waste), the payload matches the DDR5 BL32 (128-byte) native burst, and a typical — small — actor message fits in a single cell. Code-load throughput is solved with multi-cell streaming (16 KB method = 128 cells × 128B payload, pipelined). ML-Max uses its own systolic router, not the main mesh.

## Open Questions

1. **Heap GC** — the firmware is small and deterministic, so we can manage the heap as an "arena allocator" (reset at boot or per task). Is a `free` mechanism needed?
2. **byte[] vs int32[]** — the current CIL-T0 is int32-only. Introducing `byte[]` requires at minimum `ldelem.u1` and `stelem.i1` opcodes. Is `int[]` also needed (e.g., for hash state)?
3. **newarr token** — Roslyn's `newarr` opcode takes a type token. How should the linker handle this? Proposal: ignore it (always treat as byte[]), or distinguish byte[]/int[] types.
4. **External call return value** — `byte[] Compute(...)` returns a heap-allocated array. Who allocates: the HW unit (the simulator allocates on the heap itself and returns the address), or the firmware explicitly prepares a buffer with `newarr`, and the HW unit writes into it?

## Related Documents

- `docs/ISA-CIL-T0-hu.md` — the CIL-T0 base ISA (48 opcodes)
- `docs/sealcore-hu.md` — the Seal Core architecture and role
- `docs/authcode-hu.md` — the AuthCode mechanism executed by the firmware
- `docs/quench-ram-hu.md` — the QRAM memory cell (SEAL/RELEASE trigger)

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 0.1 | 2026-04-20 | Initial draft. CIL-T0 superset: array opcodes (newarr, ldlen, ldelem.u1, stelem.i1), external call dispatch (SHA-256, WOTS+, Merkle), heap memory model, Seal Core state machine. |
| 0.2 | 2026-06-01 | **Cell format updated v2.0 → v3.1** (Decided Questions, item 3). The previous 16B + 64B = 80B (v2.0) cell was two versions stale; the current interconnect spec is v3.1: **16B header + max 128B payload = max 144B**. The rationale was rewritten with the v3.1 arguments (header = 1 flit on the 128-bit L0 bus, DDR5 BL32 alignment, multi-cell streaming code-load). The unsupported, circularly-referenced "~80% ≤48 bytes" distribution figure was removed (not measured data). Cascade fix from the v3.1 bus-rollback propagation. |
