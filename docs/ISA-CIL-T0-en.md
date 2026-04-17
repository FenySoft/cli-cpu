# CIL-T0 — ISA Specification

> Magyar verzió: [ISA-CIL-T0-hu.md](ISA-CIL-T0-hu.md)

> Version: 1.1

This document specifies the **CIL-T0** subset, which is the first implemented instruction set of CLI-CPU, targeted for **Tiny Tapeout (F3)** fabrication.

## Overview

CIL-T0 is a **strict, bit-for-bit compatible subset** of ECMA-335 CIL. Every CIL-T0 opcode uses the same byte encoding and the same stack semantics as the standard CIL opcode. This means a CIL-T0 program can be inspected with **any standard CIL disassembler** (e.g. `ildasm`, `dnSpy`), and **any standard CIL runtime** (CoreCLR, Mono, nanoFramework) could execute it — but the reverse is not true: an arbitrary .NET program running under CoreCLR will not run on CIL-T0, because most real-world programs use objects, strings, virtual calls, and exceptions, none of which CIL-T0 **implements**.

### Goals

1. **Minimal** — must fit within a Tiny Tapeout 12–16 tile budget (~12K–16K gate, ~1K gate/tile).
2. **Complete** for integer-only, static-call programs — a Fibonacci, a GCD, an integer bubble-sort must be runnable.
3. **Strictly standard** — no custom opcodes; everything derives from ECMA-335.
4. **Hardware safety even at F0** — stack overflow/underflow, branch target, local index bounds all trigger a hardware trap.
5. **TDD-friendly** — every opcode is unambiguously specified; simulator tests map one-to-one.

### What is NOT in CIL-T0

| Missing feature | Reason | When it arrives |
|----------------|--------|-----------------|
| Object model (class, struct field) | No metadata walker, no heap allocator | F4 |
| Garbage collection | No heap | F4 |
| Virtual call, interface | No vtable cache | F4 |
| Arrays | No bounds-check hardware or allocator | F4 |
| String | No intern table or heap | F4 |
| Floating point (R4, R8) | FPU area | F5 |
| 64-bit integer | Double-width area | F5 |
| Exception handling (try/catch) | No shadow register file | F5 |
| Generics | Metadata complexity | F5 |
| Delegate | No method reference model | F5 |
| Thread synchronization (volatile., etc.) | Single core, no SMP | F6+ |

## Memory model

The **narrowed variant** of the `docs/architecture.md` memory model applies to CIL-T0:

| Region | Address range | Contents | Backing | Size (F3) |
|--------|--------------|----------|---------|-----------|
| **CODE** | `0x0000_0000` – `0x000F_FFFF` | CIL bytecode (.cil-t0 binary format) | QSPI Flash | 1 MB |
| **DATA** | `0x1000_0000` – `0x1003_FFFF` | `.data` segment (constants, static fields) | QSPI Flash / PSRAM | 256 KB |
| **STACK** | `0x2000_0000` – `0x2000_3FFF` | Eval stack + locals + args + frames | QSPI PSRAM | 16 KB |
| **MMIO** | `0xF000_0000` – `0xFFFF_FFFF` | UART, **Mailbox**, GPIO, timer | On-chip | — |

**No HEAP** in CIL-T0, because there is no `newobj`/`newarr`.

### Detailed MMIO region map

The MMIO region starting at `0xF000_0000` is divided into blocks. In F3 only UART and Mailbox are implemented; the rest are reservations for future phases:

| Address | Size | Block | Phase |
|---------|------|-------|-------|
| `0xF000_0000` – `0xF000_00FF` | 256 B | UART (TX/RX/status/control) | F3 |
| `0xF000_0100` – `0xF000_01FF` | 256 B | **Mailbox (inbox + outbox)** | **F3** |
| `0xF000_0200` – `0xF000_02FF` | 256 B | GPIO (reserved) | F4 |
| `0xF000_0300` – `0xF000_03FF` | 256 B | Timer / clock (reserved) | F4 |
| `0xF000_0400` – `0xFFFF_FFFF` | — | Reserved | F5+ |

## Mailbox interface (F3)

The CLI-CPU includes a **32-bit mailbox interface already on the F3 Tiny Tapeout chip**, enabling the chip to **receive messages** from the outside world and **send messages** back in an event-driven manner. This is the first interface that lays the groundwork for the **cognitive fabric** positioning — F3 is single-core, yet it already fulfills the role of a "network-connectable node."

### Design principles

1. **No new opcodes.** The mailbox lives in the MMIO region and is accessed via the existing `ldind.i4` (load indirect) and `stind.i4` (store indirect) opcodes. This keeps the CIL-T0 opcode set at **48 opcodes** and strictly ECMA-335 compatible.
2. **Symmetric inbox and outbox.** Both FIFOs are **8 deep** with 32-bit wide entries. This can buffer 8 "spike" bursts in each direction without message loss.
3. **External bridge in F3** (UART/FTDI) relays messages between host and chip. **In F4** the same registers connect to the hardware router, and the `target` field gains meaning (destination core index).
4. **Trap support.** If the program attempts to read from an empty inbox or write to a full outbox, the hardware signals this via the `STATUS` register; optionally an **interrupt/wake-from-sleep** can also be generated (F4+).

### Register map

| Address | Reg | R/W | Description |
|---------|-----|-----|-------------|
| `0xF000_0100` | `MB_STATUS` | R | **Status**: bit 0 = inbox has message, bit 1 = inbox full, bit 2 = outbox empty, bit 3 = outbox full, bit 4 = inbox overflow sticky, bit 5 = outbox overflow sticky, bit 6–7 = reserved, bit 8–11 = inbox count (0–8), bit 12–15 = outbox count (0–8) |
| `0xF000_0104` | `MB_DATA` | R/W | **Data**: read = pop from the top of the inbox FIFO; write = push to the bottom of the outbox FIFO |
| `0xF000_0108` | `MB_TARGET` | R/W | **Target**: the destination of the **last** outbox push. In F3: 0 = external (UART bridge), all other values reserved. F4+: destination core index (0–N–1) |
| `0xF000_010C` | `MB_SOURCE` | R | **Source**: the origin of the **last** inbox pop. In F3 always 0 (external). F4+: sender core index |
| `0xF000_0110` | `MB_CTRL` | R/W | **Control**: bit 0 = clear inbox overflow sticky, bit 1 = clear outbox overflow sticky, bit 2 = enable inbox-wake interrupt (F4+), bit 3 = flush outbox (resync F3 UART bridge), bit 4–31 = reserved |
| `0xF000_0114` – `0xF000_01FF` | — | — | Reserved |

### Usage example in CIL-T0

This sample is a simple "echo neuron": it waits for an incoming message, adds 1, and sends it back.

```
; receive_add_send() — infinite loop
.method static void receive_add_send()
{
    .maxstack 3
    .locals init (int32 V_msg)

POLL:
    ldc.i4      0xF0000100                 ; MB_STATUS address
    ldind.i4                                ; status value onto TOS
    ldc.i4.1                                ; bit 0 mask (inbox has message)
    and
    brfalse.s   POLL                        ; if no message, keep polling

    ; --- read message ---
    ldc.i4      0xF0000104                 ; MB_DATA address
    ldind.i4                                ; pop inbox -> TOS
    ldc.i4.1
    add                                     ; +1
    stloc.0                                 ; V_msg = received+1

    ; --- set target (F3: 0 = external) ---
    ldc.i4      0xF0000108                 ; MB_TARGET address
    ldc.i4.0
    stind.i4

    ; --- outbox push ---
    ldc.i4      0xF0000104                 ; MB_DATA address
    ldloc.0
    stind.i4                                ; push outbox

    br.s        POLL
}
```

This handful of CIL-T0 lines is **already runnable on F3 silicon**, and it **demonstrates the cognitive fabric concept**: an external test host sends a message over UART, the chip processes it with a CIL program, and sends it back. This is the first "hold-in-your-hand, network-connected neuron" demo.

### Trap addendum

An optional trap is added to the current trap list (see above) in F3:

| Trap # | Name | Description |
|--------|------|-------------|
| 0x0C | `MAILBOX_OVERFLOW` | Fired when the program attempts to write to a full outbox and `MB_CTRL` does not enable drop behavior (configurable in F4+) |

In F3, by default **overflow only sets a sticky bit** and does not trap — the sample code can handle this via `MB_STATUS` polling.

### Hardware size estimate

Estimated size of the mailbox block on Sky130:

| Component | Std cell |
|-----------|----------|
| 8 x 32-bit inbox FIFO | ~120 |
| 8 x 32-bit outbox FIFO | ~120 |
| Status/Ctrl registers + decoding | ~80 |
| UART bridge (F3) | ~50 (shared from existing UART) |
| **Mailbox total** | **~370** |

This is a **~4% increase** over the CIL-T0 ~8700 std cell budget, and it **fits** within the 12–16 Tiny Tapeout tile configuration. **The total estimated F3 size is now ~9100 std cell.**

## Stack semantics

CIL-T0 operates as a stack machine with **32-bit wide** stack elements (`I4` type).

- **Evaluation stack:** max 64 elements deep. Spills to the frame in the STACK region as needed.
- **Local variables:** max 16 per method (`ldloc.0..3`, `ldloc.s 4..15`).
- **Arguments:** max 16 per method (`ldarg.0..3`, `ldarg.s 4..15`).
- **Top-of-Stack Cache:** 4 elements (F3 Tiny Tapeout), i.e. TOS, TOS-1, TOS-2, TOS-3 reside in physical registers.

Every stack element is of type **`I4` (32-bit signed integer)**. There are no other types in CIL-T0.

## Calling convention

- **Parameters:** the caller pushes them onto the evaluation stack before the call.
- **Frame:** the `call` microcode builds it automatically:
  ```
    return PC
    saved BP
    saved SP
    arg 0
    arg 1
    ...
    local 0
    local 1
    ...
    (eval stack bottom grows here)
  ```
- **Return value:** before `ret`, the method pushes the return value onto TOS; `ret` preserves it and tears down the frame.
- **Max frame size:** 256 bytes (in F3), which allows max 16 args + 16 locals + 32 eval stack slots.

## Opcode catalog

The following 48 opcodes constitute the complete CIL-T0 instruction set. Every opcode uses the **standard ECMA-335 byte encoding**.

### Legend

- **Byte(s)** — opcode byte(s), per the CIL standard. Two bytes when the `0xFE` prefix is used.
- **Operand** — the immediate byte(s) following the opcode, if any.
- **Length** — total opcode length in bytes.
- **Stack** — stack effect: `(-> I4)` pushes one int32, `(I4, I4 -> I4)` pops two int32s and pushes one, `(I4 ->)` pops one to nothing, etc.
- **μstep** — microcode ROM step count (`o_nsteps`): how many ROM lookups the sequencer performs. This number is **deterministic and cocotb-tested** (`rtl/tb/test_microcode.py`).
- **Cycles** — total execution time in clock cycles at 50 MHz, assuming TOS cache hit. Equals μstep + ALU latency + pipeline flush. `mul`/`div`/`rem` are longer due to iterative ALU. Branch opcodes add +1 pipeline flush cycle when taken.
- **Dec.** — `HW` = hardwired (1 μstep), `uC` = microcoded (>1 μstep or ALU iteration).
- **Trap** — possible hardware trap conditions.

### 1. Constant loading

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x14` | `ldnull` | 1 | `(-> I4)` | 1 | 1 | HW | Push 0 (null as int). |
| `0x15` | `ldc.i4.m1` | 1 | `(-> I4)` | 1 | 1 | HW | Push -1. |
| `0x16` | `ldc.i4.0` | 1 | `(-> I4)` | 1 | 1 | HW | Push 0. |
| `0x17` | `ldc.i4.1` | 1 | `(-> I4)` | 1 | 1 | HW | Push 1. |
| `0x18` | `ldc.i4.2` | 1 | `(-> I4)` | 1 | 1 | HW | Push 2. |
| `0x19` | `ldc.i4.3` | 1 | `(-> I4)` | 1 | 1 | HW | Push 3. |
| `0x1A` | `ldc.i4.4` | 1 | `(-> I4)` | 1 | 1 | HW | Push 4. |
| `0x1B` | `ldc.i4.5` | 1 | `(-> I4)` | 1 | 1 | HW | Push 5. |
| `0x1C` | `ldc.i4.6` | 1 | `(-> I4)` | 1 | 1 | HW | Push 6. |
| `0x1D` | `ldc.i4.7` | 1 | `(-> I4)` | 1 | 1 | HW | Push 7. |
| `0x1E` | `ldc.i4.8` | 1 | `(-> I4)` | 1 | 1 | HW | Push 8. |
| `0x1F` | `ldc.i4.s <sb>` | 2 | `(-> I4)` | 1 | 1 | HW | Push sign-extended 8-bit immediate. |
| `0x20` | `ldc.i4 <i4>` | 5 | `(-> I4)` | 1 | 1 | HW | Push 32-bit immediate. |

**Trap:** Stack overflow (when the eval stack reaches max depth of 64).

### 2. Local variable access

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x06` | `ldloc.0` | 1 | `(-> I4)` | 1 | 1 | HW | Push local[0]. |
| `0x07` | `ldloc.1` | 1 | `(-> I4)` | 1 | 1 | HW | Push local[1]. |
| `0x08` | `ldloc.2` | 1 | `(-> I4)` | 1 | 1 | HW | Push local[2]. |
| `0x09` | `ldloc.3` | 1 | `(-> I4)` | 1 | 1 | HW | Push local[3]. |
| `0x11` | `ldloc.s <ub>` | 2 | `(-> I4)` | 1 | 1 | HW | Push local[ub], 0 <= ub <= 15. |
| `0x0A` | `stloc.0` | 1 | `(I4 ->)` | 1 | 1 | HW | Pop -> local[0]. |
| `0x0B` | `stloc.1` | 1 | `(I4 ->)` | 1 | 1 | HW | Pop -> local[1]. |
| `0x0C` | `stloc.2` | 1 | `(I4 ->)` | 1 | 1 | HW | Pop -> local[2]. |
| `0x0D` | `stloc.3` | 1 | `(I4 ->)` | 1 | 1 | HW | Pop -> local[3]. |
| `0x13` | `stloc.s <ub>` | 2 | `(I4 ->)` | 1 | 1 | HW | Pop -> local[ub], 0 <= ub <= 15. |

**Trap:** Stack underflow (pop from empty stack), Local index out of range (ub >= 16 -> `INVALID_LOCAL` trap).

### 3. Argument access

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x02` | `ldarg.0` | 1 | `(-> I4)` | 1 | 1 | HW | Push arg[0]. |
| `0x03` | `ldarg.1` | 1 | `(-> I4)` | 1 | 1 | HW | Push arg[1]. |
| `0x04` | `ldarg.2` | 1 | `(-> I4)` | 1 | 1 | HW | Push arg[2]. |
| `0x05` | `ldarg.3` | 1 | `(-> I4)` | 1 | 1 | HW | Push arg[3]. |
| `0x0E` | `ldarg.s <ub>` | 2 | `(-> I4)` | 1 | 1 | HW | Push arg[ub], 0 <= ub <= 15. |
| `0x10` | `starg.s <ub>` | 2 | `(I4 ->)` | 1 | 1 | HW | Pop -> arg[ub], 0 <= ub <= 15. |

**Trap:** Stack underflow, `INVALID_ARG` if ub >= 16 or ub >= actual arg count.

### 4. Stack manipulation

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x00` | `nop` | 1 | `(->)` | 1 | 1 | HW | No operation. |
| `0x25` | `dup` | 1 | `(I4 -> I4, I4)` | 1 | 1 | HW | Duplicate TOS. |
| `0x26` | `pop` | 1 | `(I4 ->)` | 1 | 1 | HW | Discard TOS. |

**Trap:** Stack overflow (dup), stack underflow (pop, dup).

### 5. Arithmetic (integer)

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x58` | `add` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 + TOS, wrap. |
| `0x59` | `sub` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 - TOS, wrap. |
| `0x5A` | `mul` | 1 | `(I4, I4 -> I4)` | 1 | 4–8 | uC | TOS-1 x TOS. Iterative shift-add multiplier, 3–7 ALU latency cycles. |
| `0x5B` | `div` | 1 | `(I4, I4 -> I4)` | 1 | 16–32 | uC | TOS-1 / TOS signed. Restoring divider (32 iterations), 15–31 ALU latency cycles. |
| `0x5D` | `rem` | 1 | `(I4, I4 -> I4)` | 1 | 16–32 | uC | TOS-1 % TOS signed. Restoring divider (32 iterations), 15–31 ALU latency cycles. |
| `0x65` | `neg` | 1 | `(I4 -> I4)` | 1 | 1 | HW | -TOS. |
| `0x66` | `not` | 1 | `(I4 -> I4)` | 1 | 1 | HW | ~TOS. |
| `0x5F` | `and` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 & TOS. |
| `0x60` | `or` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 \| TOS. |
| `0x61` | `xor` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 ^ TOS. |
| `0x62` | `shl` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 << (TOS & 31). |
| `0x63` | `shr` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 >> (TOS & 31), sign-extend. |
| `0x64` | `shr.un` | 1 | `(I4, I4 -> I4)` | 1 | 1 | HW | TOS-1 >> (TOS & 31), zero-extend. |

**Trap:** Stack underflow, `DIV_BY_ZERO` (if `div`/`rem` and TOS == 0), `OVERFLOW` (only for `div`, if TOS-1 == INT_MIN and TOS == -1).

### 6. Comparison

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0xFE 0x01` | `ceq` | 2 | `(I4, I4 -> I4)` | 1 | 1 | HW | 1 if TOS-1 == TOS, else 0. |
| `0xFE 0x02` | `cgt` | 2 | `(I4, I4 -> I4)` | 1 | 1 | HW | 1 if TOS-1 > TOS signed. |
| `0xFE 0x03` | `cgt.un` | 2 | `(I4, I4 -> I4)` | 1 | 1 | HW | 1 if TOS-1 > TOS unsigned. |
| `0xFE 0x04` | `clt` | 2 | `(I4, I4 -> I4)` | 1 | 1 | HW | 1 if TOS-1 < TOS signed. |
| `0xFE 0x05` | `clt.un` | 2 | `(I4, I4 -> I4)` | 1 | 1 | HW | 1 if TOS-1 < TOS unsigned. |

**Trap:** Stack underflow.

### 7. Branching (short and long)

CIL-T0 only implements **short** branches in F3 (8-bit offset) to reduce hardware requirements. **Long** variants (32-bit offset) become available from F4 onward.

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x2B` | `br.s <sb>` | 2 | `(->)` | 1 | 1+1 | HW | PC += sb (signed 8-bit). +1 pipeline flush. |
| `0x2C` | `brfalse.s <sb>` | 2 | `(I4 ->)` | 1 | 1/1+1 | HW | If TOS == 0, PC += sb. Taken: +1 flush. |
| `0x2D` | `brtrue.s <sb>` | 2 | `(I4 ->)` | 1 | 1/1+1 | HW | If TOS != 0, PC += sb. Taken: +1 flush. |
| `0x2E` | `beq.s <sb>` | 2 | `(I4, I4 ->)` | 1 | 1/1+1 | HW | If TOS-1 == TOS, PC += sb. ALU ceq + cond. |
| `0x2F` | `bge.s <sb>` | 2 | `(I4, I4 ->)` | 1 | 1/1+1 | HW | If TOS-1 >= TOS, PC += sb. ALU clt + !cond. |
| `0x30` | `bgt.s <sb>` | 2 | `(I4, I4 ->)` | 1 | 1/1+1 | HW | If TOS-1 > TOS, PC += sb. ALU cgt + cond. |
| `0x31` | `ble.s <sb>` | 2 | `(I4, I4 ->)` | 1 | 1/1+1 | HW | If TOS-1 <= TOS, PC += sb. ALU cgt + !cond. |
| `0x32` | `blt.s <sb>` | 2 | `(I4, I4 ->)` | 1 | 1/1+1 | HW | If TOS-1 < TOS, PC += sb. ALU clt + cond. |
| `0x33` | `bne.un.s <sb>` | 2 | `(I4, I4 ->)` | 1 | 1/1+1 | HW | If TOS-1 != TOS, PC += sb. ALU ceq + !cond. |

**Trap:** Stack underflow, `INVALID_BRANCH_TARGET` (if the target address falls outside the method's code range).

### 8. Call and return

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x28` | `call <token>` | 5 | `(args -> ret)` | 2 | 2+N | uC | Static call. 2 ROM steps + N arg pop (sequencer loop). N = callee arg_count. |
| `0x2A` | `ret` | 1 | `(ret ->)` | 2 | 2 | uC | Return to caller. Step 0: conditional pop (cond_pop), step 1: frame_pop/halt + PC=ret. |

**CIL-T0 deviation from the standard:** In ECMA-335, the `call` token must resolve to a metadata table entry (MethodDef token). **In CIL-T0** there is no metadata walker, so the **call token is directly an RVA** (Relative Virtual Address) into the CODE region. The CIL-T0 binary format (see below) contains pre-linked RVAs. This simplifies `call` to a pure machine call and eliminates the need for a metadata walker.

**Trap:** Stack underflow (not enough args), stack overflow, `INVALID_CALL_TARGET` (if the RVA falls outside the CODE region), max call depth reached (512).

### 9. Indirect memory access

CIL-T0 implements the 32-bit integer indirect load/store opcodes, which access the `DATA` and `MMIO` regions (or the provided data memory array in the F1 simulator). The byte values are **strictly per ECMA-335 Partition III**, so a standard CIL disassembler will recognize them.

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0x4A` | `ldind.i4` | 1 | `(I4 -> I4)` | 1 | 1–3 | HW | TOS = address; pop, read a 32-bit LE int from data memory, push the result. +QSPI/PSRAM latency. |
| `0x54` | `stind.i4` | 1 | `(I4, I4 ->)` | 1 | 1–3 | HW | TOS = value, TOS-1 = address; pop value, pop address, write a 32-bit LE int to data memory. +QSPI/PSRAM latency. |

**Trap:** Stack underflow, `INVALID_MEMORY_ACCESS` (if the address falls outside the data memory range or no data memory is assigned to the CPU). This trap corresponds to a hardware memory controller fault in the F2 RTL.

### 10. Miscellaneous

| Byte | Opcode | Length | Stack | μstep | Cycles | Dec. | Description |
|------|--------|--------|-------|-------|--------|------|-------------|
| `0xDD` | `break` | 1 | `(->)` | 1 | 1 | HW | Debug trap. Halts and signals via UART. |

**CIL-T0 deviation from the standard:** In ECMA-335, the `break` opcode byte value is `0x01`. CIL-T0 uses `0xDD` instead, because `0x01` is adjacent to `nop` (`0x00`) from the F2/F3 decoder's perspective, and it was intentionally moved to the "rare, debug-only" range so it can be separated from hot opcodes in the decoder. This is a **deliberate deviation** that CIL-T0 to standard CIL translators (`ilasm-t0`) handle automatically.

## Opcodes that CANNOT be used in CIL-T0

If the decoder encounters an opcode byte value not present in the tables above, the hardware generates an **`INVALID_OPCODE` trap**. This is part of the security model: a malicious binary will not run "randomly."

## Trap types

CIL-T0 defines the following hardware traps:

| Trap # | Name | Description |
|--------|------|-------------|
| 0x01 | `STACK_OVERFLOW` | Eval stack reaches max depth (64 slots) |
| 0x02 | `STACK_UNDERFLOW` | Pop from empty stack |
| 0x03 | `INVALID_OPCODE` | Unknown opcode byte |
| 0x04 | `INVALID_LOCAL` | Local index >= 16 or >= actual local count |
| 0x05 | `INVALID_ARG` | Arg index >= 16 or >= actual arg count |
| 0x06 | `INVALID_BRANCH_TARGET` | Branch target outside the method's code range |
| 0x07 | `INVALID_CALL_TARGET` | Call RVA outside the CODE region |
| 0x08 | `DIV_BY_ZERO` | `div`/`rem` with zero divisor |
| 0x09 | `OVERFLOW` | `div` INT_MIN / -1 |
| 0x0A | `CALL_DEPTH_EXCEEDED` | Call depth >= 512 |
| 0x0B | `DEBUG_BREAK` | `break` opcode |
| 0x0C | `INVALID_MEMORY_ACCESS` | `ldind.i4` / `stind.i4` address outside data memory range or no data memory present |

**Trap behavior in F3:** The CPU halts, outputs the trap number and PC over UART, then waits for reset. **In F5** traps will be transformed into CIL exception handlers (`throw System.InvalidOperationException`, etc.).

### Trap ordering (precedence)

When multiple trap conditions are met simultaneously, CIL-T0 hardware and the simulator resolve them in the following **fixed** order. This ordering is backwards-compatible with the F2 cocotb testbench.

1. **`INVALID_OPCODE`** — the decoder first checks opcode validity and operand presence (a truncated operand also yields `INVALID_OPCODE`). If this trap fires, no other conditions are evaluated, because the logical decoding of the instruction has not even completed.
2. **Index checks (`INVALID_LOCAL`, `INVALID_ARG`)** — for `stloc.s` / `starg.s` / `ldloc.s` / `ldarg.s` opcodes, the index check **precedes** stack access. Therefore, if the index is invalid AND the stack is empty simultaneously, `INVALID_LOCAL` (or `INVALID_ARG`) is the firing trap, NOT `STACK_UNDERFLOW`.
3. **`STACK_UNDERFLOW` / `STACK_OVERFLOW`** — evaluated after operands are popped from the stack, or before a push.
4. **Arithmetic traps (`DIV_BY_ZERO`, `OVERFLOW`)** — for `div`/`rem`, the divisor's zero value and the `INT_MIN / -1` overflow are checked only after the operands have been successfully popped.
5. **`INVALID_BRANCH_TARGET`** — for conditional branches, evaluated only after the condition is computed, and only if the branch actually fires. A non-taken branch never raises `INVALID_BRANCH_TARGET`, even if the target would be invalid.

**Index validation precedes stack access; invalid index takes precedence over stack underflow.**

## CIL-T0 binary format

Since the standard PE/COFF format is too complex for the CIL-T0 minimum (we do not want a metadata walker in F3), CIL-T0 uses a **custom, pre-linked binary format**:

```
Offset   Size   Field
─────────────────────────────────────────
0x00     4      Magic: "T0CL" (0x4C 0x43 0x30 0x54)
0x04     2      Version: 0x0001
0x06     2      Flags: reserved, 0
0x08     4      Entry point RVA (entry address in the CODE region)
0x0C     4      Code segment size bytes
0x10     4      Data segment size bytes
0x14     4      Code CRC32
0x18     4      Data CRC32
0x1C     4      Reserved
─────────────────────────────────────────
0x20     ...    Code segment (CIL bytes)
         ...    Data segment (constants)
```

**Method header within the code segment:**

```
Offset   Size   Field
─────────────────────────────────────────
0x00     1      Magic: 0xFE (standard CIL "fat" header marker)
0x01     1      arg_count (0..15)
0x02     1      local_count (0..15)
0x03     1      max_stack (0..64)
0x04     2      code_size bytes
0x06     2      Reserved
─────────────────────────────────────────
0x08     ...    CIL opcodes
```

A `.t0` file is therefore **self-contained**: a header followed by methods in sequence. The 4 bytes after the `call <token>` opcode byte represent the target method's **absolute CODE region offset**, not a PE token.

### Tool: `ilasm-t0`

In phase F1, a small compiler script (`tools/ilasm-t0.cs`) will be built:
- Input: an `.il` text file in ilasm format, or a Roslyn-compiled `.dll` with CIL-T0 subset.
- Output: a `.t0` binary in the format described above.
- Validates that the input uses only CIL-T0 opcodes, and pre-links `call` tokens to RVAs.

## Microcode sequences (complex opcodes)

### `mul` (iterative multiplication)

```
; Entry: TOS = b, TOS-1 = a
; Output: TOS-1 = a*b, TOS discarded

u01: RESULT <- 0
u02: if (b == 0) goto u07
u03: if (b & 1) RESULT <- RESULT + a
u04: a <- a << 1
u05: b <- b >>u 1
u06: goto u02
u07: TOS-1 <- RESULT
u08: pop
u09: END
```

~4–8 cycles, depending on the value of b.

### `div` (restoring division)

```
; Entry: TOS = divisor, TOS-1 = dividend
; Output: TOS-1 = dividend / divisor

u01: if (TOS == 0) TRAP #DIV_BY_ZERO
u02: if (TOS-1 == INT_MIN && TOS == -1) TRAP #OVERFLOW
u03: sign <- sign(TOS-1) ^ sign(TOS)
u04: a <- abs(TOS-1), b <- abs(TOS)
u05: q <- 0, r <- 0
u06: for i in 31..0:
         r <- (r << 1) | bit(a, i)
         if (r >= b) { r <- r - b; q <- q | (1 << i) }
u07: if sign: q <- -q
u08: TOS-1 <- q
u09: pop
u10: END
```

~16–32 cycles.

### `call`

```
; Entry: TOS..TOS-N = arguments (N = callee arg_count-1)
; operand: 4-byte absolute RVA in the CODE region

u01: TARGET <- FETCH4(PC+1)                         ; 4-byte RVA
u02: if TARGET >= CODE_SIZE TRAP #INVALID_CALL_TARGET
u03: read method header @ TARGET:
        arg_count, local_count, max_stack, code_size
u04: if SP + frame_size > STACK_LIMIT TRAP #STACK_OVERFLOW
u05: if CALL_DEPTH >= 512 TRAP #CALL_DEPTH_EXCEEDED
u06: SPILL TOS cache -> stack                        ; save local eval stack
u07: PUSH(PC + 5)                                    ; return PC
u08: PUSH(BP)
u09: PUSH(SP)
u10: BP <- SP
u11: reserve frame_size bytes on the stack
u12: pop args from caller stack, copy to arg area
u13: zero-init locals
u14: PC <- TARGET + 8 (past the header)
u15: END
```

~6–10 cycles, assuming cache hit.

### `ret`

```
; Entry: TOS = return value (optional)

u01: SAVE_RET <- TOS
u02: SP <- BP
u03: BP <- POP()                                    ; saved BP
u04: POP()                                          ; saved SP (discarded, SP <- from BP)
u05: RETURN_PC <- POP()
u06: discard callee arguments from the stack
u07: PC <- RETURN_PC
u08: PUSH(SAVE_RET) if applicable
u09: RELOAD TOS cache
u10: END
```

~4–6 cycles.

## Example: Fibonacci(n)

C# source:

```csharp
static int Fib(int n) {
    if (n < 2) return n;
    return Fib(n - 1) + Fib(n - 2);
}
```

CIL-T0 (abstract assembly, ilasm-style):

```
.method static int32 Fib(int32 n)
{
    .maxstack 3
    .locals init (int32 V_0)     // not used, but included for illustration

    ldarg.0                       ; 02
    ldc.i4.2                      ; 18
    bge.s L1                      ; 2F 04
    ldarg.0                       ; 02
    ret                           ; 2A
L1:
    ldarg.0                       ; 02
    ldc.i4.1                      ; 17
    sub                           ; 59
    call Fib                      ; 28 <RVA4>
    ldarg.0                       ; 02
    ldc.i4.2                      ; 18
    sub                           ; 59
    call Fib                      ; 28 <RVA4>
    add                           ; 58
    ret                           ; 2A
}
```

**Bytes** (with `call` tokens shown as `??` placeholders):

```
02 18 2F 04 02 2A 02 17 59 28 ?? ?? ?? ?? 02 18 59 28 ?? ?? ?? ?? 58 2A
```

This is **24 bytes** of CIL-T0. The same function in RISC-V RV32I would be ~60 bytes. The density advantage is evident.

**Execution of Fib(3), cycle count estimate:**
- Fib(3) -> 1 direct branch + 2 calls, which expand into Fib(2) and Fib(1)
- Fib(2) -> 1 call to Fib(1) + 1 call to Fib(0)
- Total: 7 function calls, ~15 total ALU/branch operations
- Order of magnitude: ~50–100 cycles at 50 MHz = ~1–2 us
- Same on x86-64 at 3 GHz with JIT: ~100 ns

**Conclusion:** a stack machine at 50 MHz is roughly 10–20x slower than a conventional CPU for Fibonacci. However, in the IoT use case, memory footprint and code size matter more than raw speed.

## F1 reference implementation notes

The F1 C# simulator (`src/CilCpu.Sim`) implements the behavior specified in this document in an **observationally equivalent** manner, but employs a few deliberate differences in internal data structures. These are **not specification violations**, because the CIL-T0 ISA specifies observable behavior (stack value, trap, return value, PC), not the internal implementation. The F2 RTL remains free to choose either approach as long as the behavior matches the simulator bit-for-bit.

### Per-frame evaluation stack

The `call` microcode (see above) describes a "SPILL TOS cache -> stack" step, which suggests a **shared** evaluation stack model: every frame operates on a common 64-deep stack, and on call the callee receives a new range above the current SP.

The **F1 reference simulator uses a per-frame evaluation stack instead**: each `TFrame` gets its own 64-deep `TEvaluationStack`. On `call`, the arguments are simply popped from the caller's eval stack, and the callee starts with an empty eval stack. On `ret`, the return value is taken from the top of the callee's eval stack and pushed onto the caller's.

**Observational equivalence.** The execution traces of the two models (PC, frame arguments, locals, return value, trap instant) **match bit-for-bit** for every program that does not rely on the "visibility" of the caller eval stack's values beyond TOS (i.e. non-argument values) from the callee — which would be invalid CIL anyway. The spec permits both behaviors.

**Traps are stricter in the per-frame model.** The `STACK_OVERFLOW` trap may fire sooner in the per-frame simulator than in the shared model: a given frame's eval stack can be at most 64 deep **on its own**, not "whatever remains of the shared 64." This is **stricter**, not more lenient, so anything that runs on the simulator will also run on the F2 shared model.

**F2 RTL decision.** The F2 RTL implementation is free to choose between the two models. If it adopts the shared approach (as described in the microcode text), the `STACK_OVERFLOW` precedence in the cocotb golden vector testbenches must be made configurable behind a flag so that the two golden execution traces continue to match.

### `Peek` API on the CPU

`TCpu.Peek(int)` is a debug/test API that reads from the current top frame's eval stack. If the call stack is empty (i.e. before `Execute` is called), it throws an `InvalidOperationException`, **not a CIL trap**, because Peek is not a CIL-T0 opcode operation. This behavior is fixed and tested.

## Estimated hardware size (Sky130, F3)

| Component | Estimate (std cell) |
|-----------|-------------------|
| Length decoder | 200 |
| Hardwired decoder (simple opcodes) | 1500 |
| Microcode ROM (mul, div, call, ret) | 1200 |
| uop sequencer | 400 |
| ALU (32-bit) | 800 |
| Stack cache (4 x 32-bit + spill logic) | 1000 |
| Load/store unit | 600 |
| QSPI controller (shared code+data) | 1500 |
| UART | 300 |
| Trap / reset logic | 400 |
| Register file (PC, SP, BP, flags) | 300 |
| Glue, clock, reset | 500 |
| **Total** | **~8700 std cell** |

This comfortably fits within **12–16 Tiny Tapeout tiles** (~1K gate/tile, ~12K–16K gate budget), leaving headroom for routing overhead and verification logic.

## F1 simulator test obligations

The F1 C# simulator tests must cover the following for **every** opcode:

1. **Happy path** — valid input, expected output.
2. **Stack underflow** — pop from empty stack.
3. **Stack overflow** — push beyond 64 depth.
4. **Trap conditions** — every trap type must be triggerable.
5. **Boundary tests** — e.g. `add` INT_MAX + 1 (wrap), `div` INT_MIN / -1 (overflow trap), `shr` on negative value.
6. **Integration test** — run a real program (Fibonacci, GCD, bubble sort) and verify the result.

Test name format: `[ClassName]_[Opcode]_[Scenario]`, e.g. `Executor_Add_WrapsAroundOnOverflow`.

## References

- **ECMA-335** — Common Language Infrastructure spec, 6th edition.
- **`docs/architecture.md`** — full CLI-CPU architecture
- **`docs/roadmap.md`** — phases and dependencies
- **Sky130 PDK** — https://skywater-pdk.readthedocs.io/
- **Tiny Tapeout** — https://tinytapeout.com/

## Clock cycle model (F2.2b)

The execution time of CIL-T0 instructions is determined by three factors:

1. **μstep** — the microcode ROM step count (`o_nsteps`). This is **deterministic** and verified by `rtl/tb/test_microcode.py` cocotb tests. Most opcodes are 1 μstep; `call` and `ret` are 2 μstep.

2. **ALU latency** — the cycle cost of the ALU's internal iterative logic. Simple operations (add, sub, and, or, xor, shl, shr, neg, not, ceq, cgt, clt) add 0 extra cycles (combinational ALU). `mul` adds 3–7 cycles (shift-add multiplier), `div`/`rem` add 15–31 cycles (restoring divider, 32 iterations).

3. **Pipeline and memory effects** — branch opcodes add +1 pipeline flush cycle when taken. `ldind.i4`/`stind.i4` opcodes may add +0–2 cycles for QSPI/PSRAM latency (on-chip SRAM: 0; QSPI flash: 1–2).

**Formula:** `Total cycles = μstep + ALU latency + pipeline flush + memory latency`

### Summary table (48 opcodes)

| Category | Opcodes | μstep | Cycles | Notes |
|----------|---------|-------|--------|-------|
| Constant load | ldnull, ldc.i4.* | 1 | 1 | — |
| Local/arg load | ldloc.*, ldarg.* | 1 | 1 | TOS cache hit |
| Local/arg store | stloc.*, starg.s | 1 | 1 | — |
| Stack manip. | nop, dup, pop | 1 | 1 | — |
| ALU simple | add, sub, and, or, xor, shl, shr, shr.un, neg, not | 1 | 1 | combinational ALU |
| ALU multiply | mul | 1 | 4–8 | iterative shift-add |
| ALU division | div, rem | 1 | 16–32 | restoring divider |
| Comparison | ceq, cgt, cgt.un, clt, clt.un | 1 | 1 | — |
| Branch unconditional | br.s | 1 | 1+1 | +1 pipeline flush |
| Branch 1-operand | brfalse.s, brtrue.s | 1 | 1/1+1 | +1 if taken |
| Branch 2-operand | beq.s..bne.un.s | 1 | 1/1+1 | ALU cmp + cond |
| Indirect load | ldind.i4 | 1 | 1–3 | +QSPI/PSRAM lat. |
| Indirect store | stind.i4 | 1 | 1–3 | +QSPI/PSRAM lat. |
| Call | call | 2 | 2+N | N = arg count |
| Return | ret | 2 | 2 | cond_pop + frame |
| Debug | break | 1 | 1 | trap, CPU halts |

**Source:** `rtl/src/cilcpu_microcode.v` — the μstep values are read from the `o_nsteps` output, and verified by the `rtl/tb/test_microcode.py` cocotb tests (24 tests, 0 failures).

---

## Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.1 | 2026-04-17 | F2.2b μstep + clock cycle documentation for all opcodes |
| 1.0 | 2026-04-14 | Initial version, translated from Hungarian |
