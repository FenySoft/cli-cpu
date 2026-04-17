// hu: CLI-CPU CIL-T0 Microcode ROM — a TExecutor.cs végrehajtási logikájának
//     bit-tökéletes hardveres leképezése vezérlőszó (control word) formában.
//     Tiszta kombinációs logika (nincs órajel, nincs flip-flop). Minden CIL-T0
//     opkódhoz meghatározza a mikrolépés-sorozatot: melyik lépésben milyen
//     stack, ALU, SRAM, PC és frame művelet szükséges.
//     Ismeretlen opkód vagy az érvényes lépéstartományon túli step esetén
//     o_valid=0, o_ctrl=0.
// en: CLI-CPU CIL-T0 Microcode ROM — bit-perfect hardware mapping of the
//     TExecutor.cs execution logic as control words. Pure combinational logic
//     (no clock, no flip-flops). For every CIL-T0 opcode, defines the
//     micro-step sequence: which stack, ALU, SRAM, PC and frame operations
//     are needed at each step.
//     Unknown opcode or step beyond valid range yields o_valid=0, o_ctrl=0.
//
// ============================================================================
// hu: ÓRAJELCIKLUS TÁBLÁZAT — minden CIL-T0 opkód végrehajtási ideje
//     μstep = microcode ROM lépések száma (o_nsteps kimenet)
//     ALU lat = ALU belső latencia (iteratív mul/div esetén)
//     Σ ciklus = teljes végrehajtási idő (μstep + ALU latencia)
//     A pipeline flush (branch taken) +1 ciklust ad a branch opkódoknál.
// en: CLOCK CYCLE TABLE — execution time for every CIL-T0 opcode
//     μstep = microcode ROM step count (o_nsteps output)
//     ALU lat = ALU internal latency (for iterative mul/div)
//     Σ cycles = total execution time (μstep + ALU latency)
//     Pipeline flush (branch taken) adds +1 cycle to branch opcodes.
//
//  Opkód                μstep  ALU lat  Σ ciklus  Megjegyzés
//  ────────────────────  ─────  ───────  ────────  ──────────────────────────
//  nop                   1      0        1         —
//  ldarg.0..3, ldarg.s   1      0        1         SRAM read (TOS cache hit)
//  starg.s               1      0        1         SRAM write
//  ldloc.0..3, ldloc.s   1      0        1         SRAM read (TOS cache hit)
//  stloc.0..3, stloc.s   1      0        1         SRAM write
//  ldnull                1      0        1         push 0
//  ldc.i4.m1..8          1      0        1         push inline konstans
//  ldc.i4.s              1      0        1         push sign-ext immediate
//  ldc.i4                1      0        1         push 32-bit immediate
//  dup                   1      0        1         push TOS másolat
//  pop                   1      0        1         eldobás
//  add                   1      0        1         32-bit összeadás
//  sub                   1      0        1         32-bit kivonás
//  mul                   1      3–7      4–8       iteratív szorzó (shift-add)
//  div                   1      15–31    16–32     restoring osztó (32 iter.)
//  rem                   1      15–31    16–32     restoring maradék
//  and, or, xor          1      0        1         bitwise logika
//  shl, shr, shr.un      1      0        1         barrel shifter
//  neg, not              1      0        1         unáris ALU
//  ceq, cgt, cgt.un      1      0        1         összehasonlítás
//  clt, clt.un            1      0        1         összehasonlítás
//  br.s                  1      0        1+1       +1 pipeline flush
//  brfalse.s             1      0        1/1+1     +1 ha branch taken
//  brtrue.s              1      0        1/1+1     +1 ha branch taken
//  beq.s                 1      0        1/1+1     ALU ceq + cond branch
//  bge.s                 1      0        1/1+1     ALU clt + cond branch
//  bgt.s                 1      0        1/1+1     ALU cgt + cond branch
//  ble.s                 1      0        1/1+1     ALU cgt + cond branch
//  blt.s                 1      0        1/1+1     ALU clt + cond branch
//  bne.un.s              1      0        1/1+1     ALU ceq + cond branch
//  ldind.i4              1      0        1–3       +QSPI/PSRAM latencia
//  stind.i4              1      0        1–3       +QSPI/PSRAM latencia
//  call                  2      0        2+N       N = arg count (seq. loop)
//  ret                   2      0        2         cond_pop + frame_pop/halt
//  break                 1      0        1         trap (CPU megáll)
// ============================================================================

`include "cilcpu_defines.vh"

module cilcpu_microcode (
    input  wire [15:0] i_opcode,    // hu: dekódolt opkód / en: decoded opcode
    input  wire [3:0]  i_step,      // hu: mikrolépés számláló (0..15) / en: micro-step counter
    output reg  [31:0] o_ctrl,      // hu: vezérlőszó / en: control word
    output reg  [3:0]  o_nsteps,    // hu: teljes lépésszám (1..15) / en: total step count
    output reg         o_valid      // hu: 1 ha ismert opkód / en: 1 if recognized opcode
);

    // hu: Belső segédjelek a vezérlőszó felépítéséhez.
    // en: Internal helper signals for building the control word.

    // hu: Egyszerű 1-lépéses ALU vezérlőszó: pop(N), ALU, push(ALU), PC+=len, done.
    // en: Simple 1-step ALU control word: pop(N), ALU, push(ALU), PC=next, done.
    function [31:0] alu_binary(input [4:0] alu_op);
        alu_binary = 0;
        alu_binary[`UC_DONE]                          = 1;
        alu_binary[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd2;  // pop2
        alu_binary[`UC_STACK_PUSH]                     = 1;
        alu_binary[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO]   = `PUSH_SRC_ALU;
        alu_binary[`UC_ALU_EN]                         = 1;
        alu_binary[`UC_ALU_OP_HI:`UC_ALU_OP_LO]       = alu_op;
        alu_binary[`UC_PC_WR]                          = 1;
        alu_binary[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
    endfunction

    function [31:0] alu_unary(input [4:0] alu_op);
        alu_unary = 0;
        alu_unary[`UC_DONE]                          = 1;
        alu_unary[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd1;  // pop1
        alu_unary[`UC_STACK_PUSH]                     = 1;
        alu_unary[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO]   = `PUSH_SRC_ALU;
        alu_unary[`UC_ALU_EN]                         = 1;
        alu_unary[`UC_ALU_OP_HI:`UC_ALU_OP_LO]       = alu_op;
        alu_unary[`UC_PC_WR]                          = 1;
        alu_unary[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
    endfunction

    // hu: Konstans push: push(IMM), PC+=len, done.
    // en: Constant push: push(IMM), PC=next, done.
    function [31:0] const_push;
        input dummy;  // hu: Verilog function igényel paramétert / en: Verilog function needs parameter
        const_push = 0;
        const_push[`UC_DONE]                          = 1;
        const_push[`UC_STACK_PUSH]                     = 1;
        const_push[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO]   = `PUSH_SRC_IMM;
        const_push[`UC_PC_WR]                          = 1;
        const_push[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
    endfunction

    // hu: SRAM olvasás → push: sram_rd, push(SRAM), addr_src, PC+=len, done.
    // en: SRAM read → push: sram_rd, push(SRAM), addr_src, PC=next, done.
    function [31:0] sram_read_push(input [1:0] addr_src);
        sram_read_push = 0;
        sram_read_push[`UC_DONE]                          = 1;
        sram_read_push[`UC_STACK_PUSH]                     = 1;
        sram_read_push[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO]   = `PUSH_SRC_SRAM;
        sram_read_push[`UC_SRAM_RD]                        = 1;
        sram_read_push[`UC_ADDR_SRC_HI:`UC_ADDR_SRC_LO]   = addr_src;
        sram_read_push[`UC_PC_WR]                          = 1;
        sram_read_push[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
    endfunction

    // hu: Pop → SRAM írás: pop1, sram_wr, addr_src, PC+=len, done.
    // en: Pop → SRAM write: pop1, sram_wr, addr_src, PC=next, done.
    function [31:0] pop_sram_write(input [1:0] addr_src);
        pop_sram_write = 0;
        pop_sram_write[`UC_DONE]                          = 1;
        pop_sram_write[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd1;
        pop_sram_write[`UC_SRAM_WR]                        = 1;
        pop_sram_write[`UC_ADDR_SRC_HI:`UC_ADDR_SRC_LO]   = addr_src;
        pop_sram_write[`UC_PC_WR]                          = 1;
        pop_sram_write[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
    endfunction

    // hu: Összehasonlító branch: pop2, ALU, cond_en, PC, done.
    // en: Comparison branch: pop2, ALU, cond_en, PC, done.
    function [31:0] cmp_branch(input [4:0] alu_op, input [1:0] cond_type, input cond_signed);
        cmp_branch = 0;
        cmp_branch[`UC_DONE]                          = 1;
        cmp_branch[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd2;
        cmp_branch[`UC_ALU_EN]                         = 1;
        cmp_branch[`UC_ALU_OP_HI:`UC_ALU_OP_LO]       = alu_op;
        cmp_branch[`UC_PC_WR]                          = 1;
        cmp_branch[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_BRANCH;
        cmp_branch[`UC_COND_EN]                        = 1;
        cmp_branch[`UC_COND_TYPE_HI:`UC_COND_TYPE_LO] = cond_type;
        cmp_branch[`UC_COND_SIGNED]                    = cond_signed;
    endfunction

    always @(*) begin
        o_ctrl   = 32'd0;
        o_nsteps = 4'd0;
        o_valid  = 1'b0;

        case (i_opcode)

            // ============================================================
            // Nop — semmi, PC+=len
            // ============================================================
            {8'h00, `OP_NOP}: begin
                o_valid  = 1'b1;
                o_nsteps = 4'd1;

                if (i_step == 4'd0) begin
                    o_ctrl[`UC_DONE]                      = 1;
                    o_ctrl[`UC_PC_WR]                      = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]   = `PC_SRC_NEXT;
                end
            end

            // ============================================================
            // Aritmetika — bináris ALU opkódok
            // ============================================================
            {8'h00, `OP_ADD}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_ADD); end
            {8'h00, `OP_SUB}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_SUB); end
            {8'h00, `OP_MUL}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_MUL); end
            {8'h00, `OP_DIV}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_DIV); end
            {8'h00, `OP_REM}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_REM); end
            {8'h00, `OP_AND}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_AND); end
            {8'h00, `OP_OR}:  begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_OR);  end
            {8'h00, `OP_XOR}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_XOR); end
            {8'h00, `OP_SHL}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_SHL); end
            {8'h00, `OP_SHR}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_SHR); end
            {8'h00, `OP_SHR_UN}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_SHR_UN); end

            // ============================================================
            // Aritmetika — unáris ALU opkódok
            // ============================================================
            {8'h00, `OP_NEG}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_unary(`ALU_NEG); end
            {8'h00, `OP_NOT}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_unary(`ALU_NOT); end

            // ============================================================
            // Összehasonlítások (FE prefix — 16-bit opkód)
            // ============================================================
            {8'hFE, `OP_FE_CEQ}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_CEQ); end
            {8'hFE, `OP_FE_CGT}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_CGT); end
            {8'hFE, `OP_FE_CGT_UN}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_CGT_UN); end
            {8'hFE, `OP_FE_CLT}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_CLT); end
            {8'hFE, `OP_FE_CLT_UN}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = alu_binary(`ALU_CLT_UN); end

            // ============================================================
            // Konstans load — push(IMM), PC+=len
            // ============================================================
            {8'h00, `OP_LDNULL}:   begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end
            {8'h00, `OP_LDC_I4_M1}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end
            {8'h00, 8'h16}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_0
            {8'h00, 8'h17}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_1
            {8'h00, 8'h18}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_2
            {8'h00, 8'h19}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_3
            {8'h00, 8'h1A}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_4
            {8'h00, 8'h1B}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_5
            {8'h00, 8'h1C}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_6
            {8'h00, 8'h1D}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_7
            {8'h00, 8'h1E}:         begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end  // LdcI4_8
            {8'h00, `OP_LDC_I4_S}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end
            {8'h00, `OP_LDC_I4}:   begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = const_push(0); end

            // ============================================================
            // Stack manipuláció
            // ============================================================
            {8'h00, `OP_DUP}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                      = 1;
                    o_ctrl[`UC_STACK_PUSH]                 = 1;
                    o_ctrl[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO] = `PUSH_SRC_TOS;
                    o_ctrl[`UC_PC_WR]                      = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]   = `PC_SRC_NEXT;
                end
            end

            {8'h00, `OP_POP}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                          = 1;
                    o_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd1;
                    o_ctrl[`UC_PC_WR]                          = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
                end
            end

            // ============================================================
            // Argumentum load — SRAM read (addr_src=ARG), push(SRAM)
            // ============================================================
            {8'h00, `OP_LDARG_0},
            {8'h00, `OP_LDARG_1},
            {8'h00, `OP_LDARG_2},
            {8'h00, `OP_LDARG_3},
            {8'h00, `OP_LDARG_S}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;
                if (i_step == 0) o_ctrl = sram_read_push(`ADDR_SRC_ARG);
            end

            // ============================================================
            // Argumentum store — pop, SRAM write (addr_src=ARG)
            // ============================================================
            {8'h00, `OP_STARG_S}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;
                if (i_step == 0) o_ctrl = pop_sram_write(`ADDR_SRC_ARG);
            end

            // ============================================================
            // Lokális load — SRAM read (addr_src=LOCAL), push(SRAM)
            // ============================================================
            {8'h00, `OP_LDLOC_0},
            {8'h00, `OP_LDLOC_1},
            {8'h00, `OP_LDLOC_2},
            {8'h00, `OP_LDLOC_3},
            {8'h00, `OP_LDLOC_S}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;
                if (i_step == 0) o_ctrl = sram_read_push(`ADDR_SRC_LOCAL);
            end

            // ============================================================
            // Lokális store — pop, SRAM write (addr_src=LOCAL)
            // ============================================================
            {8'h00, `OP_STLOC_0},
            {8'h00, `OP_STLOC_1},
            {8'h00, `OP_STLOC_2},
            {8'h00, `OP_STLOC_3},
            {8'h00, `OP_STLOC_S}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;
                if (i_step == 0) o_ctrl = pop_sram_write(`ADDR_SRC_LOCAL);
            end

            // ============================================================
            // Branch — feltétel nélküli (br.s)
            // ============================================================
            {8'h00, `OP_BR_S}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                      = 1;
                    o_ctrl[`UC_PC_WR]                      = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]   = `PC_SRC_BRANCH;
                end
            end

            // ============================================================
            // Branch — egyértékű feltételes
            // ============================================================
            {8'h00, `OP_BRFALSE_S}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                          = 1;
                    o_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd1;
                    o_ctrl[`UC_PC_WR]                          = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_BRANCH;
                    o_ctrl[`UC_COND_EN]                        = 1;
                    o_ctrl[`UC_COND_TYPE_HI:`UC_COND_TYPE_LO] = `COND_EQ;  // TOS==0 → branch
                end
            end

            {8'h00, `OP_BRTRUE_S}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                          = 1;
                    o_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd1;
                    o_ctrl[`UC_PC_WR]                          = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_BRANCH;
                    o_ctrl[`UC_COND_EN]                        = 1;
                    o_ctrl[`UC_COND_TYPE_HI:`UC_COND_TYPE_LO] = `COND_NE;  // TOS!=0 → branch
                end
            end

            // ============================================================
            // Branch — kétértékű feltételes összehasonlítás
            // hu: beq.s: a==b → branch. ALU CEQ (1 ha egyenlő), COND_NE (1≠0 → branch).
            // hu: bge.s: a>=b → branch. ALU CLT (1 ha kisebb, signed), COND_EQ (0==0 → branch ha nem kisebb).
            // hu: bgt.s: a>b → branch. ALU CGT (1 ha nagyobb, signed), COND_NE (1≠0 → branch).
            // hu: ble.s: a<=b → branch. ALU CGT (1 ha nagyobb, signed), COND_EQ (0==0 → branch ha nem nagyobb).
            // hu: blt.s: a<b → branch. ALU CLT (1 ha kisebb, signed), COND_NE (1≠0 → branch).
            // hu: bne.un.s: a!=b → branch. ALU CEQ (1 ha egyenlő), COND_EQ (0==0 → branch ha nem egyenlő).
            // ============================================================
            {8'h00, `OP_BEQ_S}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = cmp_branch(`ALU_CEQ, `COND_NE, 1'b0); end
            {8'h00, `OP_BGE_S}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = cmp_branch(`ALU_CLT, `COND_EQ, 1'b1); end
            {8'h00, `OP_BGT_S}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = cmp_branch(`ALU_CGT, `COND_NE, 1'b1); end
            {8'h00, `OP_BLE_S}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = cmp_branch(`ALU_CGT, `COND_EQ, 1'b1); end
            {8'h00, `OP_BLT_S}:    begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = cmp_branch(`ALU_CLT, `COND_NE, 1'b1); end
            {8'h00, `OP_BNE_UN_S}: begin o_valid = 1; o_nsteps = 4'd1; if (i_step == 0) o_ctrl = cmp_branch(`ALU_CEQ, `COND_EQ, 1'b0); end

            // ============================================================
            // Indirekt memória — ldind.i4
            // hu: Pop cím, SRAM read indirect, push eredmény. 1 lépés.
            // ============================================================
            {8'h00, `OP_LDIND_I4}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                          = 1;
                    o_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd1;
                    o_ctrl[`UC_STACK_PUSH]                     = 1;
                    o_ctrl[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO]   = `PUSH_SRC_SRAM;
                    o_ctrl[`UC_SRAM_RD]                        = 1;
                    o_ctrl[`UC_ADDR_SRC_HI:`UC_ADDR_SRC_LO]   = `ADDR_SRC_IND;
                    o_ctrl[`UC_PC_WR]                          = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
                end
            end

            // ============================================================
            // Indirekt memória — stind.i4
            // hu: Pop value, pop cím, SRAM write indirect. 1 lépés.
            // ============================================================
            {8'h00, `OP_STIND_I4}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                          = 1;
                    o_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd2;
                    o_ctrl[`UC_SRAM_WR]                        = 1;
                    o_ctrl[`UC_ADDR_SRC_HI:`UC_ADDR_SRC_LO]   = `ADDR_SRC_IND;
                    o_ctrl[`UC_PC_WR]                          = 1;
                    o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]       = `PC_SRC_NEXT;
                end
            end

            // ============================================================
            // Break — debug trap
            // ============================================================
            {8'h00, `OP_BREAK}: begin
                o_valid  = 1;
                o_nsteps = 4'd1;

                if (i_step == 0) begin
                    o_ctrl[`UC_DONE]                            = 1;
                    o_ctrl[`UC_TRAP]                            = 1;
                    o_ctrl[`UC_TRAP_CODE_HI:`UC_TRAP_CODE_LO]  = 4'hB;  // TRAP_DEBUG_BREAK
                end
            end

            // ============================================================
            // Call — frame push + PC=call_target
            // hu: 2 lépés: step0=stack pop (args), step1=frame_push + PC=call.
            //     A tényleges arg-pop N-t a sequencer kezeli (ismétlődő step0).
            //     A microcode ROM csak a vezérlőjeleket definiálja.
            // ============================================================
            {8'h00, `OP_CALL}: begin
                o_valid  = 1;
                o_nsteps = 4'd2;

                case (i_step)
                    // hu: Step 0: SRAM read a call target header-jéből (validáció).
                    // en: Step 0: SRAM read from call target header (validation).
                    4'd0: begin
                        o_ctrl[`UC_SRAM_RD]                      = 1;
                        o_ctrl[`UC_ADDR_SRC_HI:`UC_ADDR_SRC_LO] = `ADDR_SRC_FRAME;
                    end

                    // hu: Step 1: frame push, PC = call target.
                    // en: Step 1: frame push, PC = call target.
                    4'd1: begin
                        o_ctrl[`UC_DONE]                        = 1;
                        o_ctrl[`UC_FRAME_PUSH]                  = 1;
                        o_ctrl[`UC_PC_WR]                       = 1;
                        o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]    = `PC_SRC_CALL;
                    end

                    default: begin
                        o_ctrl = 32'd0;
                    end
                endcase
            end

            // ============================================================
            // Ret — frame pop / halt
            // hu: 2 lépés: step0=pop return value (ha van),
            //              step1=frame_pop + PC=ret (vagy halt).
            // ============================================================
            {8'h00, `OP_RET}: begin
                o_valid  = 1;
                o_nsteps = 4'd2;

                case (i_step)
                    // hu: Step 0: feltételes pop — csak ha az eval stack-en van
                    //     return value (eval depth >= 1). A sequencer ellenőrzi
                    //     a UC_COND_POP bitet és az eval depth-et.
                    // en: Step 0: conditional pop — only if eval stack has a
                    //     return value (eval depth >= 1). The sequencer checks
                    //     UC_COND_POP and eval depth.
                    4'd0: begin
                        o_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO] = 2'd1;
                        o_ctrl[`UC_COND_POP]                       = 1;
                    end

                    // hu: Step 1: frame pop + PC=return PC (vagy halt ha root frame).
                    //     A halt bit-et a sequencer állítja be futásidőben
                    //     (CallDepth==1), de a ROM mindkét jelzést biztosítja.
                    // en: Step 1: frame pop + PC=return PC (or halt if root frame).
                    //     The halt bit is set by the sequencer at runtime
                    //     (CallDepth==1), but the ROM provides both signals.
                    4'd1: begin
                        o_ctrl[`UC_DONE]                        = 1;
                        o_ctrl[`UC_FRAME_POP]                   = 1;
                        o_ctrl[`UC_PC_WR]                       = 1;
                        o_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO]    = `PC_SRC_RET;
                        o_ctrl[`UC_HALT]                        = 1;
                    end

                    default: begin
                        o_ctrl = 32'd0;
                    end
                endcase
            end

            // ============================================================
            // Default — ismeretlen opkód
            // ============================================================
            default: begin
                o_ctrl   = 32'd0;
                o_nsteps = 4'd0;
                o_valid  = 1'b0;
            end

        endcase
    end

endmodule
