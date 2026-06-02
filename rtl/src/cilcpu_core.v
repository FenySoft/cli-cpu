// hu: CLI-CPU F2.5a Top-level Nano Core — az 5 részegység (cilcpu_alu,
//     cilcpu_decoder, cilcpu_microcode, cilcpu_stack_cache,
//     cilcpu_qspi_controller) integrációja. A spec a CORE_SPEC-{hu,en}.md.
//     Sub1 hatókör: reset, boot, fetch, decode, execute LDC + RET, halt.
//     Sub2+ hozza: aritmetika, branch, call, arg/local, stack overflow.
// en: CLI-CPU F2.5a Top-level Nano Core — integration of the 5 submodules.
//     Sub1 scope: reset, boot, fetch, decode, execute LDC + RET, halt.
//     Sub2+ adds: arithmetic, branch, call, arg/local, stack overflow.

`include "cilcpu_defines.vh"

`default_nettype none

// hu: F2.8 #6.5b-F1a — a QSPI controller a Core-ból KIEMELVE a SoC-szintre
//     (architektúra: a Core nem érintkezik közvetlenül a külső RAM/Flash
//     perifériákkal). A Core eszköz-agnosztikus külső-memória-master portot ad
//     (o_xmem_*/i_xmem_*); a CODE_BASE_OFFSET / QE_INIT_ENABLE paraméterek a
//     SoC/board szintű cilcpu_qspi_controller-re kerültek. ADR:
//     Vault/Decisions/2026-05-30-boot-load-architecture.md.
// en: F2.8 #6.5b-F1a — the QSPI controller is MOVED OUT of the Core to the SoC
//     level (the Core does not directly touch external RAM/Flash). The Core
//     exposes a device-agnostic external-memory master (o_xmem_*/i_xmem_*); the
//     CODE_BASE_OFFSET / QE_INIT_ENABLE params moved to the SoC/board-level
//     cilcpu_qspi_controller.
module cilcpu_core (
    input  wire        clk,
    input  wire        rst_n,

    // hu: Boot konfiguráció / en: Boot configuration
    input  wire [23:0] i_boot_pc,
    input  wire [7:0]  i_boot_arg_count,
    input  wire [7:0]  i_boot_local_count,
    input  wire        i_boot_start,
    input  wire [31:0] i_boot_arg_data,
    input  wire        i_boot_arg_valid,
    output reg         o_boot_arg_ready,

    // hu: Státusz / en: Status
    output reg         o_halt,
    output reg         o_trap,
    output reg  [7:0]  o_trap_code,
    output reg  [23:0] o_pc,
    output reg  [31:0] o_return_value,

    // hu: Külső-memória-master busz (read-only) — a Core a CODE-ot fetch-eli
    //     (instruction + CALL method-header) ezen át. A SoC/board köti egy
    //     cilcpu_qspi_controller-re. addr[23:20] = szegmens (a controller
    //     dekódolja). A Core SOHA nem ír külső memóriát (cpu_we a controlleren
    //     fixen 0); a PSRAM-írást a loader végzi a SoC-szintű QSPI-n.
    // en: External-memory master bus (read-only) — the Core fetches CODE
    //     (instructions + CALL method headers) over this. The SoC/board wires it
    //     to a cilcpu_qspi_controller. addr[23:20] = segment (decoded by the
    //     controller). The Core NEVER writes external memory; the loader does
    //     PSRAM writes on the SoC-level QSPI.
    output wire [23:0] o_xmem_addr,
    output wire        o_xmem_re,
    input  wire [31:0] i_xmem_rdata,
    input  wire        i_xmem_ready,
    input  wire        i_xmem_busy,

    // hu: MMIO-master busz (F2.8 #6.2, architektúra B) — a 0xF szegmensű
    //     (addr[31:28]==SEG_MMIO) LDIND/STIND a perifériákat a wrapperen át
    //     éri el. A core csak a buszt hajtja; a periféria-dekódolást (mailbox
    //     0xF000_0100 / GPIO 0xF000_0200 / trace 0xF000_0300) a wrapper végzi.
    //     o_mmio_we/re: 1-ciklusos pulzus. i_mmio_rdata: a slave registered
    //     olvasási eredménye, az o_mmio_re utáni ciklusban érvényes
    //     (a mailbox/gpio/trace 1-ciklus registered read-jével egyezik).
    // en: MMIO master bus (F2.8 #6.2, architecture B) — 0xF-segment
    //     (addr[31:28]==SEG_MMIO) LDIND/STIND reach peripherals through the
    //     wrapper. The core only drives the bus; the wrapper decodes the
    //     peripheral. o_mmio_we/re: 1-cycle pulse. i_mmio_rdata: the slave's
    //     registered read result, valid the cycle after o_mmio_re.
    output reg  [31:0] o_mmio_addr,
    output reg  [31:0] o_mmio_wdata,
    output reg         o_mmio_we,
    output reg         o_mmio_re,
    input  wire [31:0] i_mmio_rdata,

    // hu: F3 — on-chip SRAM betöltő (load) write-port. A program betöltése a
    //     boot ELŐTT történik (a core ST_RESET-ben van): a SoC ezen a porton
    //     írja a CODE-ot az on-chip SRAM-ba — mód A-ban közvetlenül az UART-
    //     loader, mód B-ben a QSPI→SRAM copy-engine. i_ld_wdata BIG-ENDIAN
    //     (byte@addr a [31:24]-en, ahogy a loader/QSPI adja); a core LE-re
    //     fordítva tárolja (a fetch adapter LE-t vár). i_ld_addr = on-chip
    //     byte-cím (a [13:0] számít). 1-ciklusos write.
    // en: F3 — on-chip SRAM loader write port. The program is loaded BEFORE boot
    //     (core in ST_RESET): the SoC writes CODE into the on-chip SRAM over this
    //     port — directly from the UART loader in mode A, from the QSPI→SRAM copy
    //     engine in mode B. i_ld_wdata is BIG-ENDIAN (byte@addr in [31:24], as the
    //     loader/QSPI provide); the core stores it byte-swapped to LE (the fetch
    //     adapter expects LE). i_ld_addr = on-chip byte address ([13:0] used).
    input  wire        i_ld_we,
    input  wire [13:0] i_ld_addr,
    input  wire [31:0] i_ld_wdata
);

    // ============================================================
    // hu: Top-level FSM állapotok
    // en: Top-level FSM states
    // ============================================================
    localparam [3:0] ST_RESET    = 4'd0;
    localparam [3:0] ST_BOOT     = 4'd1;
    localparam [3:0] ST_FETCH    = 4'd2;
    localparam [3:0] ST_DECODE   = 4'd3;
    localparam [3:0] ST_EXECUTE  = 4'd4;
    localparam [3:0] ST_MEM_WAIT = 4'd5;   // Sub3: SRAM read 1-ciklus latencia / Sub3: SRAM read 1-cycle latency
    localparam [3:0] ST_CALL     = 4'd6;   // Sub5: CALL frame manager
    localparam [3:0] ST_RET      = 4'd7;   // Sub5: RET frame manager
    localparam [3:0] ST_HALT     = 4'd8;
    localparam [3:0] ST_TRAP     = 4'd9;
    // hu: F2.7 Sub5 — szekvenciális osztó (cilcpu_divider) wait-állapota.
    //     A DIV/REM opkódok ST_EXECUTE phase 0-ról ide ugranak, megvárják
    //     a divider o_done-ját (~34 ciklus), majd a normál phase 0 záró
    //     műveletek (latch + pop + phase 1) az ST_DIV_WAIT done ágában
    //     futnak — innen vissza ST_EXECUTE phase 1-be a replace_top-ra.
    // en: F2.7 Sub5 — wait state for the sequential divider
    //     (cilcpu_divider). DIV/REM opcodes jump here from ST_EXECUTE
    //     phase 0, wait for the divider's o_done (~34 cycles); the normal
    //     phase-0 closing actions (latch + pop + phase 1) run in the
    //     ST_DIV_WAIT done branch — back to ST_EXECUTE phase 1 for the
    //     replace_top.
    localparam [3:0] ST_DIV_WAIT = 4'd10;

    // hu: F2.6-prep — szekvenciális szorzó (cilcpu_multiplier) wait-állapota.
    //     A MUL opkód ST_EXECUTE phase 0-ról ide ugrik, megvárja a multiplier
    //     o_done-ját (≤32 ciklus, kis operandusoknál jóval kevesebb), majd a
    //     normál phase 0 záró műveletek (latch + pop + phase 1) az ST_MUL_WAIT
    //     done ágában futnak — innen vissza ST_EXECUTE phase 1-be a
    //     replace_top-ra. A MUL-nak nincs trap-je (wrapping, unchecked).
    // en: F2.6-prep — wait state for the sequential multiplier
    //     (cilcpu_multiplier). The MUL opcode jumps here from ST_EXECUTE
    //     phase 0, waits for the multiplier's o_done (≤32 cycles, far fewer
    //     for small operands); the normal phase-0 closing actions (latch +
    //     pop + phase 1) run in the ST_MUL_WAIT done branch — back to
    //     ST_EXECUTE phase 1 for the replace_top. MUL has no trap
    //     (wrapping, unchecked).
    localparam [3:0] ST_MUL_WAIT = 4'd11;

    // hu: Sub5 — ST_CALL sub-states (frame push szekvencia)
    // en: Sub5 — ST_CALL sub-states (frame push sequence)
    localparam [3:0] CALL_HDR_REQ      = 4'd0;
    localparam [3:0] CALL_HDR_WAIT     = 4'd1;
    localparam [3:0] CALL_VALIDATE     = 4'd2;
    localparam [3:0] CALL_ARG_POP_REQ  = 4'd3;
    localparam [3:0] CALL_ARG_POP_WAIT = 4'd4;
    localparam [3:0] CALL_ARG_POP_WR   = 4'd5;
    localparam [3:0] CALL_HDR_WR_RPC   = 4'd6;
    localparam [3:0] CALL_HDR_WR_PFP   = 4'd7;
    localparam [3:0] CALL_HDR_WR_AL    = 4'd8;
    localparam [3:0] CALL_LOCAL_ZERO   = 4'd9;
    localparam [3:0] CALL_FINALIZE     = 4'd10;
    // hu: F2.7.D — új sub-state-ek. A CALL_ARG_POP_* (3/4/5) szemantikája
    //     megváltozott: NEM cache-pop, hanem SRAM→SRAM arg-másolás a flush
    //     UTÁN (a caller eval ekkor már teljesen SRAM-ban van).
    // en: F2.7.D — new sub-states. CALL_ARG_POP_* (3/4/5) repurposed:
    //     SRAM→SRAM arg copy AFTER flush (caller eval fully in SRAM).
    localparam [3:0] CALL_FLUSH        = 4'd11;
    localparam [3:0] CALL_SAVE_D       = 4'd12;

    // hu: Sub5 — ST_RET sub-states (frame pop szekvencia)
    // en: Sub5 — ST_RET sub-states (frame pop sequence)
    localparam [3:0] RET_REQ_RPC    = 4'd0;
    localparam [3:0] RET_WAIT_RPC   = 4'd1;
    localparam [3:0] RET_LATCH_RPC  = 4'd2;
    localparam [3:0] RET_WAIT_PFP   = 4'd3;
    localparam [3:0] RET_LATCH_PFP  = 4'd4;
    localparam [3:0] RET_WAIT_AL    = 4'd5;
    localparam [3:0] RET_LATCH_AL   = 4'd6;
    localparam [3:0] RET_FINALIZE   = 4'd7;
    localparam [3:0] RET_PUSH_RV    = 4'd8;
    // hu: F2.7.D — 1-ciklus bridge a sp_load → ST_SPFILL beindulásáig,
    //     hogy a RET_PUSH_RV !w_sc_busy őre érvényes legyen.
    // en: F2.7.D — 1-cycle bridge so the SC enters ST_SPFILL before the
    //     RET_PUSH_RV !w_sc_busy guard is evaluated.
    localparam [3:0] RET_WAIT_SPFILL = 4'd9;

    // hu: Boot szekvencia alállapotok
    // en: Boot sequence sub-states
    localparam [2:0] BOOT_HDR0   = 3'd0;  // [FP+0] = -1 (ReturnPC)
    localparam [2:0] BOOT_HDR1   = 3'd1;  // [FP+4] = -1 (PrevFrameBase)
    localparam [2:0] BOOT_HDR2   = 3'd2;  // [FP+8] = {0, locals, args}
    localparam [2:0] BOOT_ARGS   = 3'd3;  // streaming args
    localparam [2:0] BOOT_LOCALS = 3'd4;  // zeroing locals
    localparam [2:0] BOOT_FINAL  = 3'd5;  // SP/FP/CallDepth init

    reg  [3:0]  r_state;
    reg  [2:0]  r_boot_sub;

    // ============================================================
    // hu: Belső állapot
    // en: Internal state
    // ============================================================
    reg  [23:0] r_pc;
    reg  [13:0] r_sp;
    reg  [13:0] r_fp;
    reg  [9:0]  r_call_depth;
    reg  [4:0]  r_arg_count;
    reg  [4:0]  r_local_count;
    reg  [3:0]  r_step;
    reg  [4:0]  r_boot_arg_idx;
    reg  [4:0]  r_boot_local_idx;
    reg  [1:0]  r_alu_phase;       // 0 = latch+pop (binary), 1 = replace_top
    reg  [31:0] r_alu_result_latched;
    reg         r_mem_phase;       // Sub3: 0 = pop1, 1 = SRAM write a pop_data-val
    reg  [13:0] r_mem_addr_latched;
    // hu: F2.8 #6.2 — IND-cél szegmens: 1 = MMIO (külső master busz), 0 = SRAM.
    //     A phase 0-ban dekódolt szegmenst őrzi a phase 1 / ST_MEM_WAIT phase 1
    //     számára. r_mmio_addr_latched a teljes 32-bit MMIO-cím.
    // en: F2.8 #6.2 — IND target segment: 1 = MMIO (external master bus),
    //     0 = SRAM. Holds the segment decoded in phase 0 for phase 1 /
    //     ST_MEM_WAIT phase 1. r_mmio_addr_latched is the full 32-bit MMIO addr.
    reg         r_mem_is_mmio;
    reg  [31:0] r_mmio_addr_latched;

    // hu: Sub5 — frame manager regiszterek (ST_CALL és ST_RET használja)
    // en: Sub5 — frame manager registers (used by ST_CALL and ST_RET)
    reg  [3:0]  r_call_sub;            // CALL sub-state
    reg  [3:0]  r_ret_sub;             // RET sub-state
    reg  [23:0] r_call_target_rva;     // CALL operand: callee header RVA
    reg  [23:0] r_return_pc;           // CALL utáni PC (a caller folytatása)
    reg  [4:0]  r_new_arg_count;       // CALL header-ből
    reg  [4:0]  r_new_local_count;     // CALL header-ből
    reg  [13:0] r_new_fp;              // FP_new = caller r_sp a CALL pillanatában
    reg  [4:0]  r_arg_pop_idx;         // CALL: hányadik arg pop-jánál tartunk
    reg  [4:0]  r_local_zero_idx;      // CALL: hányadik local nullázásánál
    reg  [31:0] r_ret_value;           // RET: a step 0-ban pop-olt return value
    reg  [13:0] r_callee_old_fp;       // RET: a callee r_fp-je (felszabadításhoz)
    reg  [23:0] r_ret_return_pc;       // RET: visszatérési PC (header [FP+0]-ból)
    reg  [13:0] r_ret_prev_fp;         // RET: caller FP (header [FP+4]-ből)
    // hu: F2.7.D — caller eval depth megőrzés CALL/RET között.
    //     r_call_total_depth: caller eval mélység a CALL pillanatában
    //       (args-szal együtt), w_sc_depth-ből latch-elve.
    //     r_caller_eval_d: a megőrzendő held eval depth = total - new_arg.
    //       CALL-kor a caller header [FP+8] bits[22:16]-ba mentve.
    //     r_ret_caller_d: RET-kor a [prev_fp+8][22:16]-ból visszaolvasva.
    // en: F2.7.D — caller eval depth preservation across CALL/RET.
    reg  [6:0]  r_call_total_depth;
    reg  [6:0]  r_caller_eval_d;
    reg  [6:0]  r_ret_caller_d;

    // hu: Fetch buffer (8 byte, packed FIFO). A packed register a Verilator
    //     non-blocking assignment-jén megbízhatóbb mint a reg array
    //     (`reg [7:0] arr [0:7]`), amivel a slide-during-multi-NBA esetén
    //     a forrás-byte-okat néha hibás (cycle-X+1) értékkel olvasta.
    // en: Fetch buffer (8 byte, packed FIFO). Packed register is more
    //     reliable in Verilator NBA than the reg array form, where slides
    //     across multiple NBAs sometimes saw the wrong (cycle-X+1) source
    //     bytes.
    reg  [63:0] r_fetch_buf;    // byte 0 = [7:0], byte 7 = [63:56]
    reg  [3:0]  r_fetch_count;
    reg  [23:0] r_fetch_pc;     // a buffer első byte-jának PC-je

    // hu: Belső 16 KB SRAM (4096 × 32-bit) — inferred BRAM
    reg  [31:0] r_sram [0:4095];

    // hu: Aktuális utasítás (decode után latched)
    reg  [15:0] r_opcode;
    reg  [2:0]  r_length;
    reg  [31:0] r_operand;

    // hu: SRAM bus signal-ek (boot fázisban a top-level írja, később
    //     a Stack Cache + microcode is használja).
    // en: SRAM bus signals (top-level writes in boot, later also
    //     Stack Cache + microcode).
    reg  [13:0] r_sram_addr;
    reg  [31:0] r_sram_wdata;
    reg         r_sram_we;
    reg         r_sram_re;
    reg  [31:0] r_sram_rdata_latched;

    // ============================================================
    // hu: F3 — instrukció-fetch SRAM adapter regiszterei + kérő-jelek.
    //     A fetch/CALL FSM változatlanul a "QSPI" kérő-jeleket használja
    //     (r_qspi_addr/re, r_qspi_inflight) és a w_qspi_* választ várja, de
    //     ezeket az on-chip r_sram-ból az alábbi adapter hajtja (lásd a fetch
    //     adapter FSM-et a memória-blokk után), NEM a külső o_xmem busz.
    // en: F3 — instruction-fetch SRAM adapter regs + request signals. The
    //     fetch/CALL FSM keeps using the "QSPI" request signals and waits for
    //     w_qspi_*, but the adapter below (see the fetch adapter FSM after the
    //     memory block) drives them from the on-chip r_sram, NOT o_xmem.
    // ============================================================
    // hu: A fetch byte-granuláris (a fetch FSM 4 byte-ot vár a PONTOS
    //     r_qspi_addr byte-címtől, ami branch után tetszőleges igazítású). Az
    //     on-chip SRAM viszont szó-szervezésű → az adapter KÉT szomszédos szót
    //     olvas (W0=addr>>2, W1=W0+1), és a {W1,W0}-ból a byte-offszettől
    //     (addr[1:0]) vonja ki a 4 byte-ot. ISSUE0/CAP0 → W0, ISSUE1/CAP1 → W1.
    // en: Fetch is byte-granular (the fetch FSM expects 4 bytes from the EXACT
    //     r_qspi_addr byte address, arbitrarily aligned after a branch). The
    //     on-chip SRAM is word-organized → the adapter reads TWO adjacent words
    //     (W0=addr>>2, W1=W0+1) and extracts the 4 bytes at byte offset addr[1:0]
    //     from {W1,W0}. ISSUE0/CAP0 → W0, ISSUE1/CAP1 → W1.
    localparam [2:0] FA_IDLE   = 3'd0;
    localparam [2:0] FA_ISSUE0 = 3'd1;   // W0 read kiadva
    localparam [2:0] FA_CAP0    = 3'd2;   // W0 latch + W1 read kiadása
    localparam [2:0] FA_ISSUE1 = 3'd3;   // W1 read kiadva
    localparam [2:0] FA_CAP1    = 3'd4;   // W1 latch + 4-byte kivonás + ready
    reg  [2:0]  r_fa_st;
    reg  [13:0] r_fa_addr;
    reg  [31:0] r_fa_w0;
    reg  [31:0] r_fa_word;
    reg         r_fa_ready;
    wire        fa_sram_re   = (r_fa_st == FA_ISSUE0) || (r_fa_st == FA_ISSUE1);
    wire [13:0] fa_sram_addr = (r_fa_st == FA_ISSUE1) ? (r_fa_addr + 14'd4)
                                                      : r_fa_addr;
    // hu: {W1,W0} eltolva a byte-offszettel → az alsó 32 bit = a 4 byte a
    //     byte-címtől (LE). FA_CAP1-ben r_sram_rdata_latched = W1, r_fa_w0 = W0.
    // en: {W1,W0} shifted by the byte offset → low 32 bits = the 4 bytes from
    //     the byte address (LE). In FA_CAP1, r_sram_rdata_latched = W1.
    wire [63:0] w_fa_shift   = {r_sram_rdata_latched, r_fa_w0}
                               >> {r_fa_addr[1:0], 3'b000};

    // hu: A fetch/CALL FSM kérő-/állapot-regiszterei (korábban lentebb voltak;
    //     ide kerültek, hogy az adapter és az arbiter is lássa őket).
    // en: Fetch/CALL FSM request/state registers (moved up so the adapter and
    //     the arbiter can both see them).
    reg  [23:0] r_qspi_addr;
    reg         r_qspi_re;
    reg         r_qspi_inflight;
    reg  [23:0] r_next_fetch_addr;

    // hu: SRAM bus arbiter — HÁROM forrás: Stack Cache spill/fill (`w_sc_*`,
    //     PRIORITÁS) > microcode/boot (`r_sram_*`) > instrukció-fetch adapter
    //     (`fa_*`). A microcode és a fetch temporálisan diszjunkt (fetch csak
    //     ST_FETCH / CALL-header-olvasásnál, microcode csak ST_EXECUTE/
    //     ST_MEM_WAIT-ben) → a prioritás csak biztonsági háló. A muxolás a
    //     memória-blokkon KÍVÜL történik (tiszta single-port BRAM-inferencia).
    // en: SRAM bus arbiter — THREE sources: Stack Cache spill/fill (`w_sc_*`,
    //     PRIORITY) > microcode/boot (`r_sram_*`) > instruction-fetch adapter
    //     (`fa_*`). microcode and fetch are temporally disjoint, so the priority
    //     is just a safety net. The mux lives OUTSIDE the memory block (clean
    //     single-port BRAM inference).
    // hu: A loader write BIG-ENDIAN szót ad (byte@addr a [31:24]-en) → LE-re
    //     fordítva tároljuk (a fetch adapter LE-t vár az r_sram-ban).
    // en: The loader write provides a BIG-ENDIAN word (byte@addr in [31:24]) →
    //     store byte-swapped to LE (the fetch adapter expects LE in r_sram).
    wire [31:0] w_ld_wdata_le = { i_ld_wdata[ 7: 0], i_ld_wdata[15: 8],
                                  i_ld_wdata[23:16], i_ld_wdata[31:24] };
    wire        w_mc_active  = r_sram_re | r_sram_we;        // microcode/boot
    // hu: non-SC cím prioritás: load > microcode/boot > fetch (a load csak
    //     ST_RESET-ben, a microcode és a fetch run közben — diszjunkt).
    wire [13:0] w_nonsc_addr = i_ld_we    ? i_ld_addr  :
                               w_mc_active ? r_sram_addr : fa_sram_addr;
    wire [11:0] w_sram_idx   = w_sc_busy ? w_sc_sram_addr[13:2] : w_nonsc_addr[13:2];
    wire [31:0] w_sram_wdata = w_sc_busy ? w_sc_sram_wdata
                                         : (i_ld_we ? w_ld_wdata_le : r_sram_wdata);
    wire        w_sram_we    = w_sc_busy ? w_sc_sram_we : (r_sram_we | i_ld_we);
    wire        w_sram_re    = w_sc_busy ? w_sc_sram_re : (r_sram_re | fa_sram_re);

    // ============================================================
    // hu: F3 — külső-memória-master LEKÖTVE. A Core a CODE-ot az on-chip
    //     SRAM-ból fetch-eli (fetch adapter), NEM a külső o_xmem buszon, ezért
    //     o_xmem_re VÉGIG 0 (egységes on-chip SRAM invariáns; lásd
    //     test_core_unified). A w_qspi_* választ a fetch adapter hajtja az
    //     r_fa_* regiszterekből: az r_sram LE szavát big-endian-re fordítja,
    //     hogy a fetch FSM meglévő byte-swap-je helyes LE buffer-t adjon (és a
    //     CALL-header magic a [31:24]-en jó legyen). Az i_xmem_* bemenetek így
    //     használaton kívül (a QSPI a SoC-szintű betöltés-idejű backing store).
    // en: F3 — external-memory master TIED OFF. The Core fetches CODE from the
    //     on-chip SRAM (fetch adapter), NOT the external o_xmem bus, so
    //     o_xmem_re stays 0 throughout (unified on-chip SRAM invariant; see
    //     test_core_unified). The w_qspi_* response is driven by the fetch
    //     adapter from the r_fa_* registers: it byte-swaps the LE r_sram word to
    //     big-endian so the fetch FSM's existing swap yields a correct LE buffer
    //     (and the CALL header magic reads right at [31:24]). The i_xmem_* inputs
    //     are thus unused (QSPI is the SoC-level load-time backing store).
    // ============================================================
    assign o_xmem_addr = 24'd0;
    assign o_xmem_re   = 1'b0;

    wire [31:0] w_qspi_rdata = { r_fa_word[ 7: 0], r_fa_word[15: 8],
                                 r_fa_word[23:16], r_fa_word[31:24] };
    wire        w_qspi_ready = r_fa_ready;
    wire        w_qspi_busy  = (r_fa_st != FA_IDLE);

    // hu: Használaton kívüli i_xmem_* bemenetek elnyelése (Verilator lint).
    // en: Sink unused i_xmem_* inputs (Verilator lint).
    wire        w_unused_xmem = &{1'b0, i_xmem_rdata, i_xmem_ready, i_xmem_busy};

    // hu: (F1a) A cilcpu_qspi_controller példányosítás INNEN ELTÁVOLÍTVA — a
    //     controller a SoC/board szintre került. A fenti o_xmem_*/i_xmem_*
    //     portok kötik a Core-t a SoC-szintű controllerhez.
    // en: (F1a) The cilcpu_qspi_controller instance is REMOVED here — it lives
    //     at SoC/board level now. The o_xmem_*/i_xmem_* ports above wire the
    //     Core to the SoC-level controller.

    // ============================================================
    // hu: Decoder bekötése (kombinációs)
    // en: Decoder wiring (combinational)
    // ============================================================
    wire [15:0] w_dec_opcode;
    wire [2:0]  w_dec_length;
    wire [31:0] w_dec_operand;
    wire        w_dec_trap;
    wire [2:0]  w_dec_bytes_avail = (r_fetch_count > 4'd5) ? 3'd5 :
                                    r_fetch_count[2:0];

    cilcpu_decoder u_decoder (
        .i_byte0           (r_fetch_buf[ 7: 0]),
        .i_byte1           (r_fetch_buf[15: 8]),
        .i_byte2           (r_fetch_buf[23:16]),
        .i_byte3           (r_fetch_buf[31:24]),
        .i_byte4           (r_fetch_buf[39:32]),
        .i_bytes_available (w_dec_bytes_avail),
        .o_opcode          (w_dec_opcode),
        .o_length          (w_dec_length),
        .o_operand         (w_dec_operand),
        .o_trap_invalid    (w_dec_trap)
    );

    // ============================================================
    // hu: Microcode bekötése (kombinációs)
    // en: Microcode wiring (combinational)
    // ============================================================
    wire [31:0] w_uc_ctrl;
    wire [3:0]  w_uc_nsteps;
    wire        w_uc_valid;

    cilcpu_microcode u_microcode (
        .i_opcode (r_opcode),
        .i_step   (r_step),
        .o_ctrl   (w_uc_ctrl),
        .o_nsteps (w_uc_nsteps),
        .o_valid  (w_uc_valid)
    );

    // hu: Vezérlőszó mező-kibontás
    // en: Control word field extraction
    wire        uc_done       = w_uc_ctrl[`UC_DONE];
    wire        uc_trap_en    = w_uc_ctrl[`UC_TRAP];
    wire [3:0]  uc_trap_code  = w_uc_ctrl[`UC_TRAP_CODE_HI:`UC_TRAP_CODE_LO];
    wire [1:0]  uc_stack_pop  = w_uc_ctrl[`UC_STACK_POP_HI:`UC_STACK_POP_LO];
    wire        uc_stack_push = w_uc_ctrl[`UC_STACK_PUSH];
    wire [1:0]  uc_push_src   = w_uc_ctrl[`UC_PUSH_SRC_HI:`UC_PUSH_SRC_LO];
    wire        uc_alu_en     = w_uc_ctrl[`UC_ALU_EN];
    wire [4:0]  uc_alu_op     = w_uc_ctrl[`UC_ALU_OP_HI:`UC_ALU_OP_LO];
    wire        uc_sram_rd    = w_uc_ctrl[`UC_SRAM_RD];
    wire        uc_sram_wr    = w_uc_ctrl[`UC_SRAM_WR];
    wire [1:0]  uc_addr_src   = w_uc_ctrl[`UC_ADDR_SRC_HI:`UC_ADDR_SRC_LO];
    wire        uc_pc_wr      = w_uc_ctrl[`UC_PC_WR];
    wire [1:0]  uc_pc_src     = w_uc_ctrl[`UC_PC_SRC_HI:`UC_PC_SRC_LO];
    wire        uc_frame_pop  = w_uc_ctrl[`UC_FRAME_POP];
    wire        uc_frame_push = w_uc_ctrl[`UC_FRAME_PUSH];
    wire        uc_halt_en    = w_uc_ctrl[`UC_HALT];
    wire        uc_cond_en    = w_uc_ctrl[`UC_COND_EN];
    wire [1:0]  uc_cond_type  = w_uc_ctrl[`UC_COND_TYPE_HI:`UC_COND_TYPE_LO];
    wire        uc_cond_pop   = w_uc_ctrl[`UC_COND_POP];

    // ============================================================
    // hu: Stack Cache bekötése
    // en: Stack Cache wiring
    // ============================================================
    reg         r_sc_sp_load;
    reg  [13:0] r_sc_sp_init;
    reg  [6:0]  r_sc_sp_depth;        // F2.7.D — sp_load eval depth (RET restore)
    reg         r_sc_flush;           // F2.7.D — cache flush SRAM-ba (CALL előtt)
    reg         r_sc_push_en;
    reg  [31:0] r_sc_push_data;
    reg         r_sc_pop_en;
    reg         r_sc_replace_top_en;
    reg  [31:0] r_sc_replace_top_data;
    wire [31:0] w_sc_tos;
    wire [31:0] w_sc_tos1;
    wire [31:0] w_sc_pop_data;
    wire [6:0]  w_sc_depth;
    wire        w_sc_busy;
    wire        w_sc_ready;
    wire        w_sc_trap;
    wire [7:0]  w_sc_trap_code;

    // hu: A Stack Cache SRAM master portjai Sub3-ban kapcsolódnak a belső
    //     16 KB SRAM-ra egy egyszerű prioritásos arbiter-en át (lásd
    //     lentebb). A microcode kontrakt szerint uc_sram_rd/wr csak akkor
    //     aktív, ha w_sc_busy=0 — ezért a busy-priority arbitrálás
    //     determinisztikus, race-mentes.
    // en: The Stack Cache SRAM master ports are wired to the internal
    //     16 KB SRAM in Sub3 via a simple priority arbiter (see below).
    //     Per microcode contract, uc_sram_rd/wr fires only when w_sc_busy=0
    //     — hence busy-priority arbitration is deterministic and race-free.
    wire [13:0] w_sc_sram_addr;
    wire [31:0] w_sc_sram_wdata;
    wire        w_sc_sram_we;
    wire        w_sc_sram_re;
    wire [31:0] w_sc_sram_rdata;
    wire        w_sc_sram_ready;
    wire [2:0]  w_sc_cc;              // F2.7.D — cache_count (flush done detektálás)

    cilcpu_stack_cache u_stack_cache (
        .clk              (clk),
        .rst_n            (rst_n),
        .sp_load          (r_sc_sp_load),
        .sp_init          (r_sc_sp_init),
        .sp_depth         (r_sc_sp_depth),
        .flush_en         (r_sc_flush),
        .push_en          (r_sc_push_en),
        .push_data        (r_sc_push_data),
        .pop_en           (r_sc_pop_en),
        .dup_en           (1'b0),
        .swap_en          (1'b0),
        .replace_top_en   (r_sc_replace_top_en),
        .replace_top_data (r_sc_replace_top_data),
        .peek_index       (2'd0),
        .peek_data        (),
        .tos              (w_sc_tos),
        .tos1             (w_sc_tos1),
        .pop_data         (w_sc_pop_data),
        .depth            (w_sc_depth),
        .cache_count      (w_sc_cc),
        .busy             (w_sc_busy),
        .ready            (w_sc_ready),
        .trap             (w_sc_trap),
        .trap_code        (w_sc_trap_code),
        .sram_addr        (w_sc_sram_addr),
        .sram_wdata       (w_sc_sram_wdata),
        .sram_rdata       (w_sc_sram_rdata),
        .sram_we          (w_sc_sram_we),
        .sram_re          (w_sc_sram_re),
        .sram_ready       (w_sc_sram_ready)
    );

    // ============================================================
    // hu: ALU bekötése — i_op_a = TOS1, i_op_b = TOS (a CIL-T0 stack
    //     konvenciója: push a, push b, ALU(op_a=a, op_b=b)). Az ALU
    //     kombinációs, az eredmény azonnal érvényes.
    // en: ALU wiring — i_op_a = TOS1, i_op_b = TOS (CIL-T0 stack
    //     convention: push a, push b, ALU(op_a=a, op_b=b)). The ALU is
    //     combinational, result valid immediately.
    // ============================================================
    wire [31:0] w_alu_result;

    // hu: F2.7 Sub5 — szekvenciális osztó (cilcpu_divider) bekötése.
    //     A DIV/REM-et r_div_start 1-ciklusos pulzus indítja; a divider
    //     ~34 ciklus alatt párhuzamosan ad hányadost és maradékot,
    //     r_div_is_rem dönti el, melyiket írja a result-latch-be. A
    //     trap-flag-eket (div_zero / INT_MIN/-1 overflow) az ST_DIV_WAIT
    //     vizsgálja az o_done ciklusban.
    // en: F2.7 Sub5 — sequential divider (cilcpu_divider) wiring. DIV/REM
    //     is launched by a 1-cycle r_div_start pulse; the divider yields
    //     quotient and remainder in parallel over ~34 cycles, and
    //     r_div_is_rem selects which goes into the result latch. Trap
    //     flags (div_zero / INT_MIN/-1 overflow) are inspected in
    //     ST_DIV_WAIT on the o_done cycle.
    wire [31:0] w_div_quotient;
    wire [31:0] w_div_remainder;
    wire        w_div_busy;
    wire        w_div_done;
    wire        w_div_trap_div_zero;
    wire        w_div_trap_overflow;
    reg         r_div_start;
    reg         r_div_is_rem;

    // hu: F2.6-prep — szekvenciális szorzó (cilcpu_multiplier) bekötése.
    //     A MUL-t r_mul_start 1-ciklusos pulzus indítja; a szorzó shift-add
    //     algoritmussal (korai kilépés, ≤32 ciklus) adja az alsó 32 bites
    //     szorzatot. Nincs trap (wrapping, unchecked) — az ST_MUL_WAIT csak
    //     az o_done-t várja.
    // en: F2.6-prep — sequential multiplier (cilcpu_multiplier) wiring. MUL
    //     is launched by a 1-cycle r_mul_start pulse; the multiplier yields
    //     the lower 32-bit product via shift-add (early exit, ≤32 cycles).
    //     No trap (wrapping, unchecked) — ST_MUL_WAIT only waits for o_done.
    wire [31:0] w_mul_product;
    wire        w_mul_busy;
    wire        w_mul_done;
    reg         r_mul_start;

    // hu: ALU operandus mux — binary (pop=2): i_op_a=TOS1, i_op_b=TOS;
    //     unary (pop=1): i_op_a=TOS (a stack tetején lévő érték), i_op_b
    //     nem használt. A microcode `alu_unary` UC_STACK_POP=1, az ALU
    //     NEG/NOT az i_op_a-t veszi.
    // en: ALU operand mux — binary (pop=2): i_op_a=TOS1, i_op_b=TOS;
    //     unary (pop=1): i_op_a=TOS (the value on top), i_op_b unused.
    //     The `alu_unary` microcode has UC_STACK_POP=1; ALU NEG/NOT use
    //     i_op_a.
    wire [31:0] w_alu_op_a = (uc_stack_pop == 2'd1) ? w_sc_tos : w_sc_tos1;

    cilcpu_alu u_alu (
        .i_op_a          (w_alu_op_a),
        .i_op_b          (w_sc_tos),
        .i_alu_op        (uc_alu_op),
        .o_result        (w_alu_result)
    );

    // hu: Szekvenciális osztó példányosítás (DIV/REM, F2.7 Sub5).
    //     Operandusok: i_dividend = w_sc_tos1 (TOS-1, osztandó),
    //     i_divisor = w_sc_tos (TOS, osztó). Az operandusok az
    //     r_div_start pulzus ciklusában érvényesek; a divider belül
    //     latch-eli őket, így a stack a divider futása alatt szabadon
    //     mozogna — a jelenlegi flow viszont az o_done-ig stallol és
    //     csak az ST_DIV_WAIT záró ágában popol (egyszerűbb az FSM).
    // en: Sequential divider instantiation (DIV/REM, F2.7 Sub5).
    //     Operands: i_dividend = w_sc_tos1 (TOS-1, dividend),
    //     i_divisor = w_sc_tos (TOS, divisor). Operands are valid in
    //     the r_div_start pulse cycle; the divider latches them
    //     internally, so the stack could move during the divider's
    //     run — but the current flow stalls until o_done and only pops
    //     in the ST_DIV_WAIT closing branch (simpler FSM).
    cilcpu_divider u_divider (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_start         (r_div_start),
        .i_dividend      (w_sc_tos1),
        .i_divisor       (w_sc_tos),
        .o_busy          (w_div_busy),
        .o_done          (w_div_done),
        .o_quotient      (w_div_quotient),
        .o_remainder     (w_div_remainder),
        .o_trap_div_zero (w_div_trap_div_zero),
        .o_trap_overflow (w_div_trap_overflow)
    );

    // hu: Szekvenciális szorzó példányosítás (MUL, F2.6-prep).
    //     Operandusok: i_op_a = w_sc_tos1 (TOS-1), i_op_b = w_sc_tos (TOS).
    //     Az r_mul_start pulzus ciklusában érvényesek; a szorzó belül
    //     latch-eli őket. A flow az o_done-ig stallol és csak az ST_MUL_WAIT
    //     záró ágában popol (egyszerűbb FSM, a divider-rel azonos minta).
    // en: Sequential multiplier instantiation (MUL, F2.6-prep).
    //     Operands: i_op_a = w_sc_tos1 (TOS-1), i_op_b = w_sc_tos (TOS).
    //     Valid on the r_mul_start pulse cycle; the multiplier latches them
    //     internally. The flow stalls until o_done and only pops in the
    //     ST_MUL_WAIT closing branch (simpler FSM, same pattern as the divider).
    cilcpu_multiplier u_multiplier (
        .i_clk      (clk),
        .i_rst_n    (rst_n),
        .i_start    (r_mul_start),
        .i_op_a     (w_sc_tos1),
        .i_op_b     (w_sc_tos),
        .o_busy     (w_mul_busy),
        .o_done     (w_mul_done),
        .o_product  (w_mul_product)
    );

    // ============================================================
    // hu: Push data mux — a microcode UC_PUSH_SRC = IMM esetén az
    //     opcode-ból (rejtett konstansok) vagy a decoder operand-jából.
    // en: Push data mux — when microcode UC_PUSH_SRC = IMM, source is
    //     the opcode (hidden constants) or the decoder operand.
    // ============================================================
    reg [31:0] push_data_imm;

    always @(*) begin
        // hu: Az r_opcode alsó byte-ja az LDC.I4_* opcode
        case (r_opcode[7:0])
            `OP_LDC_I4_M1: push_data_imm = 32'hFFFF_FFFF;
            `OP_LDC_I4_0:  push_data_imm = 32'd0;
            `OP_LDC_I4_1:  push_data_imm = 32'd1;
            `OP_LDC_I4_2:  push_data_imm = 32'd2;
            `OP_LDC_I4_3:  push_data_imm = 32'd3;
            `OP_LDC_I4_4:  push_data_imm = 32'd4;
            `OP_LDC_I4_5:  push_data_imm = 32'd5;
            `OP_LDC_I4_6:  push_data_imm = 32'd6;
            `OP_LDC_I4_7:  push_data_imm = 32'd7;
            `OP_LDC_I4_8:  push_data_imm = 32'd8;
            `OP_LDNULL:    push_data_imm = 32'd0;
            default:       push_data_imm = r_operand;  // LDC.I4_S, LDC.I4
        endcase
    end

    // ============================================================
    // hu: PC update mux
    //     PC_SRC_BRANCH: rövid branch — operand[7:0] sign-extend a
    //       pc + length-hez. (A decoder már sign-extend-el 32 bitre.)
    // en: PC update mux
    //     PC_SRC_BRANCH: short branch — sign-extend operand[7:0] added
    //       to pc + length. (Decoder already sign-extends to 32 bits.)
    // ============================================================
    reg [23:0] pc_next;

    wire signed [23:0] branch_offset_ext = {{16{r_operand[7]}}, r_operand[7:0]};

    always @(*) begin
        case (uc_pc_src)
            `PC_SRC_NEXT:   pc_next = r_pc + {21'd0, r_length};
            `PC_SRC_BRANCH: pc_next = r_pc + {21'd0, r_length} + branch_offset_ext;
            // hu: PC_SRC_RET / PC_SRC_CALL: a RET-/CALL-állapotgép hajtja a
            //     PC-t a regisztrált úton (RET_FINALIZE: r_pc <= r_ret_return_pc),
            //     a pc_next mux ezekre nem fogyasztódik. A RET-PC kombinációs
            //     r_sram-olvasása megakadályozná a BRAM-inferenciát, ezért
            //     nincs külön ág — mindkettő a default biztonságos r_pc-jére esik.
            // en: PC_SRC_RET / PC_SRC_CALL: the RET/CALL FSM drives the PC via
            //     the registered path (RET_FINALIZE: r_pc <= r_ret_return_pc);
            //     pc_next is not consumed for these. A combinational r_sram
            //     read for the RET PC would block BRAM inference, so there is
            //     no dedicated arm — both fall through to the safe default r_pc.
            default:        pc_next = r_pc;
        endcase
    end

    // ============================================================
    // hu: Branch eldöntés — Sub4
    //     1-operand branches (BRFALSE_S / BRTRUE_S): a cond_type a TOS
    //       alapján:
    //         COND_EQ → branch ha TOS == 0 (BRFALSE)
    //         COND_NE → branch ha TOS != 0 (BRTRUE)
    //     2-operand branches (BEQ/BLT/BGE/BGT/BLE/BNE): az ALU eredménye
    //       (CEQ/CLT/CGT) 0/1, és a cond_type ezt fordítja vissza:
    //         COND_NE → branch ha alu_result != 0 (alapértelmezett)
    //         COND_EQ → branch ha alu_result == 0 (BGE = !CLT, BLE = !CGT)
    //     Az `r_alu_result_latched` a phase 0-ban beolvasott ALU eredmény.
    // en: Branch decision — Sub4
    //     1-operand branches: cond_type vs TOS;
    //     2-operand branches: ALU result via cond_type inversion.
    // ============================================================
    wire branch_taken_1op = uc_cond_en && (uc_stack_pop == 2'd1) && (
        (uc_cond_type == `COND_EQ && w_sc_tos == 32'd0) ||
        (uc_cond_type == `COND_NE && w_sc_tos != 32'd0)
    );

    wire branch_taken_2op_phase1 = uc_cond_en && uc_alu_en && (
        (uc_cond_type == `COND_NE && r_alu_result_latched != 32'd0) ||
        (uc_cond_type == `COND_EQ && r_alu_result_latched == 32'd0)
    );

    // hu: Sub4 hiánypótlás — Branch target validáció (TRAP_INVALID_BRANCH).
    //     A spec szerint a branch target `target < 0` esetén trap-elt.
    //     F2.5a egyszerűsítés: csak negatív cím (felső bit = 1) trap-elt;
    //     pozitív túlcsordulás (24-bit címterén túl) NEM detektálódik itt,
    //     hanem a következő ciklus fetch-én (0xFF byte → INVALID_OPCODE).
    //     Mivel `pc_next` 24-bit unsigned, a `branch_offset_ext` 24-bit
    //     signed → ha pc_next felső bitje 1, az -8M..-1 tartomány = negatív.
    //     Csak akkor érvényes a vizsgálat, ha PC_SRC_BRANCH (1-op vagy 2-op
    //     branch); call/ret nem ide tartozik (Sub5).
    // en: Sub4 hardening — Branch target validation (TRAP_INVALID_BRANCH).
    //     Per spec, the branch is invalid if `target < 0`. F2.5a simplifies
    //     to: only negative target (top bit set in 24-bit) traps; positive
    //     overflow (above 24-bit address space) is NOT detected here, but
    //     on next-cycle fetch (0xFF byte → INVALID_OPCODE).
    //     `pc_next` is 24-bit unsigned; `branch_offset_ext` is 24-bit
    //     signed → if pc_next's top bit is 1, the value is in -8M..-1.
    //     Only valid when PC_SRC_BRANCH (1-op or 2-op branch); call/ret
    //     are out of scope (Sub5).
    wire branch_target_invalid = (uc_pc_src == `PC_SRC_BRANCH) &&
                                  (pc_next[23] == 1'b1);

    // ============================================================
    // hu: SRAM rdata/ready wireing a Stack Cache felé.
    //     A regisztrált SRAM-olvasás eredménye a következő ciklus elején
    //     érvényes; a Stack Cache 1-ciklus latencia + sram_ready-vel
    //     szinkronizál. Az SRAM mindig 1-ciklus alatt válaszol →
    //     sram_ready statikusan 1.
    // en: SRAM rdata/ready wiring to Stack Cache.
    //     Registered SRAM read result is valid at the next cycle's start;
    //     the Stack Cache uses 1-cycle latency + sram_ready handshake.
    //     SRAM always responds in 1 cycle → sram_ready is static 1.
    // ============================================================
    assign w_sc_sram_rdata = r_sram_rdata_latched;
    assign w_sc_sram_ready = 1'b1;

    // ============================================================
    // hu: Sub3 — SRAM cím számítás (frame layout):
    //     ARG:   FP + 12 + idx*4
    //     LOCAL: FP + 12 + arg_count*4 + idx*4
    //     A range check a microcode-szervezésben már megelőzi az SRAM
    //     hozzáférést (lásd ST_EXECUTE → uc_sram_rd/wr ág).
    // en: Sub3 — SRAM address calculation (frame layout):
    //     ARG:   FP + 12 + idx*4
    //     LOCAL: FP + 12 + arg_count*4 + idx*4
    //     Range check precedes SRAM access in the sequencer.
    // ============================================================
    // hu: Hatásos arg/local index — az LDARG.0..3 / LDLOC.0..3 / STLOC.0..3
    //     opkódok az indexet az opcode byte-ban hordozzák (operand=0):
    //       0x02..0x05 LDARG.0..3 → idx = opcode - 0x02
    //       0x06..0x09 LDLOC.0..3 → idx = opcode - 0x06
    //       0x0A..0x0D STLOC.0..3 → idx = opcode - 0x0A
    //     Az LDARG.S/STARG.S/LDLOC.S/STLOC.S esetén az operandus tartalmazza
    //     az indexet (8-bit unsigned).
    // en: Effective arg/local index — short opcodes carry the index in the
    //     opcode byte itself (operand=0):
    //       0x02..0x05 LDARG.0..3 → idx = opcode - 0x02
    //       0x06..0x09 LDLOC.0..3 → idx = opcode - 0x06
    //       0x0A..0x0D STLOC.0..3 → idx = opcode - 0x0A
    //     The .S forms carry the index in the operand.
    wire [7:0]  eff_idx =
        (r_opcode[7:0] >= 8'h02 && r_opcode[7:0] <= 8'h05) ? (r_opcode[7:0] - 8'h02) :
        (r_opcode[7:0] >= 8'h06 && r_opcode[7:0] <= 8'h09) ? (r_opcode[7:0] - 8'h06) :
        (r_opcode[7:0] >= 8'h0A && r_opcode[7:0] <= 8'h0D) ? (r_opcode[7:0] - 8'h0A) :
        r_operand[7:0];

    function [13:0] addr_calc;
        input [1:0]  fc_addr_src;
        input [7:0]  fc_idx;
        reg [13:0] base;
        begin
            base = r_fp + 14'd12;
            case (fc_addr_src)
                `ADDR_SRC_ARG:   addr_calc = base + {4'd0, fc_idx, 2'd0};
                `ADDR_SRC_LOCAL: addr_calc = base + {7'd0, r_arg_count, 2'd0}
                                                   + {4'd0, fc_idx, 2'd0};
                `ADDR_SRC_FRAME: addr_calc = r_fp + {4'd0, fc_idx, 2'd0};
                default:         addr_calc = base;
            endcase
        end
    endfunction

    // ============================================================
    // hu: SRAM memória — KÜLÖN always @(posedge clk) blokk, async reset
    //     NÉLKÜL. A BRAM-inferencia tiltja az async-reset érzékenységet,
    //     a fő FSM blokk viszont async resetes — ezért a memória nem
    //     lehet ott. A tömb maga nem resetelhető (BRAM-tartalom); az
    //     r_sram_rdata_latched kimeneti regiszter szinkron resettel
    //     nullázódik. A muxolt w_sram_* arbiter-jelek a deklarációnál.
    // en: SRAM memory — SEPARATE always @(posedge clk) block, NO async
    //     reset. BRAM inference forbids async-reset sensitivity, but the
    //     main FSM block is async-reset — so the memory cannot live
    //     there. The array itself is not reset (BRAM contents); the
    //     r_sram_rdata_latched output register clears via synchronous
    //     reset. Muxed w_sram_* arbiter signals are at the declaration.
    // ============================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            r_sram_rdata_latched <= 32'd0;
        end else begin
            if (w_sram_we) begin
                r_sram[w_sram_idx] <= w_sram_wdata;
            end
            if (w_sram_re) begin
                r_sram_rdata_latched <= r_sram[w_sram_idx];
            end
        end
    end

    // ============================================================
    // hu: F3 — instrukció-fetch SRAM adapter FSM. A fetch/CALL FSM r_qspi_re
    //     kérés-pulzusát on-chip SRAM-olvasásra fordítja, és a w_qspi_ready
    //     pulzust + a beolvasott szót szolgáltatja vissza:
    //       FA_IDLE  : r_qspi_re=1 → cím-latch, FA_ISSUE
    //       FA_ISSUE : fa_sram_re=1 (az arbiteren át) → SRAM 1-ciklus read; a
    //                  r_sram_rdata_latched a KÖVETKEZŐ ciklusban érvényes
    //       FA_CAP   : r_fa_word <= r_sram_rdata_latched, r_fa_ready pulzus
    //     A latencia (~3 ciklus issue→ready) bőven a QSPI ~58-98 alatt; a
    //     fetch/CALL FSM handshake-je (inflight + w_qspi_ready) változatlan.
    // en: F3 — instruction-fetch SRAM adapter FSM. Translates the fetch/CALL
    //     FSM's r_qspi_re request pulse into an on-chip SRAM read and returns the
    //     w_qspi_ready pulse + the read word. Latency (~3 cycles issue→ready) is
    //     far below QSPI ~58-98; the fetch/CALL FSM handshake is unchanged.
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_fa_st    <= FA_IDLE;
            r_fa_addr  <= 14'd0;
            r_fa_w0    <= 32'd0;
            r_fa_word  <= 32'd0;
            r_fa_ready <= 1'b0;
        end else begin
            r_fa_ready <= 1'b0;   // hu: 1-ciklusos ready pulzus alaphelyzet
            case (r_fa_st)
                FA_IDLE: begin
                    if (r_qspi_re) begin
                        r_fa_addr <= r_qspi_addr[13:0];
                        r_fa_st   <= FA_ISSUE0;
                    end
                end
                FA_ISSUE0: begin
                    // hu: fa_sram_re=1, fa_sram_addr=W0 → SRAM latch; W0 a CAP0-ban jó.
                    r_fa_st <= FA_CAP0;
                end
                FA_CAP0: begin
                    r_fa_w0 <= r_sram_rdata_latched;   // W0 (addr>>2)
                    r_fa_st <= FA_ISSUE1;              // W1 read kiadása
                end
                FA_ISSUE1: begin
                    r_fa_st <= FA_CAP1;
                end
                FA_CAP1: begin
                    // hu: {W1,W0} >> (byte_offset*8) alsó 32 bitje = a 4 byte a
                    //     byte-címtől, LE sorrendben (r_fa_word[7:0] = byte@addr).
                    //     A w_qspi_rdata ezt big-endian-re fordítja a fetch FSM-nek.
                    // en: {W1,W0} >> (byte_offset*8) low 32 bits = the 4 bytes from
                    //     the byte address, LE (r_fa_word[7:0] = byte@addr).
                    r_fa_word  <= w_fa_shift[31:0];
                    r_fa_ready <= 1'b1;
                    r_fa_st    <= FA_IDLE;
                end
                default: r_fa_st <= FA_IDLE;
            endcase
        end
    end

    // ============================================================
    // hu: Fő FSM
    // en: Main FSM
    // ============================================================
    // hu: A buffer csúsztatás explicit case-szel megy — nem kell loop index.
    // en: Buffer slide uses explicit case — no loop index needed.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state          <= ST_RESET;
            r_boot_sub       <= BOOT_HDR0;
            r_pc             <= 24'd0;
            r_sp             <= 14'd0;
            r_fp             <= 14'd0;
            r_call_depth     <= 10'd0;
            r_arg_count      <= 5'd0;
            r_local_count    <= 5'd0;
            r_step           <= 4'd0;
            r_boot_arg_idx   <= 5'd0;
            r_boot_local_idx <= 5'd0;
            r_fetch_count    <= 4'd0;
            r_fetch_pc       <= 24'd0;
            r_fetch_buf      <= 64'd0;
            r_opcode         <= 16'd0;
            r_length         <= 3'd0;
            r_operand        <= 32'd0;
            r_qspi_addr      <= 24'd0;
            r_qspi_re        <= 1'b0;
            // hu: Sub2.1 — fetch addresszálás állapot reset
            // en: Sub2.1 — fetch addressing state reset
            r_qspi_inflight  <= 1'b0;
            r_next_fetch_addr <= 24'd0;
            r_sram_addr      <= 14'd0;
            r_sram_wdata     <= 32'd0;
            r_sram_we        <= 1'b0;
            r_sram_re        <= 1'b0;
            r_div_start      <= 1'b0;
            r_div_is_rem     <= 1'b0;
            r_mul_start      <= 1'b0;
            r_sc_sp_load     <= 1'b0;
            r_sc_sp_init     <= 14'd0;
            r_sc_sp_depth    <= 7'd0;
            r_sc_flush       <= 1'b0;
            r_sc_push_en     <= 1'b0;
            r_sc_push_data   <= 32'd0;
            r_sc_pop_en      <= 1'b0;
            r_sc_replace_top_en   <= 1'b0;
            r_sc_replace_top_data <= 32'd0;
            r_alu_phase           <= 2'd0;
            r_alu_result_latched  <= 32'd0;
            r_mem_phase           <= 1'b0;
            r_mem_addr_latched    <= 14'd0;
            r_mem_is_mmio         <= 1'b0;
            r_mmio_addr_latched   <= 32'd0;
            o_mmio_addr           <= 32'd0;
            o_mmio_wdata          <= 32'd0;
            o_mmio_we             <= 1'b0;
            o_mmio_re             <= 1'b0;
            // hu: Sub5 — frame manager regiszterek reset
            // en: Sub5 — frame manager registers reset
            r_call_sub            <= CALL_HDR_REQ;
            r_ret_sub             <= RET_REQ_RPC;
            r_call_target_rva     <= 24'd0;
            r_return_pc           <= 24'd0;
            r_new_arg_count       <= 5'd0;
            r_new_local_count     <= 5'd0;
            r_new_fp              <= 14'd0;
            r_arg_pop_idx         <= 5'd0;
            r_local_zero_idx      <= 5'd0;
            r_ret_value           <= 32'd0;
            r_callee_old_fp       <= 14'd0;
            r_ret_return_pc       <= 24'd0;
            r_ret_prev_fp         <= 14'd0;
            r_call_total_depth    <= 7'd0;
            r_caller_eval_d       <= 7'd0;
            r_ret_caller_d        <= 7'd0;
            o_halt           <= 1'b0;
            o_trap           <= 1'b0;
            o_trap_code      <= 8'd0;
            o_pc             <= 24'd0;
            o_return_value   <= 32'd0;
            o_boot_arg_ready <= 1'b0;
            // hu: Az SRAM nem zerózódik reset-tel — szintézisben undefined.
            //     Az F2.5a viselkedés: a boot felülír, így nem olvasunk
            //     inicializálatlan címről.
        end else begin
            // hu: Default jelek minden ciklus elején
            r_qspi_re        <= 1'b0;
            r_sram_we        <= 1'b0;
            r_sram_re        <= 1'b0;
            o_mmio_we        <= 1'b0;
            o_mmio_re        <= 1'b0;
            r_div_start      <= 1'b0;
            r_mul_start      <= 1'b0;
            r_sc_sp_load        <= 1'b0;
            r_sc_flush          <= 1'b0;
            r_sc_push_en        <= 1'b0;
            r_sc_pop_en         <= 1'b0;
            r_sc_replace_top_en <= 1'b0;
            o_boot_arg_ready    <= 1'b0;
            o_pc                <= r_pc;

            // hu: Sub6 — Stack Cache trap aggregátor: az SC pulzusos trap
            //     jele (overflow / underflow) bármelyik állapotban
            //     detektálható; átáll ST_TRAP-be, latch-eli a trap_code-ot.
            // en: Sub6 — Stack Cache trap aggregator: SC pulses trap on
            //     overflow / underflow, detectable from any state →
            //     ST_TRAP, latch trap_code.
            if (w_sc_trap && r_state != ST_TRAP && r_state != ST_HALT) begin
                o_trap      <= 1'b1;
                o_trap_code <= w_sc_trap_code;
                r_state     <= ST_TRAP;
            end

            case (r_state)

            // ====================================================
            // ST_RESET — vár i_boot_start-ra
            // ====================================================
            ST_RESET: begin
                if (i_boot_start) begin
                    r_arg_count    <= i_boot_arg_count[4:0];
                    r_local_count  <= i_boot_local_count[4:0];
                    r_pc           <= i_boot_pc;
                    // hu: F3 — a root frame a STACK_BASE-re kerül (a CODE+DATA
                    //     a [0, STACK_BASE) tartományba), nem a 0. bájtra.
                    // en: F3 — root frame at STACK_BASE (CODE+DATA in
                    //     [0, STACK_BASE)), not at byte 0.
                    r_fp           <= `STACK_BASE;
                    r_sp           <= `STACK_BASE;
                    r_call_depth   <= 10'd1;
                    r_boot_arg_idx <= 5'd0;
                    r_boot_local_idx <= 5'd0;
                    r_state        <= ST_BOOT;
                    r_boot_sub     <= BOOT_HDR0;
                end
            end

            // ====================================================
            // ST_BOOT — root frame felépítése
            // ====================================================
            ST_BOOT: begin
                case (r_boot_sub)
                    BOOT_HDR0: begin
                        r_sram_addr  <= `STACK_BASE + 14'd0;     // FP+0
                        r_sram_wdata <= 32'hFFFF_FFFF;  // ReturnPC = -1
                        r_sram_we    <= 1'b1;
                        r_boot_sub   <= BOOT_HDR1;
                    end
                    BOOT_HDR1: begin
                        r_sram_addr  <= `STACK_BASE + 14'd4;     // FP+4
                        r_sram_wdata <= 32'hFFFF_FFFF;  // PrevFrameBase = -1
                        r_sram_we    <= 1'b1;
                        r_boot_sub   <= BOOT_HDR2;
                    end
                    BOOT_HDR2: begin
                        r_sram_addr  <= `STACK_BASE + 14'd8;     // FP+8
                        r_sram_wdata <= {16'd0,
                                         3'd0, r_local_count,
                                         3'd0, r_arg_count};
                        r_sram_we    <= 1'b1;
                        if (r_arg_count > 5'd0) begin
                            r_boot_sub <= BOOT_ARGS;
                        end else if (r_local_count > 5'd0) begin
                            r_boot_sub <= BOOT_LOCALS;
                        end else begin
                            r_boot_sub <= BOOT_FINAL;
                        end
                    end
                    BOOT_ARGS: begin
                        // hu: Várjuk az i_boot_arg_valid pulzust
                        o_boot_arg_ready <= 1'b1;
                        if (i_boot_arg_valid) begin
                            r_sram_addr  <= `STACK_BASE + 14'd12 + {7'd0, r_boot_arg_idx, 2'd0};
                            r_sram_wdata <= i_boot_arg_data;
                            r_sram_we    <= 1'b1;
                            r_boot_arg_idx <= r_boot_arg_idx + 5'd1;
                            o_boot_arg_ready <= 1'b0;
                            if (r_boot_arg_idx + 5'd1 >= r_arg_count) begin
                                if (r_local_count > 5'd0) begin
                                    r_boot_sub <= BOOT_LOCALS;
                                end else begin
                                    r_boot_sub <= BOOT_FINAL;
                                end
                            end
                        end
                    end
                    BOOT_LOCALS: begin
                        r_sram_addr  <= `STACK_BASE + 14'd12
                                        + {7'd0, r_arg_count, 2'd0}
                                        + {7'd0, r_boot_local_idx, 2'd0};
                        r_sram_wdata <= 32'd0;
                        r_sram_we    <= 1'b1;
                        r_boot_local_idx <= r_boot_local_idx + 5'd1;
                        if (r_boot_local_idx + 5'd1 >= r_local_count) begin
                            r_boot_sub <= BOOT_FINAL;
                        end
                    end
                    BOOT_FINAL: begin
                        // hu: SP = STACK_BASE + 12 + arg_count*4 + local_count*4
                        r_sp <= `STACK_BASE + 14'd12
                                + {7'd0, r_arg_count, 2'd0}
                                + {7'd0, r_local_count, 2'd0};
                        // hu: Stack Cache reset az új SP-re (boot: üres eval)
                        // en: Stack Cache reset to new SP (boot: empty eval)
                        r_sc_sp_load <= 1'b1;
                        r_sc_sp_init <= `STACK_BASE + 14'd12
                                        + {7'd0, r_arg_count, 2'd0}
                                        + {7'd0, r_local_count, 2'd0};
                        r_sc_sp_depth <= 7'd0;
                        r_state    <= ST_FETCH;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc <= r_pc;
                        // hu: Sub2.1 — a fetch állapot inicializálása az
                        //     i_boot_pc-re; a soron következő ST_FETCH ettől
                        //     a címtől indítja az 1. tranzakciót.
                        // en: Sub2.1 — initialize fetch state to i_boot_pc;
                        //     the next ST_FETCH will start the 1st
                        //     transaction from this address.
                        r_next_fetch_addr <= i_boot_pc;
                        r_qspi_inflight   <= 1'b0;
                    end
                    default: begin
                        r_state <= ST_TRAP;
                        o_trap  <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_OPCODE;
                    end
                endcase
            end

            // ====================================================
            // ST_FETCH — fetch buffer feltöltés
            // hu: A feltételek sorrendje fontos! Ha a controller éppen
            //     befejezte a fetch-et (cpu_ready=1, busy=0), az append
            //     ágnak ELSŐBBSÉGE van a fetch-indítás ágával szemben,
            //     különben az indítás "elmosná" az aktuális adatot.
            // en: Order of conditions matters! If the controller just
            //     completed (cpu_ready=1, busy=0), the append branch must
            //     win over the fetch-start branch, otherwise we'd lose the
            //     just-arrived data.
            // ====================================================
            ST_FETCH: begin
                if (r_fetch_count >= 4'd5) begin
                    r_state <= ST_DECODE;
                end else if (w_qspi_ready) begin
                    // hu: 4-byte append a packed buffer-be tetszőleges
                    //     r_fetch_count (0..4) értéknél. A korábbi 0/4-csak
                    //     verzió a Sub2.2 előtt: 5-byte LDC.I4 után
                    //     r_fetch_count=3 maradt (slide-down nem 4-byte
                    //     aligned), és a default ág eldobta a következő
                    //     fetch eredményét → timeout.
                    //     Sub2.2: explicit case minden cnt=0..4 értékre,
                    //     mindegyik a `cnt*8` bit ofszetre illeszti a
                    //     little-endian 4-byte word-öt. cnt>=5 esetén nem
                    //     indulhatott volna fetch (lásd ST_FETCH felső ág),
                    //     ezért default ágra nem futhatunk.
                    // en: 4-byte append to the packed buffer at any
                    //     r_fetch_count (0..4). The earlier 0/4-only form:
                    //     after 5-byte LDC.I4, r_fetch_count=3 (slide is
                    //     not 4-byte aligned) and the default arm dropped
                    //     the next fetch result → timeout.
                    //     Sub2.2: explicit case for every cnt=0..4, each
                    //     inserting the little-endian 4-byte word at the
                    //     `cnt*8` bit offset. cnt>=5 cannot start a fetch
                    //     (see top branch in ST_FETCH), so default cannot
                    //     fire.
                    case (r_fetch_count)
                        4'd0: r_fetch_buf[31: 0] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd1: r_fetch_buf[39: 8] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd2: r_fetch_buf[47:16] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd3: r_fetch_buf[55:24] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        4'd4: r_fetch_buf[63:32] <= {
                                w_qspi_rdata[ 7: 0],
                                w_qspi_rdata[15: 8],
                                w_qspi_rdata[23:16],
                                w_qspi_rdata[31:24]
                            };
                        default: ;
                    endcase
                    r_fetch_count     <= r_fetch_count + 4'd4;
                    r_qspi_inflight   <= 1'b0;
                    r_next_fetch_addr <= r_next_fetch_addr + 24'd4;
                end else if (!r_qspi_inflight) begin
                    // hu: Új fetch indítása. A feltétel a Sub2.1 fix után
                    //     egyetlen állapot-bittől függ (r_qspi_inflight),
                    //     a w_qspi_busy redundáns volt és Verilator NBA
                    //     race-t okozott. A cím a r_next_fetch_addr-ból
                    //     jön — ezt a Boot finalize r_pc-re inicializálja,
                    //     APPEND után +4-gyel léptetjük, full-flush-nál
                    //     pedig pc_next-re állítjuk.
                    // en: Start a new fetch. After the Sub2.1 fix, the
                    //     condition depends on a single state bit
                    //     (r_qspi_inflight); w_qspi_busy was redundant
                    //     and caused a Verilator NBA race. The address
                    //     comes from r_next_fetch_addr — initialized to
                    //     r_pc on Boot finalize, advanced by +4 after
                    //     APPEND, and reset to pc_next on full flush.
                    r_qspi_addr     <= r_next_fetch_addr;
                    r_qspi_re       <= 1'b1;
                    r_qspi_inflight <= 1'b1;
                end
            end

            // ====================================================
            // ST_DECODE — 1 ciklus, decoder kombinációs eredmény latch
            // ====================================================
            ST_DECODE: begin
                if (w_dec_trap) begin
                    o_trap      <= 1'b1;
                    o_trap_code <= `TRAP_INVALID_OPCODE;
                    r_state     <= ST_TRAP;
                end else begin
                    r_opcode  <= w_dec_opcode;
                    r_length  <= w_dec_length;
                    r_operand <= w_dec_operand;
                    r_step    <= 4'd0;
                    r_state   <= ST_EXECUTE;
                end
            end

            // ====================================================
            // ST_EXECUTE — microcode sequencer
            // hu: Az ALU opcode-okat 2 ciklusra bontjuk (binary) vagy
            //     1 ciklusra (unary), mert a Stack Cache nem támogatja
            //     a pop_en+push_en egyidejű kombinációt. Binary minta:
            //       phase 0: latch ALU(tos1, tos), pop_en=1
            //       phase 1: replace_top(r_alu_result_latched)
            //     Unary minta: phase 0 csak: replace_top(alu_result).
            // en: ALU opcodes split into 2 cycles (binary) or 1 cycle
            //     (unary), since the Stack Cache disallows simultaneous
            //     pop_en+push_en. Binary pattern:
            //       phase 0: latch ALU(tos1, tos), pop_en=1
            //       phase 1: replace_top(r_alu_result_latched)
            //     Unary pattern: phase 0 only: replace_top(alu_result).
            // ====================================================
            ST_EXECUTE: begin
                if (!w_uc_valid) begin
                    o_trap      <= 1'b1;
                    o_trap_code <= `TRAP_INVALID_OPCODE;
                    r_state     <= ST_TRAP;
                end else if (uc_trap_en) begin
                    o_trap      <= 1'b1;
                    o_trap_code <= {4'd0, uc_trap_code};
                    r_state     <= ST_TRAP;
                end else if (uc_alu_en && r_alu_phase == 2'd0) begin
                    // hu: ALU phase 0 — kombinációs ALU eredmény latch-elése
                    //     (TOS1, TOS még érvényes). F2.7 Sub5: DIV/REM-et
                    //     szekvenciális osztó kezeli — r_div_start pulzus +
                    //     ST_DIV_WAIT; a phase 0 záró műveletei (latch +
                    //     pop + phase 1) és a trap-ellenőrzés is ott fut.
                    // en: ALU phase 0 — latch the combinational ALU result
                    //     (TOS1, TOS still valid). F2.7 Sub5: DIV/REM are
                    //     handled by the sequential divider — r_div_start
                    //     pulse + ST_DIV_WAIT; the phase-0 closing actions
                    //     (latch + pop + phase 1) and trap detection both
                    //     run there.
                    if (uc_alu_op == `ALU_DIV || uc_alu_op == `ALU_REM) begin
                        r_div_start  <= 1'b1;
                        r_div_is_rem <= (uc_alu_op == `ALU_REM);
                        r_state      <= ST_DIV_WAIT;
                    end else if (uc_alu_op == `ALU_MUL) begin
                        // hu: F2.6-prep — MUL a szekvenciális szorzóra
                        //     (r_mul_start pulzus + ST_MUL_WAIT). A phase 0
                        //     záró műveletei (latch + pop + phase 1) ott futnak.
                        // en: F2.6-prep — MUL to the sequential multiplier
                        //     (r_mul_start pulse + ST_MUL_WAIT). The phase-0
                        //     closing actions (latch + pop + phase 1) run there.
                        r_mul_start <= 1'b1;
                        r_state     <= ST_MUL_WAIT;
                    end else begin
                        r_alu_result_latched <= w_alu_result;
                        if (uc_stack_pop == 2'd2) begin
                            // hu: Binary — pop1 most, replace_top phase 1-ben
                            r_sc_pop_en <= 1'b1;
                            r_alu_phase <= 2'd1;
                            // hu: NEM uc_done — phase 1-be megyünk
                        end else begin
                            // hu: Unary — replace_top egyciklus alatt,
                            //     uc_done flow.
                            r_sc_replace_top_en   <= 1'b1;
                            r_sc_replace_top_data <= w_alu_result;
                            // hu: uc_done flow lefut alább
                            if (uc_pc_wr) begin
                                r_pc <= pc_next;
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
                                // hu: Sub2.1 — full-flush a fetch címet
                                //     pc_next-re állítja. Az esetlegesen
                                //     in-flight tranzakciót hagyjuk
                                //     befejeződni, az adat eldobódik
                                //     (a következő ST_FETCH a friss címet
                                //     fogja használni).
                                // en: Sub2.1 — full-flush sets the fetch
                                //     address to pc_next. Any in-flight
                                //     transaction is allowed to finish;
                                //     its data is discarded (the next
                                //     ST_FETCH uses the fresh address).
                                r_next_fetch_addr <= pc_next;
                            end
                            r_step  <= 4'd0;
                            r_state <= ST_FETCH;
                        end
                    end
                end else if (uc_alu_en && uc_cond_en && r_alu_phase == 2'd1) begin
                    // hu: 2-operand branch phase 1 (Sub4) — második pop,
                    //     branch eldöntés r_alu_result_latched alapján.
                    //     NEM replace_top, mert a stack-en már nincs
                    //     szükség az eredményre (az ALU comp BEQ/BLT/...
                    //     csak a feltételhez kellett).
                    //     Sub4 hiánypótlás: ha a branch teljesül és a
                    //     target negatív → TRAP_INVALID_BRANCH a PC update
                    //     előtt (a pop-ot már megengedjük, mert az állapot
                    //     ettől függetlenül halad).
                    // en: 2-operand branch phase 1 (Sub4) — second pop,
                    //     branch decision based on r_alu_result_latched.
                    //     No replace_top — the stack no longer needs the
                    //     comparison result.
                    //     Sub4 hardening: if branch is taken and target is
                    //     negative → TRAP_INVALID_BRANCH before PC update.
                    r_sc_pop_en <= 1'b1;
                    r_alu_phase <= 2'd0;
                    if (branch_taken_2op_phase1 && branch_target_invalid) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_BRANCH;
                        r_state     <= ST_TRAP;
                    end else if (branch_taken_2op_phase1) begin
                        r_pc          <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        r_next_fetch_addr <= pc_next;
                        r_step  <= 4'd0;
                        r_state <= ST_FETCH;
                    end else begin
                        r_pc          <= r_pc + {21'd0, r_length};
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= r_pc + {21'd0, r_length};
                        r_next_fetch_addr <= r_pc + {21'd0, r_length};
                        r_step  <= 4'd0;
                        r_state <= ST_FETCH;
                    end
                end else if (uc_alu_en && r_alu_phase == 2'd1) begin
                    // hu: ALU phase 1 (binary, NEM cond) — replace_top a
                    //     latch-elt eredménnyel, uc_done flow.
                    // en: ALU phase 1 (binary, non-cond) — replace_top
                    //     with latched result, uc_done flow.
                    r_sc_replace_top_en   <= 1'b1;
                    r_sc_replace_top_data <= r_alu_result_latched;
                    r_alu_phase           <= 2'd0;
                    if (uc_pc_wr) begin
                        r_pc <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        // hu: Sub2.1 — lásd unary ág kommentje.
                        // en: Sub2.1 — see unary branch comment.
                        r_next_fetch_addr <= pc_next;
                    end
                    r_step  <= 4'd0;
                    r_state <= ST_FETCH;
                end else if (uc_sram_rd) begin
                    // hu: Sub3 — SRAM olvasás (LDARG / LDLOC).
                    //     1. Range check: ARG → idx < arg_count, LOCAL →
                    //        idx < local_count. Hibás esetén megfelelő trap.
                    //     2. SRAM read indítás (1-ciklus latency), átmenet
                    //        ST_MEM_WAIT-re — ott push_data <= rdata és
                    //        uc_done flow.
                    //     A hatásos indexet `eff_idx` szolgáltatja: az
                    //     LDARG.0..3 / LDLOC.0..3 az opcode byte alsó 2
                    //     bitjéből, az .S formák az r_operand[7:0]-ból.
                    // en: Sub3 — SRAM read (LDARG / LDLOC).
                    //     1. Range check: ARG → idx < arg_count, LOCAL →
                    //        idx < local_count; trap on mismatch.
                    //     2. Start SRAM read (1-cycle latency), transition
                    //        to ST_MEM_WAIT for push_data <= rdata + uc_done.
                    //     `eff_idx` derives the index: short opcodes from
                    //     opcode[1:0], .S forms from r_operand[7:0].
                    if (uc_addr_src == `ADDR_SRC_IND) begin
                        // hu: LDIND.I4 — a cím a TOS-ról jön (indirekt).
                        //     Szegmens-dekódolás (F2.8 #6.2): addr[31:28]==0xF
                        //     (SEG_MMIO) → külső MMIO master busz (o_mmio_re),
                        //     egyébként on-chip SRAM. Pop a címet, a beolvasott
                        //     érték push-ja ST_MEM_WAIT phase 1-ben. Az SRAM-ágon
                        //     bounds check (C# ExecuteLdindI4 paritás; negatív
                        //     cím is trap, mert előjel nélküli összehasonlítás).
                        // en: LDIND.I4 — address comes from TOS (indirect).
                        //     Segment decode (F2.8 #6.2): addr[31:28]==0xF
                        //     (SEG_MMIO) → external MMIO master bus (o_mmio_re),
                        //     otherwise on-chip SRAM. Pop the address, push the
                        //     read value in ST_MEM_WAIT phase 1. SRAM path bounds
                        //     check (parity with C#; negative addr traps unsigned).
                        if (w_sc_tos[31:28] == `SEG_MMIO) begin
                            o_mmio_addr   <= w_sc_tos;
                            o_mmio_re     <= 1'b1;
                            r_mem_is_mmio <= 1'b1;
                            r_sc_pop_en   <= 1'b1;
                            r_state       <= ST_MEM_WAIT;
                        end else if (w_sc_tos > (`SRAM_SIZE_BYTES - 4)) begin
                            o_trap      <= 1'b1;
                            o_trap_code <= `TRAP_INVALID_MEMORY;
                            r_state     <= ST_TRAP;
                        end else begin
                            r_sram_addr   <= w_sc_tos[13:0];
                            r_sram_re     <= 1'b1;
                            r_mem_is_mmio <= 1'b0;
                            r_sc_pop_en   <= 1'b1;
                            r_state       <= ST_MEM_WAIT;
                        end
                    end else if (uc_addr_src == `ADDR_SRC_ARG &&
                        eff_idx >= {3'd0, r_arg_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_ARG;
                        r_state     <= ST_TRAP;
                    end else if (uc_addr_src == `ADDR_SRC_LOCAL &&
                                 eff_idx >= {3'd0, r_local_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_LOCAL;
                        r_state     <= ST_TRAP;
                    end else begin
                        r_sram_addr   <= addr_calc(uc_addr_src, eff_idx);
                        r_sram_re     <= 1'b1;
                        r_mem_is_mmio <= 1'b0;
                        r_state       <= ST_MEM_WAIT;
                    end
                end else if (uc_sram_wr && r_mem_phase == 1'b0) begin
                    // hu: Sub3 — SRAM írás (STARG / STLOC) phase 0:
                    //     range check (mint az olvasásnál), majd pop_en=1
                    //     és cím latch — phase 1-ben írunk.
                    //     A range check megelőzi a pop-ot az ISA spec
                    //     szerinti trap sorrendnek (lásd TExecutor.cs:
                    //     index check BEFORE pop).
                    // en: Sub3 — SRAM write (STARG / STLOC) phase 0:
                    //     range check (same as read), then pop_en=1 and
                    //     latch the address — phase 1 performs the write.
                    //     Range check precedes pop per ISA spec (see
                    //     TExecutor.cs: index check BEFORE pop).
                    if (uc_addr_src == `ADDR_SRC_IND) begin
                        // hu: STIND.I4 phase 0 — cím = TOS-1 (indirekt),
                        //     érték = TOS. Szegmens-dekódolás (F2.8 #6.2):
                        //     addr[31:28]==0xF (SEG_MMIO) → MMIO master busz
                        //     (phase 1: o_mmio_we), egyébként SRAM. Pop az
                        //     értéket (phase 1-ben w_sc_pop_data-ként érvényes),
                        //     a címet latch-eljük. A cím-pop (2.) phase 1-ben.
                        //     SRAM-ágon bounds check (C# ExecuteStindI4 paritás).
                        // en: STIND.I4 phase 0 — address = TOS-1 (indirect),
                        //     value = TOS. Segment decode (F2.8 #6.2):
                        //     addr[31:28]==0xF (SEG_MMIO) → MMIO master bus
                        //     (phase 1: o_mmio_we), otherwise SRAM. Pop the value
                        //     (w_sc_pop_data in phase 1), latch the address. The
                        //     address pop (2nd) is in phase 1. SRAM path bounds
                        //     check (parity with C#).
                        if (w_sc_tos1[31:28] == `SEG_MMIO) begin
                            r_mmio_addr_latched <= w_sc_tos1;
                            r_mem_is_mmio       <= 1'b1;
                            r_sc_pop_en         <= 1'b1;
                            r_mem_phase         <= 1'b1;
                        end else if (w_sc_tos1 > (`SRAM_SIZE_BYTES - 4)) begin
                            o_trap      <= 1'b1;
                            o_trap_code <= `TRAP_INVALID_MEMORY;
                            r_state     <= ST_TRAP;
                        end else begin
                            r_mem_addr_latched <= w_sc_tos1[13:0];
                            r_mem_is_mmio      <= 1'b0;
                            r_sc_pop_en        <= 1'b1;
                            r_mem_phase        <= 1'b1;
                        end
                    end else if (uc_addr_src == `ADDR_SRC_ARG &&
                        eff_idx >= {3'd0, r_arg_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_ARG;
                        r_state     <= ST_TRAP;
                    end else if (uc_addr_src == `ADDR_SRC_LOCAL &&
                                 eff_idx >= {3'd0, r_local_count}) begin
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_LOCAL;
                        r_state     <= ST_TRAP;
                    end else begin
                        r_mem_addr_latched <= addr_calc(uc_addr_src, eff_idx);
                        r_mem_is_mmio      <= 1'b0;
                        r_sc_pop_en        <= 1'b1;
                        r_mem_phase        <= 1'b1;
                    end
                end else if (uc_sram_wr && r_mem_phase == 1'b1) begin
                    // hu: Sub3 — írás phase 1: a Stack Cache 1-ciklus
                    //     regisztrált pop_data-ját a célra írjuk. A cél a
                    //     phase 0-ban dekódolt szegmens: r_mem_is_mmio=1 →
                    //     külső MMIO master busz (o_mmio_we), egyébként on-chip
                    //     SRAM. Ezután uc_done flow + ST_FETCH.
                    // en: Sub3 — write phase 1: write the Stack Cache's 1-cycle
                    //     registered pop_data to the target. The target is the
                    //     segment decoded in phase 0: r_mem_is_mmio=1 → external
                    //     MMIO master bus (o_mmio_we), otherwise on-chip SRAM.
                    //     Then uc_done flow + ST_FETCH.
                    if (r_mem_is_mmio) begin
                        o_mmio_addr  <= r_mmio_addr_latched;
                        o_mmio_wdata <= w_sc_pop_data;
                        o_mmio_we    <= 1'b1;
                    end else begin
                        r_sram_addr  <= r_mem_addr_latched;
                        r_sram_wdata <= w_sc_pop_data;
                        r_sram_we    <= 1'b1;
                    end
                    r_mem_phase  <= 1'b0;
                    if (uc_addr_src == `ADDR_SRC_IND) begin
                        // hu: STIND 2. pop — a cím (az érték phase 0-beli
                        //     pop-ja után már a TOS-on van). STARG/STLOC csak
                        //     1× pop-ol, ezért IND-feltételhez kötjük.
                        // en: STIND 2nd pop — the address (now on TOS after the
                        //     value was popped in phase 0). STARG/STLOC pop only
                        //     once, hence gated on the IND condition.
                        r_sc_pop_en <= 1'b1;
                    end
                    if (uc_pc_wr) begin
                        r_pc          <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        r_next_fetch_addr <= pc_next;
                    end
                    r_step  <= 4'd0;
                    r_state <= ST_FETCH;
                end else begin
                    // hu: Stack műveletek a vezérlőszó alapján
                    if (uc_stack_pop > 2'd0) begin
                        r_sc_pop_en <= 1'b1;
                    end
                    if (uc_stack_push) begin
                        r_sc_push_en <= 1'b1;
                        case (uc_push_src)
                            `PUSH_SRC_IMM: r_sc_push_data <= push_data_imm;
                            `PUSH_SRC_TOS: r_sc_push_data <= w_sc_tos;
                            default:       r_sc_push_data <= 32'd0;
                        endcase
                    end

                    // hu: RET (UC_HALT=1, UC_FRAME_POP=1, UC_PC_SRC=PC_SRC_RET)
                    //     A microcode 2-step: step 0 = pop return value
                    //     (cond_pop), step 1 = halt/frame_pop (UC_DONE=1).
                    //     Step 1 ciklusban a w_sc_pop_data tartalmazza a
                    //     step 0-ban pop-olt return value-t (Stack Cache
                    //     1-ciklus regisztrált pop_data).
                    //     Sub1-ben: csak root frame (call_depth==1) → halt.
                    //     Nem-root call_depth Sub2-re marad.
                    // en: RET — microcode is 2-step: step 0 pops return
                    //     value (cond_pop), step 1 halts (UC_DONE=1).
                    //     On step 1, w_sc_pop_data holds the value popped
                    //     on step 0 (Stack Cache's 1-cycle registered
                    //     pop_data). Sub1: only root frame (call_depth==1)
                    //     halts; non-root call_depth deferred to Sub2.
                    if (uc_done && uc_halt_en && uc_frame_pop) begin
                        if (r_call_depth == 10'd1) begin
                            o_halt  <= 1'b1;
                            // hu: A return_value a step 0-ban pop-olt érték,
                            //     ami most a w_sc_pop_data-n érvényes.
                            //     Ha az eval stack üres volt step 0-ban,
                            //     a Stack Cache trap-pet ad — itt nem.
                            o_return_value <= w_sc_pop_data;
                            r_state <= ST_HALT;
                        end else begin
                            // hu: Sub5 — non-root frame pop → ST_RET szekvencia.
                            //     A return value a step 0-ban pop-olt érték
                            //     (w_sc_pop_data); elmentjük r_ret_value-be.
                            //     Az SRAM read indítása itt: [FP+0] = ReturnPC.
                            // en: Sub5 — non-root frame pop → ST_RET sequence.
                            //     Return value latched from step 0 pop_data.
                            //     Initiate SRAM read of [FP+0] = ReturnPC.
                            r_ret_value     <= w_sc_pop_data;
                            r_callee_old_fp <= r_fp;
                            r_sram_addr     <= r_fp;
                            r_sram_re       <= 1'b1;
                            r_ret_sub       <= RET_REQ_RPC;
                            r_state         <= ST_RET;
                        end
                    end else if (uc_frame_push) begin
                        // hu: Sub5 — CALL → ST_CALL szekvencia.
                        //     A microcode 1-step (UC_DONE + UC_FRAME_PUSH +
                        //     UC_PC_WR + UC_PC_SRC=PC_SRC_CALL). A teljes
                        //     frame felépítést a top-level végzi több
                        //     ciklus alatt: header read QSPI-ról, validáció,
                        //     args reverse-pop a Stack Cache-ből, header
                        //     write az új frame-be, locals nullázás,
                        //     regiszterek és Stack Cache reset.
                        //     A return_pc = r_pc + r_length (5 byte: 1 op
                        //     + 4 byte RVA). Az új FP = caller r_sp (a
                        //     caller frame vége, ami egyben a callee frame
                        //     kezdete).
                        // en: Sub5 — CALL → ST_CALL sequence.
                        //     Microcode is 1-step (UC_DONE + UC_FRAME_PUSH +
                        //     UC_PC_WR + UC_PC_SRC=PC_SRC_CALL). The full
                        //     frame setup runs in the top-level FSM across
                        //     multiple cycles: header read from QSPI,
                        //     validation, args reverse-pop from Stack Cache,
                        //     header write into the new frame, locals zero,
                        //     register and Stack Cache reset.
                        //     return_pc = r_pc + r_length (5 byte). New FP =
                        //     caller r_sp (caller frame end = callee frame
                        //     start).
                        r_call_target_rva <= r_operand[23:0];
                        r_return_pc       <= r_pc + {21'd0, r_length};
                        // hu: F2.7.D — FP_new a CALL_VALIDATE-ben dől el
                        //     (kell hozzá a callee arg_count). A caller
                        //     eval mélységét (args-szal) ITT latch-eljük,
                        //     mielőtt bármi pop/flush történne.
                        // en: F2.7.D — FP_new decided in CALL_VALIDATE
                        //     (needs callee arg_count). Latch the caller
                        //     eval depth (incl. args) HERE, before any
                        //     pop/flush.
                        r_call_total_depth <= w_sc_depth;
                        r_arg_pop_idx     <= 5'd0;
                        r_local_zero_idx  <= 5'd0;
                        r_call_sub        <= CALL_HDR_REQ;
                        r_state           <= ST_CALL;
                    end else if (uc_done) begin
                        // hu: Normal opcode befejezés — PC update + buffer
                        //     csúsztatás (warm-path optimalizáció). Branch/call
                        //     esetén full flush. A csúsztatás explicit `case
                        //     (r_length)`-szel — a generic `for` loop +
                        //     dynamic index Verilator regiszter-array-en
                        //     nem viselkedik megbízhatóan.
                        //     Sub4 — 1-operand branch (BRFALSE/BRTRUE):
                        //     a fall-through esetén (cond_en=1, branch
                        //     nem teljesül) pc_next-et felülírjuk pc+len-re.
                        // en: Normal opcode end — PC update + buffer slide-down
                        //     (warm-path opt). On branch/call we full-flush.
                        //     Sub4 — 1-operand branch: on fall-through, override
                        //     pc_next with pc+len (no taken).
                        if (uc_pc_wr) begin
                            if (uc_cond_en && (uc_stack_pop == 2'd1) &&
                                !branch_taken_1op) begin
                                // hu: BRFALSE_S/BRTRUE_S nem teljesült feltétel
                                //     → fall-through, NEM branch.
                                // en: BRFALSE_S/BRTRUE_S condition false →
                                //     fall-through, no branch.
                                r_pc          <= r_pc + {21'd0, r_length};
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= r_pc + {21'd0, r_length};
                                r_next_fetch_addr <= r_pc + {21'd0, r_length};
                            end else if (branch_target_invalid) begin
                                // hu: Sub4 hiánypótlás — BR_S / BRFALSE_S /
                                //     BRTRUE_S taken ágban negatív cél
                                //     → TRAP_INVALID_BRANCH a PC update
                                //     előtt. (A 2-op branchet külön kezeljük
                                //     a phase 1 ágban.)
                                // en: Sub4 hardening — BR_S / BRFALSE_S /
                                //     BRTRUE_S taken with negative target
                                //     → TRAP_INVALID_BRANCH before PC update.
                                //     (2-op branch is handled in phase 1.)
                                o_trap      <= 1'b1;
                                o_trap_code <= `TRAP_INVALID_BRANCH;
                                r_state     <= ST_TRAP;
                            end else if (uc_pc_src != `PC_SRC_NEXT) begin
                                r_pc <= pc_next;
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
                                // hu: Sub2.1 — branch/call full-flush:
                                //     a következő fetch pc_next-ről indul.
                                // en: Sub2.1 — branch/call full-flush:
                                //     next fetch starts from pc_next.
                                r_next_fetch_addr <= pc_next;
                            end else if (r_fetch_count >= {1'b0, r_length}) begin
                                r_pc <= pc_next;
                                // hu: Packed buffer slide: lefelé (byte 0 a
                                //     legalsó), `r_length * 8` bit jobbra
                                //     shift, felülre 0. Verilator
                                //     megbízhatóan kezeli.
                                //     A warm-path slide NEM állítja
                                //     r_next_fetch_addr-t — az APPEND
                                //     +4-es léptetése független a slide-tól.
                                // en: Packed buffer slide: down-shift by
                                //     r_length*8 bits (byte 0 is LSB), zero
                                //     fill upper. Verilator handles reliably.
                                //     The warm-path slide does NOT touch
                                //     r_next_fetch_addr — APPEND's +4
                                //     bump is independent of slide.
                                case (r_length)
                                    3'd1: r_fetch_buf <= {8'h00,
                                                          r_fetch_buf[63:8]};
                                    3'd2: r_fetch_buf <= {16'h0000,
                                                          r_fetch_buf[63:16]};
                                    3'd3: r_fetch_buf <= {24'h0,
                                                          r_fetch_buf[63:24]};
                                    3'd4: r_fetch_buf <= {32'h0,
                                                          r_fetch_buf[63:32]};
                                    3'd5: r_fetch_buf <= {40'h0,
                                                          r_fetch_buf[63:40]};
                                    default: ;
                                endcase
                                r_fetch_count <=
                                    r_fetch_count - {1'b0, r_length};
                                r_fetch_pc <= r_fetch_pc
                                              + {21'd0, r_length};
                            end else begin
                                // hu: Sub2.1 — slide-vesztett full-flush.
                                // en: Sub2.1 — slide-fallback full-flush.
                                r_fetch_count <= 4'd0;
                                r_fetch_pc    <= pc_next;
                                r_next_fetch_addr <= pc_next;
                            end
                        end
                        r_step <= 4'd0;
                        r_state <= ST_FETCH;
                    end else begin
                        // hu: Multi-step opcode — folytatás
                        r_step <= r_step + 4'd1;
                    end
                end
            end

            // ====================================================
            // ST_MEM_WAIT — Sub3: 2-fázisú SRAM read wait
            //   phase 0: r_sram_rdata_latched még előző érték (NBA).
            //            Ekkor csak phase++.
            //   phase 1: r_sram_rdata_latched már friss → push, PC update,
            //            ST_FETCH.
            //   Verilog NBA: r_sram_re <= 1 cycle X-ben → X+1 ciklus elején
            //   `if (r_sram_re)` lefut → X+2 ciklus elején r_sram_rdata_
            //   latched friss. Ezért 2 ciklus (phase 0 + phase 1) kell.
            // en: ST_MEM_WAIT — Sub3: 2-phase SRAM read wait
            //   phase 0: r_sram_rdata_latched is still old (NBA timing).
            //   phase 1: r_sram_rdata_latched is fresh → push + uc_done.
            // ====================================================
            ST_MEM_WAIT: begin
                if (r_mem_phase == 1'b0) begin
                    r_mem_phase <= 1'b1;
                end else begin
                    r_mem_phase    <= 1'b0;
                    r_sc_push_en   <= 1'b1;
                    // hu: F2.8 #6.2 — a push forrása a phase 0-ban dekódolt
                    //     szegmens: MMIO read → i_mmio_rdata (a slave az
                    //     o_mmio_re utáni ciklusban regisztrálva hajtja),
                    //     egyébként az SRAM 1-ciklusos latched olvasása.
                    // en: F2.8 #6.2 — push source per the segment decoded in
                    //     phase 0: MMIO read → i_mmio_rdata (slave drives it
                    //     registered the cycle after o_mmio_re), otherwise the
                    //     SRAM's 1-cycle latched read.
                    r_sc_push_data <= r_mem_is_mmio ? i_mmio_rdata
                                                    : r_sram_rdata_latched;
                    if (uc_pc_wr) begin
                        r_pc          <= pc_next;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= pc_next;
                        r_next_fetch_addr <= pc_next;
                    end
                    r_step  <= 4'd0;
                    r_state <= ST_FETCH;
                end
            end

            // ====================================================
            // ST_CALL — Sub5 frame manager (CALL szekvencia)
            // hu: Több ciklus alatt felépíti az új callee frame-et az
            //     SRAM-ban. Sub-states (r_call_sub):
            //     0 HDR_REQ      → call_depth check + QSPI read indítása
            //                       a callee header címére
            //     1 HDR_WAIT     → várja a w_qspi_ready-t, magic+arg+local
            //                       latch-elése
            //     2 VALIDATE     → SRAM overflow check (r_sp + frame_size)
            //     3 ARG_POP_REQ  → pop_en=1 (vagy átmenet HDR_WR-be ha 0 arg)
            //     4 ARG_POP_WAIT → várja !w_sc_busy állapotot
            //     5 ARG_POP_WR   → SRAM write a frame [FP+12+i*4] címre
            //     6 HDR_WR_RPC   → [FP+0] = return_pc
            //     7 HDR_WR_PFP   → [FP+4] = prev_fp (régi r_fp)
            //     8 HDR_WR_AL    → [FP+8] = {0, local_count, arg_count}
            //     9 LOCAL_ZERO   → 0 írása minden local slotra
            //    10 FINALIZE     → regiszterek + sc_sp_load + fetch flush
            // en: Builds the new callee frame in SRAM across several cycles.
            // ====================================================
            ST_CALL: begin
                case (r_call_sub)
                    CALL_HDR_REQ: begin
                        // hu: Call depth check (max 512). Itt trap-elünk,
                        //     mielőtt a header read-et kérnénk.
                        // en: Call depth check (max 512). Trap before
                        //     issuing the header read request.
                        if (r_call_depth >= 10'd512) begin
                            o_trap      <= 1'b1;
                            o_trap_code <= `TRAP_CALL_DEPTH_EXCEEDED;
                            r_state     <= ST_TRAP;
                        end else if (!w_qspi_busy && !r_qspi_inflight) begin
                            // hu: QSPI szabad → új request a header címére
                            //     (4 byte word: magic + arg + local + max).
                            // en: QSPI idle → request header word
                            //     (4 bytes: magic + arg + local + max).
                            r_qspi_addr     <= r_call_target_rva;
                            r_qspi_re       <= 1'b1;
                            r_qspi_inflight <= 1'b1;
                            r_call_sub      <= CALL_HDR_WAIT;
                        end
                    end

                    CALL_HDR_WAIT: begin
                        if (w_qspi_ready) begin
                            r_qspi_inflight <= 1'b0;
                            // hu: w_qspi_rdata layout (lásd a fetch
                            //     byte-swapot): [31:24] = byte at addr
                            //     (magic), [23:16] = arg_count, [15:8] =
                            //     local_count, [7:0] = max_stack.
                            // en: See fetch byte-swap: [31:24] = magic,
                            //     [23:16] = arg_count, [15:8] = local_count,
                            //     [7:0] = max_stack.
                            if (w_qspi_rdata[31:24] != 8'hFE) begin
                                o_trap      <= 1'b1;
                                o_trap_code <= `TRAP_INVALID_CALL_TARGET;
                                r_state     <= ST_TRAP;
                            end else begin
                                r_new_arg_count   <= w_qspi_rdata[20:16];
                                r_new_local_count <= w_qspi_rdata[12:8];
                                r_call_sub        <= CALL_VALIDATE;
                            end
                        end
                    end

                    CALL_VALIDATE: begin
                        // hu: F2.7.D — D = total (args-szal) - callee arg.
                        //     FP_new a caller eval TETEJE fölé (a held D
                        //     elem fölé), NEM a caller eval bázisra, hogy a
                        //     callee frame ne írja felül a megőrzött
                        //     értékeket. caller_eval_base = r_sp.
                        // en: F2.7.D — D = total (incl. args) - callee arg.
                        //     FP_new ABOVE the caller's held eval, not at
                        //     the eval base.
                        r_caller_eval_d <= r_call_total_depth -
                                           {2'd0, r_new_arg_count};
                        r_new_fp        <= r_sp +
                            {5'd0,
                             (r_call_total_depth - {2'd0, r_new_arg_count}),
                             2'd0};
                        // hu: SRAM overflow: FP_new + frame_size > 16384.
                        // en: SRAM overflow: FP_new + frame_size > 16384.
                        if ({1'b0, r_sp} +
                            {1'b0,
                             {5'd0,
                              (r_call_total_depth - {2'd0, r_new_arg_count}),
                              2'd0}} +
                            {1'b0, 14'd12} +
                            {8'd0, r_new_arg_count, 2'd0} +
                            {8'd0, r_new_local_count, 2'd0} > 15'h4000) begin
                            o_trap      <= 1'b1;
                            o_trap_code <= `TRAP_SRAM_OVERFLOW;
                            r_state     <= ST_TRAP;
                        end else begin
                            r_call_sub <= CALL_FLUSH;
                        end
                    end

                    CALL_FLUSH: begin
                        // hu: F2.7.D — a caller TELJES eval stack-jét (cache
                        //     + spilled) SRAM-ba ürítjük: a held elemek így
                        //     biztonságosan SRAM-ban (FP_new alatt), a callee
                        //     tiszta cache-sel indul. flush_en SZINTVEZÉRELT
                        //     — tartjuk, míg cache_count==0 és !busy. Üres
                        //     cache → azonnali no-op.
                        // en: F2.7.D — flush caller's ENTIRE eval stack
                        //     (cache + spilled) to SRAM; preserved items end
                        //     up in SRAM below FP_new, callee starts clean.
                        //     flush_en level-held until cache_count==0 &&
                        //     !busy. Empty cache → immediate no-op.
                        if (w_sc_cc == 3'd0 && !w_sc_busy) begin
                            r_call_sub <= CALL_ARG_POP_REQ;
                        end else begin
                            r_sc_flush <= 1'b1;
                        end
                    end

                    CALL_ARG_POP_REQ: begin
                        // hu: F2.7.D — args SRAM→SRAM másolás a flush UTÁN.
                        //     SRAM[FP_new + j*4] = arg j (j=0..N-1). Cél:
                        //     callee slot [FP_new+12 + j*4]. j = N-1-idx
                        //     (csökkenő) — a dst=src+12 felülírás és a
                        //     header-írás így nem ütközik.
                        // en: F2.7.D — SRAM→SRAM arg copy AFTER flush.
                        //     SRAM[FP_new + j*4] → callee slot
                        //     [FP_new+12 + j*4]. j descending avoids clobber.
                        if (r_arg_pop_idx >= r_new_arg_count) begin
                            r_call_sub <= CALL_HDR_WR_RPC;
                        end else begin
                            r_sram_addr <= r_new_fp +
                                {7'd0,
                                 (r_new_arg_count - 5'd1 - r_arg_pop_idx),
                                 2'd0};
                            r_sram_re   <= 1'b1;
                            r_call_sub  <= CALL_ARG_POP_WAIT;
                        end
                    end

                    CALL_ARG_POP_WAIT: begin
                        // hu: SRAM read 2-ciklus latencia (bridge).
                        // en: SRAM read 2-cycle latency (bridge).
                        r_call_sub <= CALL_ARG_POP_WR;
                    end

                    CALL_ARG_POP_WR: begin
                        // hu: r_sram_rdata_latched = arg j → callee slot.
                        //     Cím = FP_new + 12 + (N-1-idx)*4.
                        // en: r_sram_rdata_latched = arg j → callee slot.
                        r_sram_addr  <= r_new_fp + 14'd12 +
                                        {7'd0,
                                         (r_new_arg_count - 5'd1 - r_arg_pop_idx),
                                         2'd0};
                        r_sram_wdata <= r_sram_rdata_latched;
                        r_sram_we    <= 1'b1;
                        r_arg_pop_idx <= r_arg_pop_idx + 5'd1;
                        r_call_sub    <= CALL_ARG_POP_REQ;
                    end

                    CALL_HDR_WR_RPC: begin
                        r_sram_addr  <= r_new_fp;            // [FP+0]
                        r_sram_wdata <= {8'd0, r_return_pc};
                        r_sram_we    <= 1'b1;
                        r_call_sub   <= CALL_HDR_WR_PFP;
                    end

                    CALL_HDR_WR_PFP: begin
                        r_sram_addr  <= r_new_fp + 14'd4;    // [FP+4]
                        r_sram_wdata <= {18'd0, r_fp};
                        r_sram_we    <= 1'b1;
                        r_call_sub   <= CALL_HDR_WR_AL;
                    end

                    CALL_HDR_WR_AL: begin
                        r_sram_addr  <= r_new_fp + 14'd8;    // [FP+8]
                        r_sram_wdata <= {16'd0,
                                         3'd0, r_new_local_count,
                                         3'd0, r_new_arg_count};
                        r_sram_we    <= 1'b1;
                        r_call_sub   <= CALL_SAVE_D;
                    end

                    CALL_SAVE_D: begin
                        // hu: F2.7.D — a CALLER header [r_fp+8] reserved
                        //     bitjeibe ([22:16]) mentjük a megőrzött eval
                        //     depth-et (D). RET-kor innen olvassuk vissza.
                        //     A caller arg/local count alsó bitjei
                        //     változatlanok (r_fp még a caller-é).
                        // en: F2.7.D — save preserved eval depth D into the
                        //     CALLER header [r_fp+8] reserved bits [22:16].
                        //     RET reads it back. Caller arg/local low bits
                        //     unchanged (r_fp still the caller's).
                        r_sram_addr  <= r_fp + 14'd8;
                        r_sram_wdata <= {9'd0, r_caller_eval_d,
                                         3'd0, r_local_count,
                                         3'd0, r_arg_count};
                        r_sram_we    <= 1'b1;
                        if (r_new_local_count > 5'd0) begin
                            r_local_zero_idx <= 5'd0;
                            r_call_sub <= CALL_LOCAL_ZERO;
                        end else begin
                            r_call_sub <= CALL_FINALIZE;
                        end
                    end

                    CALL_LOCAL_ZERO: begin
                        // hu: Locals nullázása: [FP_new + 12 + arg*4 + i*4]
                        // en: Zero locals: [FP_new + 12 + arg*4 + i*4]
                        r_sram_addr  <= r_new_fp + 14'd12 +
                                        {7'd0, r_new_arg_count, 2'd0} +
                                        {7'd0, r_local_zero_idx, 2'd0};
                        r_sram_wdata <= 32'd0;
                        r_sram_we    <= 1'b1;
                        r_local_zero_idx <= r_local_zero_idx + 5'd1;
                        if (r_local_zero_idx + 5'd1 >= r_new_local_count) begin
                            r_call_sub <= CALL_FINALIZE;
                        end
                    end

                    CALL_FINALIZE: begin
                        // hu: Regiszterek frissítése a callee context-re,
                        //     fetch flush, Stack Cache reset üres eval-re.
                        // en: Update registers to callee context, fetch flush,
                        //     Stack Cache reset to empty eval.
                        r_fp          <= r_new_fp;
                        r_sp          <= r_new_fp + 14'd12 +
                                         {7'd0, r_new_arg_count, 2'd0} +
                                         {7'd0, r_new_local_count, 2'd0};
                        r_arg_count   <= r_new_arg_count;
                        r_local_count <= r_new_local_count;
                        r_call_depth  <= r_call_depth + 10'd1;
                        r_pc          <= r_call_target_rva + 24'd8;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= r_call_target_rva + 24'd8;
                        r_next_fetch_addr <= r_call_target_rva + 24'd8;
                        r_qspi_inflight <= 1'b0;
                        r_sc_sp_load <= 1'b1;
                        r_sc_sp_init <= r_new_fp + 14'd12 +
                                        {7'd0, r_new_arg_count, 2'd0} +
                                        {7'd0, r_new_local_count, 2'd0};
                        // hu: F2.7.D — a callee üres eval-lal indul.
                        // en: F2.7.D — callee starts with empty eval.
                        r_sc_sp_depth <= 7'd0;
                        r_state <= ST_FETCH;
                    end

                    default: begin
                        r_state <= ST_TRAP;
                        o_trap  <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_OPCODE;
                    end
                endcase
            end

            // ====================================================
            // ST_RET — Sub5 frame manager (RET szekvencia)
            // hu: Sub-states (r_ret_sub):
            //     0 REQ_RPC    → SRAM read már lefutott (ST_EXECUTE indította
            //                    [FP+0] = ReturnPC). Csak átmenet.
            //     1 WAIT_RPC   → 2-cycle SRAM latency: várjuk a friss adatot.
            //     2 LATCH_RPC  → r_ret_return_pc latch + [FP+4] read indítás.
            //     3 WAIT_PFP   → 2-cycle latency.
            //     4 LATCH_PFP  → r_ret_prev_fp latch + [prev_fp+8] read.
            //     5 WAIT_AL    → 2-cycle latency.
            //     6 LATCH_AL   → caller arg/local count latch.
            //     7 FINALIZE   → regiszterek caller-re + Stack Cache reset
            //                    a caller eval bázisra.
            //     8 PUSH_RV    → return value push a Stack Cache-be →
            //                    ST_FETCH (caller folytatása).
            // en: Frame pop sequence: 3× SRAM read (return_pc, prev_fp,
            //     caller arg/local), then register/SP updates, push return
            //     value back to caller eval stack.
            // ====================================================
            ST_RET: begin
                case (r_ret_sub)
                    RET_REQ_RPC: begin
                        // hu: ST_EXECUTE már r_sram_re=1-et adott a [FP+0]-re.
                        //     A 2-cycle latency miatt 1 cycle várás itt.
                        // en: ST_EXECUTE already issued the read; here we
                        //     just bridge the 1st of 2 cycles of latency.
                        r_ret_sub <= RET_WAIT_RPC;
                    end

                    RET_WAIT_RPC: begin
                        r_ret_sub <= RET_LATCH_RPC;
                    end

                    RET_LATCH_RPC: begin
                        r_ret_return_pc <= r_sram_rdata_latched[23:0];
                        r_sram_addr <= r_callee_old_fp + 14'd4;  // [FP+4]
                        r_sram_re   <= 1'b1;
                        r_ret_sub   <= RET_WAIT_PFP;
                    end

                    RET_WAIT_PFP: begin
                        r_ret_sub <= RET_LATCH_PFP;
                    end

                    RET_LATCH_PFP: begin
                        r_ret_prev_fp <= r_sram_rdata_latched[13:0];
                        // hu: Indítsuk a [prev_fp + 8] olvasást azonnal,
                        //     a friss r_sram_rdata_latched-ből nyerjük a
                        //     prev_fp-t (a regiszter NBA miatt 1 cycle
                        //     múlva érvényes, de a kombinációs cím
                        //     számítás itt érvényes).
                        // en: Start [prev_fp + 8] read using the freshly
                        //     latched value (combinational use is OK).
                        r_sram_addr <= r_sram_rdata_latched[13:0] + 14'd8;
                        r_sram_re   <= 1'b1;
                        r_ret_sub   <= RET_WAIT_AL;
                    end

                    RET_WAIT_AL: begin
                        r_ret_sub <= RET_LATCH_AL;
                    end

                    RET_LATCH_AL: begin
                        // hu: byte 0 = arg_count, byte 1 = local_count
                        //     ([FP+8]: {reserved, local_count, arg_count}).
                        //     F2.7.D — bits[22:16] = a CALL-kor mentett
                        //     caller eval depth (D), visszaolvasva.
                        // en: byte 0 = arg_count, byte 1 = local_count.
                        //     F2.7.D — bits[22:16] = caller eval depth (D)
                        //     saved at CALL, read back here.
                        r_arg_count    <= r_sram_rdata_latched[4:0];
                        r_local_count  <= r_sram_rdata_latched[12:8];
                        r_ret_caller_d <= r_sram_rdata_latched[22:16];
                        r_ret_sub      <= RET_FINALIZE;
                    end

                    RET_FINALIZE: begin
                        // hu: Regiszterek caller context-re. A r_arg_count
                        //     és r_local_count NBA-zott — a RET_FINALIZE
                        //     ciklusában már a friss caller értékek.
                        //     A callee SRAM (r_callee_old_fp .. r_sp-ig)
                        //     felszabadul.
                        // en: Registers reset to caller context. r_arg_count
                        //     and r_local_count are NBA-fresh by this cycle.
                        //     Callee SRAM region freed.
                        r_pc          <= r_ret_return_pc;
                        r_fp          <= r_ret_prev_fp;
                        // hu: F2.7.D — r_sp a caller eval BÁZISA (a frame
                        //     eval-pointer regiszter), NEM a callee old fp.
                        // en: F2.7.D — r_sp = caller eval BASE (frame eval
                        //     pointer), not the callee old fp.
                        r_sp          <= r_ret_prev_fp + 14'd12 +
                                         {7'd0, r_arg_count, 2'd0} +
                                         {7'd0, r_local_count, 2'd0};
                        r_call_depth  <= r_call_depth - 10'd1;
                        r_fetch_count <= 4'd0;
                        r_fetch_pc    <= r_ret_return_pc;
                        r_next_fetch_addr <= r_ret_return_pc;
                        r_qspi_inflight <= 1'b0;
                        // hu: F2.7.D — Stack Cache a caller eval bázisra,
                        //     a megőrzött eval depth-tel (D). A held elemek
                        //     az SRAM-ban [base .. base+D*4) — a Stack Cache
                        //     onnan tölti vissza pop-kor. A return value
                        //     push külön ciklusban (RET_PUSH_RV).
                        // en: F2.7.D — Stack Cache to caller eval base WITH
                        //     the preserved eval depth (D). Held items live
                        //     in SRAM [base .. base+D*4); the cache fills
                        //     them back on pop. RV push in a separate cycle.
                        r_sc_sp_load <= 1'b1;
                        r_sc_sp_init <= r_ret_prev_fp + 14'd12 +
                                        {7'd0, r_arg_count, 2'd0} +
                                        {7'd0, r_local_count, 2'd0};
                        r_sc_sp_depth <= r_ret_caller_d;
                        r_ret_sub <= RET_WAIT_SPFILL;
                    end

                    RET_WAIT_SPFILL: begin
                        // hu: 1-ciklus bridge: a sp_load-ot a Stack Cache
                        //     ebben a ciklusban dolgozza fel; ST_SPFILL a
                        //     KÖVETKEZŐ ciklusban indul (busy=1). A
                        //     RET_PUSH_RV !w_sc_busy őre így érvényes.
                        // en: 1-cycle bridge: SC processes sp_load this
                        //     cycle; ST_SPFILL starts NEXT cycle (busy=1),
                        //     so the RET_PUSH_RV !w_sc_busy guard is valid.
                        r_ret_sub <= RET_PUSH_RV;
                    end

                    RET_PUSH_RV: begin
                        // hu: F2.7.D — várjuk az ST_SPFILL befejezését
                        //     (a caller held eval cache-újratöltése a
                        //     sp_load(depth) hatására), MIELŐTT push-olunk.
                        //     A return value push a caller eval tetejére,
                        //     majd ST_FETCH.
                        // en: F2.7.D — wait for ST_SPFILL to finish (the
                        //     caller held-eval cache refill from
                        //     sp_load(depth)) BEFORE pushing the return
                        //     value, then ST_FETCH.
                        if (!w_sc_busy) begin
                            r_sc_push_en   <= 1'b1;
                            r_sc_push_data <= r_ret_value;
                            r_state        <= ST_FETCH;
                        end
                    end

                    default: begin
                        r_state <= ST_TRAP;
                        o_trap  <= 1'b1;
                        o_trap_code <= `TRAP_INVALID_OPCODE;
                    end
                endcase
            end

            // ====================================================
            // hu: ST_DIV_WAIT — a szekvenciális osztó (cilcpu_divider)
            //     o_done-jára vár. Az r_div_start 1-ciklusos pulzus
            //     elindította a divider-t az ST_EXECUTE phase 0 átmenetben;
            //     amint w_div_done magas, a phase 0 záró műveletei (trap-
            //     ellenőrzés, eredmény-latch, pop1, phase 1) lefutnak, és
            //     visszatérünk ST_EXECUTE-ba a phase 1-re (replace_top).
            // en: ST_DIV_WAIT — waits for the sequential divider's
            //     (cilcpu_divider) o_done. The r_div_start 1-cycle pulse
            //     launched the divider at the ST_EXECUTE phase-0 entry;
            //     once w_div_done goes high, the phase-0 closing actions
            //     (trap check, result latch, pop1, phase 1) run, and we
            //     return to ST_EXECUTE for phase 1 (replace_top).
            // ====================================================
            ST_DIV_WAIT: begin
                if (w_div_done) begin
                    if (w_div_trap_div_zero) begin
                        // hu: Osztó nulla → div-by-zero trap (DIV és REM is).
                        // en: Divisor zero → div-by-zero trap (both DIV and REM).
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_DIV_BY_ZERO;
                        r_state     <= ST_TRAP;
                    end else if (w_div_trap_overflow && !r_div_is_rem) begin
                        // hu: INT_MIN / -1 → DIV-overflow trap. REM-re NEM
                        //     trap (a divider o_remainder=0-t ad, ami a
                        //     spec szerint a helyes INT_MIN % -1 eredmény).
                        // en: INT_MIN / -1 → DIV overflow trap. NOT a trap
                        //     for REM (the divider returns o_remainder=0,
                        //     which per spec is the correct INT_MIN % -1
                        //     result).
                        o_trap      <= 1'b1;
                        o_trap_code <= `TRAP_OVERFLOW;
                        r_state     <= ST_TRAP;
                    end else begin
                        // hu: Normál befejezés — phase 0 záró műveletei:
                        //     eredmény-latch (hányados DIV-re, maradék
                        //     REM-re), pop1, phase 1 jelzés, vissza
                        //     ST_EXECUTE-ba a replace_top-ra.
                        // en: Normal completion — phase-0 closing actions:
                        //     result latch (quotient for DIV, remainder
                        //     for REM), pop1, signal phase 1, back to
                        //     ST_EXECUTE for the replace_top.
                        r_alu_result_latched <= r_div_is_rem ? w_div_remainder : w_div_quotient;
                        r_sc_pop_en <= 1'b1;
                        r_alu_phase <= 2'd1;
                        r_state     <= ST_EXECUTE;
                    end
                end
                // hu: Egyébként várunk; r_div_start a default-each-cycle
                //     blokkban már 0-ra állt, így a divider nyugodtan fut.
                // en: Otherwise we wait; r_div_start was already cleared
                //     by the default-each-cycle block, so the divider
                //     runs undisturbed.
            end

            // ====================================================
            // hu: ST_MUL_WAIT — a szekvenciális szorzó (cilcpu_multiplier)
            //     o_done-jára vár. Az r_mul_start 1-ciklusos pulzus
            //     elindította a szorzót az ST_EXECUTE phase 0 átmenetben;
            //     amint w_mul_done magas, a phase 0 záró műveletei (eredmény-
            //     latch, pop1, phase 1) lefutnak, és visszatérünk ST_EXECUTE-ba
            //     a phase 1-re (replace_top). A MUL binary, nincs trap.
            // en: ST_MUL_WAIT — waits for the sequential multiplier's
            //     (cilcpu_multiplier) o_done. The r_mul_start 1-cycle pulse
            //     launched the multiplier at the ST_EXECUTE phase-0 entry;
            //     once w_mul_done goes high, the phase-0 closing actions
            //     (result latch, pop1, phase 1) run, and we return to
            //     ST_EXECUTE for phase 1 (replace_top). MUL is binary, no trap.
            // ====================================================
            ST_MUL_WAIT: begin
                if (w_mul_done) begin
                    r_alu_result_latched <= w_mul_product;
                    r_sc_pop_en <= 1'b1;
                    r_alu_phase <= 2'd1;
                    r_state     <= ST_EXECUTE;
                end
                // hu: Egyébként várunk; r_mul_start már 0-ra állt a
                //     default-each-cycle blokkban, a szorzó nyugodtan fut.
                // en: Otherwise we wait; r_mul_start was already cleared
                //     by the default-each-cycle block, so the multiplier
                //     runs undisturbed.
            end

            // ====================================================
            // ST_HALT — végállapot, latch
            // ====================================================
            ST_HALT: begin
                o_halt <= 1'b1;
            end

            // ====================================================
            // ST_TRAP — végállapot, o_trap 1-ciklus pulzus után 0
            // ====================================================
            ST_TRAP: begin
                o_trap <= 1'b0;
                // hu: o_trap_code latch-ben marad
            end

            default: begin
                r_state <= ST_RESET;
            end
            endcase
        end
    end

endmodule

`default_nettype wire
