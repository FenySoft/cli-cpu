// hu: CLI-CPU F2.3 Stack Cache — 4-elemű TOS cache SRAM spill/fill támogatással.
//     A teljes eval stack max. mélysége 64 (MAX_STACK_DEPTH). A felsőbb microcode
//     felé transzparens: push_en, pop_en, dup_en, swap_en, replace_top_en jelekkel
//     vezérelhető. SPILL/FILL állapot sram_ready handshake-kel szinkronizálva.
//
//     Kimenet stratégia:
//     - tos, tos1, cache_count, depth, pop_data: KOMBINÁCIÓS next-value kimenetek.
//       Láthatók a cocotb/Verilator RisingEdge callbackben, NBA settlement előtt.
//     - trap, trap_code: REGISZTRÁLT (1 ciklusos pulzus, self-clearing).
//     - busy, ready: kombinációs az r_state-ből.
//
//     SRAM: KIZÁRÓLAG külső portokon át (sram_we/re/addr/wdata/rdata/ready).
//     A modul SAJÁT belső tárolóval NEM rendelkezik — ez biztosítja a Tiny Tapeout
//     területbüdzsé tartását, az F2.4 QSPI vezérlő integrációját és az F4 multi-core
//     skálázódást. A tesztkörnyezet `sram_behavior_model` koroutinja biztosítja
//     a memória szemantikát.
//
// en: CLI-CPU F2.3 Stack Cache — 4-element TOS cache with SRAM spill/fill support.
//     Total eval stack max depth 64 (MAX_STACK_DEPTH). Transparent to upper microcode.
//     SPILL/FILL state synchronized with sram_ready handshake.
//
//     Output strategy:
//     - tos, tos1, cache_count, depth, pop_data: COMBINATIONAL next-value outputs.
//       Visible in cocotb/Verilator RisingEdge callback before NBA settlement.
//     - trap, trap_code: REGISTERED (1-cycle pulse, self-clearing).
//     - busy, ready: combinational from r_state.
//
//     SRAM: EXTERNAL ports ONLY (sram_we/re/addr/wdata/rdata/ready). The module
//     has NO internal storage — required for Tiny Tapeout area budget,
//     F2.4 QSPI controller integration, and F4 multi-core scaling. The cocotb
//     `sram_behavior_model` coroutine provides the memory semantics in tests.

`include "cilcpu_defines.vh"

module cilcpu_stack_cache (
    // hu: Órajel és reset
    // en: Clock and reset
    input  wire        clk,
    input  wire        rst_n,

    // hu: SP betöltés (frame setup). sp_depth = a betöltendő frame eval
    //     mélysége szóban (RET-kor a caller megőrzött eval depth-je; CALL /
    //     boot esetén 0 = üres eval). sp_load ÜRÍTI a cache-t (cache_count
    //     <= 0) — a megőrzendő elemek az SRAM-ban élnek (lásd flush_en).
    // en: SP load (frame setup). sp_depth = the loaded frame's eval depth
    //     in words (the caller's preserved eval depth on RET; 0 = empty
    //     eval for CALL / boot). sp_load CLEARS the cache (cache_count <=
    //     0) — preserved items live in SRAM (see flush_en).
    input  wire        sp_load,
    input  wire [13:0] sp_init,
    input  wire [6:0]  sp_depth,

    // hu: Cache flush SRAM-ba (CALL előtt): minden cache-elt elemet
    //     kiír az SRAM-ba (a legmélyebb a legalacsonyabb címre),
    //     r_sp-t feljebb lépteti, cache_count <= 0. A `depth` invariáns
    //     a flush alatt (cache→SRAM transzfer).
    // en: Flush cache to SRAM (before CALL): writes every cached entry
    //     to SRAM (deepest at the lowest address), advances r_sp, sets
    //     cache_count <= 0. `depth` is invariant across the flush.
    input  wire        flush_en,

    // hu: Stack műveletek
    // en: Stack operations
    input  wire        push_en,
    input  wire [31:0] push_data,
    input  wire        pop_en,
    input  wire        dup_en,
    input  wire        swap_en,
    input  wire        replace_top_en,
    input  wire [31:0] replace_top_data,

    // hu: Peek port (kombinációs, cache-only)
    // en: Peek port (combinational, cache-only)
    input  wire [1:0]  peek_index,
    output wire [31:0] peek_data,

    // hu: Kombinációs kimenetek
    // en: Combinational outputs
    output wire [31:0] tos,
    output wire [31:0] tos1,

    // hu: Pop eredmény (kombinációs, ready-jellel érvényes)
    // en: Pop result (combinational, valid when ready asserted)
    output wire [31:0] pop_data,

    // hu: Mélység és állapotjelzők
    // en: Depth and status signals
    output wire [6:0]  depth,
    output wire [2:0]  cache_count,
    output wire        busy,
    output wire        ready,

    // hu: Trap jelzés (regisztrált, 1 ciklusos pulzus)
    // en: Trap signal (registered, 1-cycle pulse)
    output wire        trap,
    output wire [7:0]  trap_code,

    // hu: SRAM master portok
    // en: SRAM master ports
    output wire [13:0] sram_addr,
    output wire [31:0] sram_wdata,
    input  wire [31:0] sram_rdata,
    output wire        sram_we,
    output wire        sram_re,
    input  wire        sram_ready
);

    // ============================================================
    // hu: Registered belső állapot (backend)
    // en: Registered internal state (backend)
    // ============================================================

    reg [31:0] r_t0, r_t1, r_t2, r_t3;      // hu: TOS regiszterek (r_t0 = TOS)
    reg [13:0] r_sp;                          // hu: Stack pointer (byte-cím, word-aligned)
    reg [13:0] r_sp_base;                     // hu: SP alap (depth számításhoz)
    reg [2:0]  r_cache_count;                 // hu: Cache elemszám (0..4)
    reg [2:0]  r_state;                       // hu: Állapotgép

    reg [31:0] r_pop_data;                    // hu: Pop eredmény (FILL esetén belső SRAM-ból)
    reg [31:0] r_spill_push_data;             // hu: SPILL elején regisztrált push_data/dup_data
    reg [31:0] r_fill_replace_data;           // hu: FILL_REPLACE elején regisztrált adat
    // hu: F2.7.D — sp_load(depth>0) cache-újratöltés (RET restore).
    //     A design invariánsa: cache_count = min(depth,4) — az ALU
    //     2-operandus opjai a tos/tos1 cache-only kimeneteket olvassák,
    //     ezért a top min(D,4) held elemet SRAM-ból a cache-be kell
    //     tölteni. r_spfill_k = hányadik elem; r_spfill_d = D.
    // en: F2.7.D — sp_load(depth>0) cache refill (RET restore).
    //     Invariant: cache_count = min(depth,4) — ALU 2-operand ops read
    //     the cache-only tos/tos1, so the top min(D,4) held elements must
    //     be loaded from SRAM into the cache.
    reg [2:0]  r_spfill_k;
    reg [6:0]  r_spfill_d;
    reg        r_spfill_ph;                   // 0 = read bridge, 1 = latch

    reg        r_trap;                        // hu: Trap flag (regisztrált, self-clearing)
    reg [7:0]  r_trap_code;                   // hu: Trap kód (regisztrált)

    reg        r_prev_busy;                   // hu: Előző ciklus busy flag (spurious op blokkolás)

    reg        r_sram_we;                     // hu: SRAM write enable
    reg        r_sram_re;                     // hu: SRAM read enable
    reg [13:0] r_sram_addr;                   // hu: SRAM cím
    reg [31:0] r_sram_wdata;                  // hu: SRAM írási adat

    // hu: Állapot-konstansok
    // en: State constants
    localparam [2:0] ST_IDLE         = 3'd0;
    localparam [2:0] ST_SPILL        = 3'd1;
    localparam [2:0] ST_FILL         = 3'd2;
    localparam [2:0] ST_FILL_DUP     = 3'd3;
    localparam [2:0] ST_FILL_SWAP    = 3'd4;
    localparam [2:0] ST_FILL_REPLACE = 3'd5;
    localparam [2:0] ST_FLUSH        = 3'd6;
    localparam [2:0] ST_SPFILL       = 3'd7;

    // hu: A betöltendő cache-elemszám: min(sp_depth, 4).
    // en: Cache fill count: min(sp_depth, 4).
    wire [2:0] w_spfill_cnt =
        (r_spfill_d >= 7'd4) ? 3'd4 : r_spfill_d[2:0];

    // hu: Flush alatt a legmélyebb ÉRVÉNYES cache-elem kiválasztása.
    //     cc=4→t3, cc=3→t2, cc=2→t1, cc=1→t0 (a legrégebbi cache-elt
    //     elem megy a legalacsonyabb szabad SRAM címre = r_sp).
    // en: Deepest VALID cache entry select during flush.
    wire [31:0] w_flush_sel =
        (r_cache_count == 3'd4) ? r_t3 :
        (r_cache_count == 3'd3) ? r_t2 :
        (r_cache_count == 3'd2) ? r_t1 :
                                  r_t0;

    // hu: A KÖVETKEZŐ flush-elem (a cache_count-1 melletti legmélyebb).
    //     A cache NEM tolódik flush közben — indexelt kiválasztás.
    // en: The NEXT flush entry (deepest for cache_count-1). The cache
    //     does NOT shift during flush — indexed select.
    wire [31:0] w_flush_next =
        (r_cache_count == 3'd4) ? r_t2 :
        (r_cache_count == 3'd3) ? r_t1 :
                                  r_t0;

    // ============================================================
    // hu: Prioritás-kódolt műveletek dekódolása (IDLE-ban)
    //     Prioritás: pop > push > dup > swap > replace_top
    // en: Priority-encoded operation decode (in IDLE)
    //     Priority: pop > push > dup > swap > replace_top
    // ============================================================

    wire op_pop     = pop_en;
    wire op_push    = (~pop_en) & push_en;
    wire op_dup     = (~pop_en) & (~push_en) & dup_en;
    wire op_swap    = (~pop_en) & (~push_en) & (~dup_en) & swap_en;
    wire op_replace = (~pop_en) & (~push_en) & (~dup_en) & (~swap_en) & replace_top_en;

    // ============================================================
    // hu: SP különbség és SRAM elemszám (kombinációs)
    // en: SP difference and SRAM word count (combinational)
    // ============================================================

    wire [14:0] w_sp_diff  = {1'b0, r_sp} - {1'b0, r_sp_base};
    wire [6:0]  w_sram_cnt = w_sp_diff[8:2];  // >> 2 = /4 (word-aligned)

    // ============================================================
    // hu: NEXT-VALUE kombinációs logika
    //     Az összes kombinációs kimenet a BEMENETI JELEK és a JELENLEGI állapot
    //     alapján ELŐRE számítja a következő értéket.
    // en: NEXT-VALUE combinational logic
    //     All combinational outputs are pre-computed from CURRENT inputs and state.
    // ============================================================

    // hu: Jelenlegi mélység
    // en: Current depth
    wire [6:0] w_depth = {4'b0, r_cache_count} + w_sram_cnt;

    // hu: busy = nem IDLE (kombinációs)
    // en: busy = not IDLE (combinational)
    assign busy = (r_state != ST_IDLE);

    // hu: IDLE feltételek — csak akkor aktívak, ha r_prev_busy=0 is
    //     (az előző ciklus busy volt → a most érkező op blokkolva)
    // en: IDLE conditions — only active if r_prev_busy=0
    //     (previous cycle was busy → arriving op blocked)
    wire w_op_ok = (r_state == ST_IDLE) && (~r_prev_busy);

    wire idle_push_ok     = w_op_ok && op_push && (w_depth < 7'd64) && (r_cache_count < 3'd4);
    wire idle_pop_ok      = w_op_ok && op_pop  && (w_depth > 7'd0)  && (r_cache_count > 3'd0);
    wire idle_dup_ok      = w_op_ok && op_dup  && (w_depth > 7'd0)  && (w_depth < 7'd64) && (r_cache_count > 3'd0) && (r_cache_count < 3'd4);
    wire idle_swap_ok     = w_op_ok && op_swap && (w_depth >= 7'd2) && (r_cache_count >= 3'd2);
    wire idle_replace_ok  = w_op_ok && op_replace && (w_depth > 7'd0) && (r_cache_count > 3'd0);

    // hu: Overflow/underflow trap feltételek (IDLE, w_op_ok gátolt)
    // en: Overflow/underflow trap conditions (IDLE, w_op_ok gated)
    wire idle_push_overflow  = w_op_ok && op_push    && (w_depth >= 7'd64);
    wire idle_pop_underflow  = w_op_ok && op_pop     && (w_depth == 7'd0);
    wire idle_dup_underflow  = w_op_ok && op_dup     && (w_depth == 7'd0);
    wire idle_dup_overflow   = w_op_ok && op_dup     && (w_depth >= 7'd64);
    wire idle_swap_underflow = w_op_ok && op_swap    && (w_depth < 7'd2);
    wire idle_repl_underflow = w_op_ok && op_replace && (w_depth == 7'd0);

    // ============================================================
    // hu: Következő t0, t1, cache_count kombinációs bypass
    //     (NBA settlement előtt is helyes érték — cocotb/Verilator kompatibilis)
    // en: Next t0, t1, cache_count combinational bypass
    //     (correct values before NBA settlement — cocotb/Verilator compatible)
    // ============================================================

    wire [31:0] w_next_t0 =
        idle_push_ok    ? push_data        :
        idle_pop_ok     ? r_t1             :
        idle_replace_ok ? replace_top_data :
        idle_swap_ok    ? r_t1             :
                          r_t0;

    // hu: Dup esetén: t1 = r_t0 (TOS duplikálódik t1-be is)
    // en: On dup: t1 = r_t0 (TOS duplicated into t1 as well)
    wire [31:0] w_next_t1 =
        idle_push_ok  ? r_t0 :
        idle_pop_ok   ? r_t2 :
        idle_swap_ok  ? r_t0 :
        idle_dup_ok   ? r_t0 :
                        r_t1;

    wire [2:0] w_next_cc =
        idle_push_ok  ? (r_cache_count + 3'd1) :
        idle_pop_ok   ? (r_cache_count - 3'd1) :
        idle_dup_ok   ? (r_cache_count + 3'd1) :
                         r_cache_count;

    // ============================================================
    // hu: Pop adat kombinációs
    // en: Pop data combinational
    // ============================================================
    assign pop_data = idle_pop_ok ? r_t0 : r_pop_data;

    // ============================================================
    // hu: Ready kombinációs
    // en: Ready combinational
    // ============================================================

    wire idle_spill_needed  = w_op_ok && (op_push || op_dup) &&
                               (w_depth > 7'd0) && (w_depth < 7'd64) &&
                               (r_cache_count == 3'd4);
    wire idle_fill_needed   = w_op_ok &&
                               ((op_pop     && (w_depth > 7'd0)  && (r_cache_count == 3'd0)) ||
                                (op_dup     && (w_depth > 7'd0)  && (r_cache_count == 3'd0)) ||
                                (op_swap    && (w_depth >= 7'd2) && (r_cache_count < 3'd2))  ||
                                (op_replace && (w_depth > 7'd0)  && (r_cache_count == 3'd0)));

    wire w_next_ready =
        (r_state != ST_IDLE) ? (sram_ready ? 1'b1 : 1'b0) :
        (idle_spill_needed || idle_fill_needed) ? 1'b0 :
        1'b1;

    // ============================================================
    // hu: Kimeneti port assign-ok
    // en: Output port assigns
    // ============================================================

    assign tos         = w_next_t0;
    assign tos1        = w_next_t1;
    assign cache_count = w_next_cc;
    assign depth       = {4'b0, w_next_cc} + w_sram_cnt;
    assign ready       = w_next_ready;

    // hu: Trap regiszterből hajtva (1 ciklusos pulzus)
    // en: Trap driven from register (1-cycle pulse)
    assign trap        = r_trap;
    assign trap_code   = r_trap_code;

    // hu: Peek (kombinációs, cache-only, saturating 0)
    // en: Peek (always combinational, cache-only, saturating 0)
    assign peek_data =
        (peek_index == 2'd0) ? ((r_cache_count > 3'd0) ? r_t0 : 32'h0) :
        (peek_index == 2'd1) ? ((r_cache_count > 3'd1) ? r_t1 : 32'h0) :
        (peek_index == 2'd2) ? ((r_cache_count > 3'd2) ? r_t2 : 32'h0) :
                               ((r_cache_count > 3'd3) ? r_t3 : 32'h0);

    // hu: SRAM portok (regiszterből hajtva)
    // en: SRAM ports (driven from registers)
    assign sram_we    = r_sram_we;
    assign sram_re    = r_sram_re;
    assign sram_addr  = r_sram_addr;
    assign sram_wdata = r_sram_wdata;

    // ============================================================
    // hu: Fő szekvenciális logika — regiszter update
    // en: Main sequential logic — register update
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // hu: Aszinkron reset
            // en: Asynchronous reset
            r_t0                <= 32'h0;
            r_t1                <= 32'h0;
            r_t2                <= 32'h0;
            r_t3                <= 32'h0;
            r_sp                <= 14'h0;
            r_sp_base           <= 14'h0;
            r_cache_count       <= 3'd0;
            r_state             <= ST_IDLE;
            r_pop_data          <= 32'h0;
            r_spill_push_data   <= 32'h0;
            r_fill_replace_data <= 32'h0;
            r_spfill_k          <= 3'd0;
            r_spfill_d          <= 7'd0;
            r_spfill_ph         <= 1'b0;
            r_trap              <= 1'b0;
            r_trap_code         <= 8'h00;
            r_prev_busy         <= 1'b0;
            r_sram_we           <= 1'b0;
            r_sram_re           <= 1'b0;
            r_sram_addr         <= 14'h0;
            r_sram_wdata        <= 32'h0;

        end else begin

            // hu: Trap 1 ciklusra aktív, aztán automatikusan törlődik
            // en: Trap active for 1 cycle, then auto-clears
            r_trap      <= 1'b0;
            r_trap_code <= 8'h00;

            // hu: Előző ciklus busy flag frissítése
            // en: Update previous cycle busy flag
            r_prev_busy <= (r_state != ST_IDLE);

            case (r_state)

                // --------------------------------------------------------
                // hu: IDLE — normál műveletek kezelése
                // en: IDLE — handle normal operations
                // --------------------------------------------------------
                ST_IDLE: begin
                    r_sram_we <= 1'b0;
                    r_sram_re <= 1'b0;

                    // hu: SP betöltés (frame setup). sp_init = új eval bázis,
                    //     r_sp = bázis + sp_depth*4 (a megőrzött elemek az
                    //     SRAM-ban élnek). A cache MINDIG ürül (cache_count
                    //     <= 0) — CORE_SPEC: a callee tiszta cache-sel indul,
                    //     a caller maradéka flush-olva van SRAM-ba.
                    // en: SP load (frame setup). sp_init = new eval base,
                    //     r_sp = base + sp_depth*4 (preserved items live in
                    //     SRAM). Cache is ALWAYS cleared.
                    if (sp_load) begin
                        r_sp_base     <= sp_init;
                        r_t0          <= 32'h0;
                        r_t1          <= 32'h0;
                        r_t2          <= 32'h0;
                        r_t3          <= 32'h0;
                        if (sp_depth == 7'd0) begin
                            // hu: Üres eval (CALL / boot).
                            // en: Empty eval (CALL / boot).
                            r_sp          <= sp_init;
                            r_cache_count <= 3'd0;
                        end else begin
                            // hu: RET restore — a top min(D,4) held elemet
                            //     SRAM-ból a cache-be töltjük (ST_SPFILL).
                            //     1. read: SRAM[base + (D-1)*4] → r_t0 (TOS).
                            // en: RET restore — load top min(D,4) held
                            //     items from SRAM into the cache.
                            r_cache_count <= 3'd0;
                            r_spfill_d    <= sp_depth;
                            r_spfill_k    <= 3'd0;
                            r_spfill_ph   <= 1'b0;
                            r_state       <= ST_SPFILL;
                            r_sram_re     <= 1'b1;
                            r_sram_addr   <= sp_init +
                                {5'd0, (sp_depth - 7'd1), 2'b00};
                        end
                    end

                    // hu: Cache flush SRAM-ba (CALL előtt). Csak ha van
                    //     cache-elt elem; egyébként no-op (már minden SRAM).
                    //     A flush kizárja a normál op-ot ebben a ciklusban.
                    // en: Flush cache to SRAM (before CALL). Only if cache
                    //     has entries; otherwise no-op. Flush excludes a
                    //     normal op this cycle.
                    if (flush_en && ~r_prev_busy && ~sp_load &&
                        (r_cache_count > 3'd0)) begin
                        r_state      <= ST_FLUSH;
                        r_sram_we    <= 1'b1;
                        r_sram_addr  <= r_sp;
                        r_sram_wdata <= w_flush_sel;
                    end

                    // hu: Spurious op blokkolás: ha az előző ciklus busy volt,
                    //     kihagyjuk ezt a ciklust (az op a busy közbeni jelek miatt
                    //     érkezett, és ignorálandó)
                    // en: Spurious op blocking: if previous cycle was busy,
                    //     skip this cycle (op arrived due to signals during busy,
                    //     must be ignored)
                    if (~r_prev_busy && ~flush_en && ~sp_load) begin

                        if (op_pop) begin
                            // ── POP ──
                            if (w_depth == 7'd0) begin
                                // hu: Underflow trap
                                // en: Underflow trap
                                r_trap      <= 1'b1;
                                r_trap_code <= `TRAP_STACK_UNDERFLOW;
                            end else if (r_cache_count > 3'd0) begin
                                // hu: Cache-ből pop
                                // en: Pop from cache
                                r_pop_data    <= r_t0;
                                r_t0          <= r_t1;
                                r_t1          <= r_t2;
                                r_t2          <= r_t3;
                                r_t3          <= 32'h0;
                                r_cache_count <= r_cache_count - 3'd1;
                            end else begin
                                // hu: FILL: sp--, sram_re=1
                                // en: FILL: sp--, sram_re=1
                                r_state     <= ST_FILL;
                                r_sp        <= r_sp - 14'd4;
                                r_sram_re   <= 1'b1;
                                r_sram_addr <= r_sp - 14'd4;
                            end

                        end else if (op_push) begin
                            // ── PUSH ──
                            if (w_depth >= 7'd64) begin
                                // hu: Overflow trap
                                // en: Overflow trap
                                r_trap      <= 1'b1;
                                r_trap_code <= `TRAP_STACK_OVERFLOW;
                            end else if (r_cache_count < 3'd4) begin
                                // hu: Cache-be push
                                // en: Push into cache
                                r_t3          <= r_t2;
                                r_t2          <= r_t1;
                                r_t1          <= r_t0;
                                r_t0          <= push_data;
                                r_cache_count <= r_cache_count + 3'd1;
                            end else begin
                                // hu: SPILL: t3 SRAM-ba, push_data regisztrálása
                                // en: SPILL: write t3 to SRAM, register push_data
                                r_spill_push_data <= push_data;
                                r_state           <= ST_SPILL;
                                r_sram_we         <= 1'b1;
                                r_sram_addr       <= r_sp;
                                r_sram_wdata      <= r_t3;
                            end

                        end else if (op_dup) begin
                            // ── DUP ──
                            if (w_depth == 7'd0) begin
                                r_trap      <= 1'b1;
                                r_trap_code <= `TRAP_STACK_UNDERFLOW;
                            end else if (w_depth >= 7'd64) begin
                                r_trap      <= 1'b1;
                                r_trap_code <= `TRAP_STACK_OVERFLOW;
                            end else if (r_cache_count > 3'd0) begin
                                if (r_cache_count < 3'd4) begin
                                    // hu: Egyszerű dup: cache-ben van hely
                                    // en: Simple dup: cache has room
                                    r_t3          <= r_t2;
                                    r_t2          <= r_t1;
                                    r_t1          <= r_t0;
                                    // hu: r_t0 változatlan (TOS duplikálódik)
                                    // en: r_t0 unchanged (TOS duplicated)
                                    r_cache_count <= r_cache_count + 3'd1;
                                end else begin
                                    // hu: SPILL: t3 ki, TOS dup
                                    // en: SPILL: evict t3, dup TOS
                                    r_spill_push_data <= r_t0;
                                    r_state           <= ST_SPILL;
                                    r_sram_we         <= 1'b1;
                                    r_sram_addr       <= r_sp;
                                    r_sram_wdata      <= r_t3;
                                end
                            end else begin
                                // hu: FILL_DUP: cache üres, TOS az SRAM-ban
                                // en: FILL_DUP: cache empty, TOS in SRAM
                                r_state     <= ST_FILL_DUP;
                                r_sp        <= r_sp - 14'd4;
                                r_sram_re   <= 1'b1;
                                r_sram_addr <= r_sp - 14'd4;
                            end

                        end else if (op_swap) begin
                            // ── SWAP ──
                            if (w_depth < 7'd2) begin
                                r_trap      <= 1'b1;
                                r_trap_code <= `TRAP_STACK_UNDERFLOW;
                            end else if (r_cache_count >= 3'd2) begin
                                r_t0 <= r_t1;
                                r_t1 <= r_t0;
                            end else begin
                                // hu: FILL_SWAP: TOS-1 betöltése SRAM-ból
                                // en: FILL_SWAP: load TOS-1 from SRAM
                                r_state     <= ST_FILL_SWAP;
                                r_sp        <= r_sp - 14'd4;
                                r_sram_re   <= 1'b1;
                                r_sram_addr <= r_sp - 14'd4;
                            end

                        end else if (op_replace) begin
                            // ── REPLACE TOP ──
                            if (w_depth == 7'd0) begin
                                r_trap      <= 1'b1;
                                r_trap_code <= `TRAP_STACK_UNDERFLOW;
                            end else if (r_cache_count > 3'd0) begin
                                r_t0 <= replace_top_data;
                            end else begin
                                // hu: FILL_REPLACE: cache üres
                                // en: FILL_REPLACE: cache empty
                                r_fill_replace_data <= replace_top_data;
                                r_state     <= ST_FILL_REPLACE;
                                r_sp        <= r_sp - 14'd4;
                                r_sram_re   <= 1'b1;
                                r_sram_addr <= r_sp - 14'd4;
                            end
                        end

                    end // ~r_prev_busy
                end // ST_IDLE

                // --------------------------------------------------------
                // hu: SPILL — t3 SRAM-ba írjuk, sram_ready handshake-kel
                // en: SPILL — write t3 to SRAM with sram_ready handshake
                // --------------------------------------------------------
                ST_SPILL: begin
                    r_sram_we    <= 1'b1;
                    r_sram_addr  <= r_sp;
                    r_sram_wdata <= r_t3;

                    if (sram_ready) begin
                        // hu: A külső SRAM írás a sram_we/sram_addr/sram_wdata
                        //     portokon át történik — itt csak az állapot előrelép.
                        // en: External SRAM write happens through the
                        //     sram_we/sram_addr/sram_wdata ports — only state
                        //     advancement here.
                        r_sp          <= r_sp + 14'd4;
                        r_sram_we     <= 1'b0;
                        r_t3          <= r_t2;
                        r_t2          <= r_t1;
                        r_t1          <= r_t0;
                        r_t0          <= r_spill_push_data;
                        r_state       <= ST_IDLE;
                    end
                end // ST_SPILL

                // --------------------------------------------------------
                // hu: FILL — pop eredménye belső SRAM-ból
                // en: FILL — pop result from internal SRAM
                // --------------------------------------------------------
                ST_FILL: begin
                    r_sram_re   <= 1'b1;
                    r_sram_addr <= r_sp;

                    if (sram_ready) begin
                        // hu: Külső SRAM olvasás a sram_rdata bemeneten át
                        //     (r_sp már dekrementált az IDLE belépésekor)
                        // en: External SRAM read via sram_rdata input
                        //     (r_sp already decremented on IDLE entry)
                        r_pop_data  <= sram_rdata;
                        r_sram_re   <= 1'b0;
                        r_state     <= ST_IDLE;
                    end
                end // ST_FILL

                // --------------------------------------------------------
                // hu: FILL_DUP — betölt a belső SRAM-ból, majd duplikál
                // en: FILL_DUP — load from internal SRAM, then duplicate
                // --------------------------------------------------------
                ST_FILL_DUP: begin
                    r_sram_re   <= 1'b1;
                    r_sram_addr <= r_sp;

                    if (sram_ready) begin
                        // hu: Külső SRAM-ból olvas, és duplikálja TOS-ra és TOS-1-re
                        // en: Read from external SRAM, duplicate to TOS and TOS-1
                        r_t0          <= sram_rdata;
                        r_t1          <= sram_rdata;
                        r_cache_count <= 3'd2;
                        r_sram_re     <= 1'b0;
                        r_state       <= ST_IDLE;
                    end
                end // ST_FILL_DUP

                // --------------------------------------------------------
                // hu: FILL_SWAP — TOS-1 betöltése, majd csere
                // en: FILL_SWAP — load TOS-1 then swap
                // --------------------------------------------------------
                ST_FILL_SWAP: begin
                    r_sram_re   <= 1'b1;
                    r_sram_addr <= r_sp;

                    if (sram_ready) begin
                        // hu: Külső SRAM-ból olvas, és cseréli TOS és TOS-1-et
                        // en: Read from external SRAM, swap TOS and TOS-1
                        r_t1          <= r_t0;
                        r_t0          <= sram_rdata;
                        r_cache_count <= 3'd2;
                        r_sram_re     <= 1'b0;
                        r_state       <= ST_IDLE;
                    end
                end // ST_FILL_SWAP

                // --------------------------------------------------------
                // hu: FILL_REPLACE — betölt, majd felülír (sram_we=0!)
                // en: FILL_REPLACE — load then overwrite (no sram_we!)
                // --------------------------------------------------------
                ST_FILL_REPLACE: begin
                    r_sram_re   <= 1'b1;
                    r_sram_addr <= r_sp;

                    if (sram_ready) begin
                        r_t0          <= r_fill_replace_data;
                        r_cache_count <= 3'd1;
                        r_sram_re     <= 1'b0;
                        r_state       <= ST_IDLE;
                    end
                end // ST_FILL_REPLACE

                // --------------------------------------------------------
                // hu: FLUSH — minden cache-elt elem SRAM-ba (CALL előtt).
                //     Ciklusonként a legmélyebb érvényes elemet írjuk a
                //     soron következő (növekvő) SRAM címre, sram_ready
                //     handshake-kel. cache_count==0 → ST_IDLE. A `depth`
                //     invariáns: cc-- és w_sram_cnt++ kiegyenlíti egymást.
                // en: FLUSH — every cached entry to SRAM (before CALL).
                //     Per cycle write the deepest valid entry to the next
                //     ascending SRAM address with sram_ready handshake.
                //     cache_count==0 → ST_IDLE. `depth` is invariant.
                // --------------------------------------------------------
                ST_FLUSH: begin
                    r_sram_we <= 1'b1;

                    if (sram_ready) begin
                        // hu: Az aktuális elem (r_sram_addr/wdata) kiírva.
                        //     Léptetés a következőre.
                        // en: Current entry (r_sram_addr/wdata) written.
                        //     Advance to the next.
                        r_sp          <= r_sp + 14'd4;
                        r_cache_count <= r_cache_count - 3'd1;
                        if (r_cache_count <= 3'd1) begin
                            // hu: Ez volt az utolsó elem → IDLE.
                            // en: This was the last entry → IDLE.
                            r_sram_we <= 1'b0;
                            r_state   <= ST_IDLE;
                        end else begin
                            r_sram_addr  <= r_sp + 14'd4;
                            r_sram_wdata <= w_flush_next;
                        end
                    end
                end // ST_FLUSH

                // --------------------------------------------------------
                // hu: SPFILL — sp_load(depth>0): a top min(D,4) held elemet
                //     SRAM-ból a cache-be tölti (RET restore). Elemenként
                //     2 fázis (ph0 = read bridge, ph1 = latch+advance), a
                //     core RET-olvasásával egyező robosztus időzítés.
                //     r_t0 = TOS = SRAM[base+(D-1)*4], r_t1 = +(D-2)*4, ...
                // en: SPFILL — sp_load(depth>0): load top min(D,4) held
                //     items from SRAM into the cache (RET restore). Per
                //     element 2 phases (ph0 read bridge, ph1 latch+advance).
                // --------------------------------------------------------
                ST_SPFILL: begin
                    if (r_spfill_ph == 1'b0) begin
                        // hu: A read folyamatban (addr a sp_load/előző
                        //     elem óta tartva) — 1 ciklus bridge.
                        // en: Read in flight (addr held) — 1-cycle bridge.
                        r_sram_re   <= 1'b1;
                        r_spfill_ph <= 1'b1;
                    end else begin
                        // hu: sram_rdata érvényes → r_t[k] latch.
                        // en: sram_rdata valid → latch r_t[k].
                        case (r_spfill_k)
                            3'd0: r_t0 <= sram_rdata;
                            3'd1: r_t1 <= sram_rdata;
                            3'd2: r_t2 <= sram_rdata;
                            default: r_t3 <= sram_rdata;
                        endcase
                        if (r_spfill_k + 3'd1 >= w_spfill_cnt) begin
                            // hu: Kész — cache_count + SRAM-maradék SP.
                            // en: Done — set cache_count + SRAM-rest SP.
                            r_cache_count <= w_spfill_cnt;
                            r_sp <= r_sp_base +
                                {5'd0,
                                 (r_spfill_d - {4'd0, w_spfill_cnt}),
                                 2'b00};
                            r_sram_re <= 1'b0;
                            r_state   <= ST_IDLE;
                        end else begin
                            // hu: Következő elem: addr = base+(D-2-k)*4.
                            // en: Next element.
                            r_spfill_k  <= r_spfill_k + 3'd1;
                            r_spfill_ph <= 1'b0;
                            r_sram_re   <= 1'b1;
                            r_sram_addr <= r_sp_base +
                                {5'd0,
                                 (r_spfill_d - 7'd2 - {4'd0, r_spfill_k}),
                                 2'b00};
                        end
                    end
                end // ST_SPFILL

                default: begin
                    r_state   <= ST_IDLE;
                    r_sram_we <= 1'b0;
                    r_sram_re <= 1'b0;
                end

            endcase
        end
    end

endmodule
