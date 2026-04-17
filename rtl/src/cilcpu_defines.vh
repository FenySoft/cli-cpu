// hu: CLI-CPU CIL-T0 globális konstansok — opkód byte-értékek, trap kódok,
//     SRAM frame layout offszetek. A C# szimulátor TCpu, TOpcode, TTrapReason
//     osztályaival konzisztens.
// en: CLI-CPU CIL-T0 global constants — opcode byte values, trap codes,
//     SRAM frame layout offsets. Consistent with C# simulator TCpu, TOpcode,
//     TTrapReason classes.

`ifndef CILCPU_DEFINES_VH
`define CILCPU_DEFINES_VH

// ============================================================
// SRAM és frame layout konstansok (TCpu.cs-ből)
// ============================================================

`define SRAM_SIZE_BYTES     16384   // 16 KB per Nano core
`define SRAM_ADDR_WIDTH     14      // log2(16384)
`define FRAME_HEADER_SIZE   12      // 12 byte header
`define OFF_RETURN_PC       0       // [FP+0]  ReturnPC (i32)
`define OFF_PREV_FRAME_BASE 4       // [FP+4]  PrevFrameBase (i32)
`define OFF_ARG_COUNT       8       // [FP+8]  ArgCount (u8)
`define OFF_LOCAL_COUNT     9       // [FP+9]  LocalCount (u8)

`define MAX_STACK_DEPTH     64      // max eval stack mélység
`define MAX_CALL_DEPTH      512     // max hívási mélység
`define MAX_ARGS            16      // max arg / metódus
`define MAX_LOCALS          16      // max local / metódus

// ============================================================
// Method header (TMethodHeader.cs-ből)
// ============================================================

`define METHOD_HEADER_MAGIC 8'hFE
`define METHOD_HEADER_SIZE  8       // 8 byte a code memory-ban

// ============================================================
// ALU műveletek (belső kódolás, NEM az opcode byte)
// ============================================================

`define ALU_ADD     5'd0
`define ALU_SUB     5'd1
`define ALU_MUL     5'd2
`define ALU_DIV     5'd3
`define ALU_REM     5'd4
`define ALU_AND     5'd5
`define ALU_OR      5'd6
`define ALU_XOR     5'd7
`define ALU_SHL     5'd8
`define ALU_SHR     5'd9
`define ALU_SHR_UN  5'd10
`define ALU_NEG     5'd11
`define ALU_NOT     5'd12
`define ALU_CEQ     5'd13
`define ALU_CGT     5'd14
`define ALU_CGT_UN  5'd15
`define ALU_CLT     5'd16
`define ALU_CLT_UN  5'd17

// ============================================================
// Trap kódok (TTrapReason.cs-ből, byte értékek)
// ============================================================

`define TRAP_NONE                8'h00
`define TRAP_STACK_OVERFLOW      8'h01
`define TRAP_STACK_UNDERFLOW     8'h02
`define TRAP_INVALID_OPCODE      8'h03
`define TRAP_INVALID_LOCAL       8'h04
`define TRAP_INVALID_ARG         8'h05
`define TRAP_INVALID_BRANCH      8'h06
`define TRAP_INVALID_CALL_TARGET 8'h07
`define TRAP_DIV_BY_ZERO         8'h08
`define TRAP_OVERFLOW            8'h09
`define TRAP_CALL_DEPTH_EXCEEDED 8'h0A
`define TRAP_DEBUG_BREAK         8'h0B
`define TRAP_INVALID_MEMORY      8'h0C
`define TRAP_SRAM_OVERFLOW       8'h0D

// ============================================================
// CIL-T0 opcode byte értékek (TOpcode.cs-ből)
// Egybyte-os opkódok: a byte értéke
// 0xFE prefixes: csak a második byte (a prefix kezelés a dekóderben)
// ============================================================

// -- Nop / Break --
`define OP_NOP          8'h00
`define OP_BREAK        8'hDD

// -- Argument betöltés --
`define OP_LDARG_0      8'h02
`define OP_LDARG_1      8'h03
`define OP_LDARG_2      8'h04
`define OP_LDARG_3      8'h05
`define OP_LDARG_S      8'h0E   // + 1 byte operandus

// -- Argument írás --
`define OP_STARG_S      8'h10   // + 1 byte operandus

// -- Lokális betöltés --
`define OP_LDLOC_0      8'h06
`define OP_LDLOC_1      8'h07
`define OP_LDLOC_2      8'h08
`define OP_LDLOC_3      8'h09
`define OP_LDLOC_S      8'h11   // + 1 byte operandus

// -- Lokális írás --
`define OP_STLOC_0      8'h0A
`define OP_STLOC_1      8'h0B
`define OP_STLOC_2      8'h0C
`define OP_STLOC_3      8'h0D
`define OP_STLOC_S      8'h13   // + 1 byte operandus

// -- Konstans betöltés --
`define OP_LDNULL       8'h14   // push 0
`define OP_LDC_I4_M1    8'h15   // push -1
`define OP_LDC_I4_0     8'h16
`define OP_LDC_I4_1     8'h17
`define OP_LDC_I4_2     8'h18
`define OP_LDC_I4_3     8'h19
`define OP_LDC_I4_4     8'h1A
`define OP_LDC_I4_5     8'h1B
`define OP_LDC_I4_6     8'h1C
`define OP_LDC_I4_7     8'h1D
`define OP_LDC_I4_8     8'h1E
`define OP_LDC_I4_S     8'h1F   // + 1 byte signed operandus
`define OP_LDC_I4       8'h20   // + 4 byte LE operandus

// -- Stack manipuláció --
`define OP_DUP          8'h25
`define OP_POP          8'h26

// -- Branch (rövid, 2 byte: opcode + signed offset) --
`define OP_BR_S         8'h2B
`define OP_BRFALSE_S    8'h2C
`define OP_BRTRUE_S     8'h2D
`define OP_BEQ_S        8'h2E
`define OP_BGE_S        8'h2F
`define OP_BGT_S        8'h30
`define OP_BLE_S        8'h31
`define OP_BLT_S        8'h32
`define OP_BNE_UN_S     8'h33

// -- Aritmetika (1 byte, operandus nélkül) --
`define OP_ADD          8'h58
`define OP_SUB          8'h59
`define OP_MUL          8'h5A
`define OP_DIV          8'h5B
`define OP_REM          8'h5D
`define OP_AND          8'h5F
`define OP_OR           8'h60
`define OP_XOR          8'h61
`define OP_SHL          8'h62
`define OP_SHR          8'h63
`define OP_SHR_UN       8'h64
`define OP_NEG          8'h65
`define OP_NOT          8'h66

// -- Call / Ret --
`define OP_CALL         8'h28   // + 4 byte RVA operandus
`define OP_RET          8'h2A

// -- Indirect memória --
`define OP_LDIND_I4     8'h4A
`define OP_STIND_I4     8'h54

// -- 0xFE prefix --
`define OP_PREFIX       8'hFE

// -- 0xFE prefixes: második byte értékek --
`define OP_FE_CEQ       8'h01
`define OP_FE_CGT       8'h02
`define OP_FE_CGT_UN    8'h03
`define OP_FE_CLT       8'h04
`define OP_FE_CLT_UN    8'h05

// ============================================================
// Microcode vezérlőszó mezőpozíciók (cilcpu_microcode.v)
// Microcode control word field positions (cilcpu_microcode.v)
// ============================================================

// hu: A 32 bites vezérlőszó mezői fentről lefelé.
// en: 32-bit control word fields, MSB to LSB.

`define UC_DONE         31      // utolsó mikrolépés / last micro-step
`define UC_TRAP         30      // trap generálás / raise trap
`define UC_TRAP_CODE_HI 29      // trap_code[3:0] felső bit / trap code high
`define UC_TRAP_CODE_LO 26      // trap_code[3:0] alsó bit / trap code low
`define UC_STACK_POP_HI 25      // stack_pop[1:0] / pop count
`define UC_STACK_POP_LO 24
`define UC_STACK_PUSH   23      // push engedélyezés / push enable
`define UC_PUSH_SRC_HI  22      // push_src[1:0] / push source
`define UC_PUSH_SRC_LO  21
`define UC_ALU_EN       20      // ALU engedélyezés / ALU enable
`define UC_ALU_OP_HI    19      // alu_op[4:0] / ALU operation
`define UC_ALU_OP_LO    15
`define UC_SRAM_RD      14      // SRAM olvasás / SRAM read
`define UC_SRAM_WR      13      // SRAM írás / SRAM write
`define UC_ADDR_SRC_HI  12      // addr_src[1:0] / address source
`define UC_ADDR_SRC_LO  11
`define UC_PC_WR        10      // PC frissítés / PC write
`define UC_PC_SRC_HI     9      // pc_src[1:0] / PC source
`define UC_PC_SRC_LO     8
`define UC_FRAME_PUSH    7      // call frame push
`define UC_FRAME_POP     6      // call frame pop
`define UC_HALT          5      // CPU megállítás / halt
`define UC_COND_EN       4      // feltételes branch / conditional branch
`define UC_COND_TYPE_HI  3      // cond_type[1:0] / condition type
`define UC_COND_TYPE_LO  2
`define UC_COND_SIGNED   1      // signed összehasonlítás / signed comparison
`define UC_COND_POP      0      // feltételes pop (csak ha eval depth > 0) / conditional pop (only if eval depth > 0)

// hu: push_src értékek — mi kerül a stack-re push-kor.
// en: push_src values — what gets pushed onto the stack.
`define PUSH_SRC_ALU    2'd0    // ALU eredmény / ALU result
`define PUSH_SRC_IMM    2'd1    // immediát/operandus / immediate/operand
`define PUSH_SRC_SRAM   2'd2    // SRAM olvasott adat / SRAM read data
`define PUSH_SRC_TOS    2'd3    // TOS másolat (dup) / TOS copy (dup)

// hu: pc_src értékek — honnan jön az új PC.
// en: pc_src values — source of the new PC.
`define PC_SRC_NEXT     2'd0    // PC + utasítás hossz / PC + instruction length
`define PC_SRC_BRANCH   2'd1    // PC + len + offset (branch target)
`define PC_SRC_CALL     2'd2    // operandus + header_size (call target)
`define PC_SRC_RET      2'd3    // mentett return PC / saved return PC

// hu: addr_src értékek — SRAM cím forrás.
// en: addr_src values — SRAM address source.
`define ADDR_SRC_ARG    2'd0    // argumentum slot / argument slot
`define ADDR_SRC_LOCAL  2'd1    // lokális slot / local slot
`define ADDR_SRC_FRAME  2'd2    // frame header / frame header
`define ADDR_SRC_IND    2'd3    // indirekt (TOS cím) / indirect (TOS address)

// hu: cond_type értékek — branch feltétel típus.
// en: cond_type values — branch condition type.
`define COND_EQ         2'd0    // == (beq / brfalse / ceq)
`define COND_NE         2'd1    // != (bne.un / brtrue)
`define COND_LT         2'd2    // < (blt)
`define COND_GE         2'd3    // >= (bge)

// hu: Segéd makrók a cond_type kódoláshoz — bgt = !(<=) = swap+lt,
//     ble = !(>) = swap+ge. A swap logika a sequencer-ben van.
// en: Helper notes for cond_type encoding — bgt = !(<=) = swap+lt,
//     ble = !(>) = swap+ge. The swap logic lives in the sequencer.

`endif
