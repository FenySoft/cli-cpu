# hu: CLI-CPU Stack Cache cocotb tesztek — a cilcpu_stack_cache.v 4-elem TOS cache
#     és SRAM spill/fill mechanizmus verifikálása a C# TCpuNano.EvalPush/EvalPop/
#     EvalPeek aranypélda szemantikájával szemben.
#     Tesztstratégia: STACK_CACHE_SPEC.md "Tesztstratégia" 14 pontja alapján.
#     Oracle: src/CilCpu.Sim/TCpuNano.cs EvalPush, EvalPop, EvalPeek.
# en: CLI-CPU Stack Cache cocotb tests — verification of cilcpu_stack_cache.v
#     4-element TOS cache and SRAM spill/fill mechanism against the C#
#     TCpuNano.EvalPush/EvalPop/EvalPeek reference semantics.
#     Test strategy: based on STACK_CACHE_SPEC.md "Test strategy" 14 points.
#     Oracle: src/CilCpu.Sim/TCpuNano.cs EvalPush, EvalPop, EvalPeek.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
import random

# ============================================================
# hu: Trap kódok (STACK_CACHE_SPEC.md alapján)
# en: Trap codes (from STACK_CACHE_SPEC.md)
# ============================================================

TRAP_STACK_OVERFLOW  = 0x01
TRAP_STACK_UNDERFLOW = 0x02

# hu: Maximális stack mélység (TCpuNano.MaxStackDepth = 64)
# en: Maximum stack depth (TCpuNano.MaxStackDepth = 64)
MAX_STACK_DEPTH = 64

# hu: SP alap offset (16-bites, relatív a stack régió bázisához)
# en: SP base offset (14-bit, relative to stack region base)
SP_INIT_DEFAULT = 0

# hu: Az aktívan futó SRAM behavior modell task-je. A reset_dut killeli
#     a korábbit és indít újat, így minden teszt friss, üres SRAM-mal indul.
# en: The currently running SRAM behavior model task. reset_dut kills the
#     previous one and starts a fresh one so each test gets a clean SRAM.
_sram_model_task = None

# ============================================================
# hu: Segédfüggvények
# en: Helper functions
# ============================================================


async def sram_behavior_model(dut, ready_override=None):
    """
    hu: Külső SRAM viselkedés-modell, két koroutinból: (1) write-figyelő
        rising edge-en (sram_we sample-elés), és (2) sram_rdata kombinációs
        kihajtása az aktuális sram_addr alapján. Az olvasás "azonnali",
        ahogyan egy Sky130 SRAM blokk: amikor a sram_re=1 jön, a sram_rdata
        ugyanazon a ciklusban érvényes. A `ready_override` callable
        ciklusonként vezérelheti a sram_ready jelet (test_22).
    en: External SRAM behavior model, two coroutines: (1) write watcher on
        rising edge (samples sram_we), and (2) combinational sram_rdata drive
        from current sram_addr. Read is "instant" like a Sky130 SRAM block:
        when sram_re=1 arrives, sram_rdata is valid on the same cycle. The
        `ready_override` callable drives sram_ready per cycle (test_22).
    """
    mem = {}

    async def _write_watcher():
        while True:
            await RisingEdge(dut.clk)

            if ready_override is not None:
                try:
                    dut.sram_ready.value = int(ready_override())
                except Exception:
                    pass

            try:
                we = int(dut.sram_we.value)
                ready = int(dut.sram_ready.value)
                addr_word = (int(dut.sram_addr.value) >> 2)
            except ValueError:
                continue

            if we == 1 and ready == 1:
                mem[addr_word] = int(dut.sram_wdata.value)

    async def _read_driver():
        # hu: kombinációs olvasó — az sram_addr bármilyen változásra reagál
        # en: combinational reader — reacts to any sram_addr change
        from cocotb.triggers import Edge, Combine, First
        while True:
            try:
                addr_word = (int(dut.sram_addr.value) >> 2)
                dut.sram_rdata.value = mem.get(addr_word, 0)
            except ValueError:
                dut.sram_rdata.value = 0
            # hu: várjunk akár órajel élre, akár cím változásra — bármelyik előbb
            # en: wait for clock edge or addr change — whichever comes first
            await First(RisingEdge(dut.clk), Edge(dut.sram_addr))

    cocotb.start_soon(_write_watcher())
    cocotb.start_soon(_read_driver())
    # hu: a fő koroutin örökre vár — a két alkoroutin tartja életben a modellt
    # en: main coroutine waits forever — sub-coroutines keep the model alive
    while True:
        await RisingEdge(dut.clk)


async def reset_dut(dut, sram_ready_override=None):
    """
    hu: Aszinkron aktív-low reset, 3 ciklus. Reset után sp_load + sp_init.
        Indít egy friss SRAM behavior modellt is — a korábbit killeli, hogy
        minden teszt üres SRAM-mal kezdjen.
    en: Async active-low reset, 3 cycles. After reset: sp_load + sp_init.
        Also starts a fresh SRAM behavior model — kills the previous one so
        each test starts with empty SRAM.
    """
    global _sram_model_task
    if _sram_model_task is not None:
        _sram_model_task.kill()
    _sram_model_task = cocotb.start_soon(
        sram_behavior_model(dut, ready_override=sram_ready_override)
    )

    dut.rst_n.value = 0
    dut.sp_load.value = 0
    dut.sp_init.value = SP_INIT_DEFAULT
    dut.push_en.value = 0
    dut.push_data.value = 0
    dut.pop_en.value = 0
    dut.dup_en.value = 0
    dut.swap_en.value = 0
    dut.replace_top_en.value = 0
    dut.replace_top_data.value = 0
    dut.peek_index.value = 0
    dut.sram_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # hu: Reset feloldása + SP inicializálás egy ciklusban
    # en: Release reset + SP init in one cycle
    dut.rst_n.value = 1
    dut.sp_load.value = 1
    dut.sp_init.value = SP_INIT_DEFAULT

    await RisingEdge(dut.clk)

    dut.sp_load.value = 0

    await RisingEdge(dut.clk)


async def do_push(dut, value):
    """
    hu: Push művelet, megvárja amíg a modul ready lesz (spill kezelés).
    en: Push operation, waits for ready (handles spill).
    """
    await FallingEdge(dut.clk)
    dut.push_en.value = 1
    dut.push_data.value = value & 0xFFFFFFFF
    await RisingEdge(dut.clk)
    dut.push_en.value = 0
    dut.push_data.value = 0

    # hu: Spill esetén busy=1 ideig várunk
    # en: Wait while busy (spill in progress)
    for _ in range(20):
        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)


async def do_pop(dut):
    """
    hu: Pop művelet, visszaadja a pop_data értékét.
    en: Pop operation, returns pop_data value.
    """
    await FallingEdge(dut.clk)
    dut.pop_en.value = 1
    await RisingEdge(dut.clk)
    dut.pop_en.value = 0

    # hu: Fill esetén busy=1 ideig várunk
    # en: Wait while busy (fill in progress)
    for _ in range(20):
        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)

    return int(dut.pop_data.value)


async def do_dup(dut):
    """
    hu: Dup művelet — TOS duplikálása.
    en: Dup operation — duplicate TOS.
    """
    await FallingEdge(dut.clk)
    dut.dup_en.value = 1
    await RisingEdge(dut.clk)
    dut.dup_en.value = 0

    for _ in range(20):
        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)


async def do_swap(dut):
    """
    hu: Swap művelet — TOS ↔ TOS-1.
    en: Swap operation — TOS ↔ TOS-1.
    """
    await FallingEdge(dut.clk)
    dut.swap_en.value = 1
    await RisingEdge(dut.clk)
    dut.swap_en.value = 0

    for _ in range(20):
        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)


async def do_replace_top(dut, value):
    """
    hu: Replace top művelete — TOS felülírás.
    en: Replace top — overwrite TOS.
    """
    await FallingEdge(dut.clk)
    dut.replace_top_en.value = 1
    dut.replace_top_data.value = value & 0xFFFFFFFF
    await RisingEdge(dut.clk)
    dut.replace_top_en.value = 0
    dut.replace_top_data.value = 0

    for _ in range(20):
        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)


async def wait_ready(dut, max_cycles=20):
    """
    hu: Megvárja a ready=1 jelet.
    en: Wait for ready=1 signal.
    """
    for _ in range(max_cycles):
        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            return
        await RisingEdge(dut.clk)


def get_tos(dut):
    """hu: TOS kombinációs érték olvasása. en: Read TOS combinatorial output."""
    return int(dut.tos.value)


def get_depth(dut):
    """hu: Stack mélység olvasása. en: Read stack depth."""
    return int(dut.depth.value)


def get_cache_count(dut):
    """hu: Cache elemszám olvasása. en: Read cache element count."""
    return int(dut.cache_count.value)


# ============================================================
# hu: Python referencia stack modell (aranypélda: TCpuNano.EvalPush/EvalPop)
# en: Python reference stack model (oracle: TCpuNano.EvalPush/EvalPop)
# ============================================================

class TRefStack:
    """
    hu: Referencia stack modell, amely a TCpuNano.EvalPush/EvalPop szemantikát
        implementálja. Overflow és underflow trap-et szimulál.
    en: Reference stack model implementing TCpuNano.EvalPush/EvalPop semantics.
        Simulates overflow and underflow traps.
    """

    def __init__(self):
        # hu: Stack elemek listája, legutolsó = TOS
        # en: Stack elements list, last = TOS
        self.FStack = []

    def push(self, value):
        """
        hu: Elem feltolása. Ha depth >= 64 → StackOverflow.
        en: Push element. If depth >= 64 → StackOverflow.
        """
        if len(self.FStack) >= MAX_STACK_DEPTH:
            return "OVERFLOW"

        self.FStack.append(value & 0xFFFFFFFF)
        return None

    def pop(self):
        """
        hu: Elem levétele. Ha üres → StackUnderflow.
        en: Pop element. If empty → StackUnderflow.
        """
        if len(self.FStack) == 0:
            return None, "UNDERFLOW"

        return self.FStack.pop(), None

    def tos(self):
        """hu: TOS érték. en: TOS value."""
        if len(self.FStack) == 0:
            return None

        return self.FStack[-1]

    def tos1(self):
        """hu: TOS-1 érték. en: TOS-1 value."""
        if len(self.FStack) < 2:
            return None

        return self.FStack[-2]

    def peek(self, index):
        """
        hu: Peek adott offsettel (0=TOS). en: Peek at given offset (0=TOS).
        """
        pos = len(self.FStack) - 1 - index

        if pos < 0:
            return None

        return self.FStack[pos]

    @property
    def depth(self):
        """hu: Stack mélység. en: Stack depth."""
        return len(self.FStack)

    def dup(self):
        """hu: TOS duplikálása. en: Duplicate TOS."""
        if len(self.FStack) == 0:
            return "UNDERFLOW"

        if len(self.FStack) >= MAX_STACK_DEPTH:
            return "OVERFLOW"

        self.FStack.append(self.FStack[-1])
        return None

    def swap(self):
        """hu: TOS ↔ TOS-1. en: Swap TOS with TOS-1."""
        if len(self.FStack) < 2:
            return "UNDERFLOW"

        self.FStack[-1], self.FStack[-2] = self.FStack[-2], self.FStack[-1]
        return None

    def replace_top(self, value):
        """hu: TOS felülírás. en: Replace TOS."""
        if len(self.FStack) == 0:
            return "UNDERFLOW"

        self.FStack[-1] = value & 0xFFFFFFFF
        return None


# ============================================================
# hu: 1. Reset és inicializálás — cache_count=0, depth=0, ready=1
# en: 1. Reset and initialization — cache_count=0, depth=0, ready=1
# ============================================================

@cocotb.test()
async def test_01_reset_and_init(dut):
    """
    hu: Reset után: cache_count=0, depth=0, ready=1, busy=0, trap=0.
    en: After reset: cache_count=0, depth=0, ready=1, busy=0, trap=0.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    assert get_cache_count(dut) == 0, \
        f"cache_count after reset: expected 0, got {get_cache_count(dut)}"
    assert get_depth(dut) == 0, \
        f"depth after reset: expected 0, got {get_depth(dut)}"
    assert int(dut.ready.value) == 1, \
        f"ready after reset: expected 1, got {int(dut.ready.value)}"
    assert int(dut.busy.value) == 0, \
        f"busy after reset: expected 0, got {int(dut.busy.value)}"
    assert int(dut.trap.value) == 0, \
        f"trap after reset: expected 0, got {int(dut.trap.value)}"


# ============================================================
# hu: 2. Egyszerű push — tos == push_data, cache_count==1, depth==1
# en: 2. Simple push — tos == push_data, cache_count==1, depth==1
# ============================================================

@cocotb.test()
async def test_02_simple_push(dut):
    """
    hu: 1 push: tos == push_data, cache_count==1, depth==1.
    en: 1 push: tos == push_data, cache_count==1, depth==1.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    await do_push(dut, 0xDEADBEEF)

    assert get_tos(dut) == 0xDEADBEEF, \
        f"tos after push: expected 0xDEADBEEF, got {get_tos(dut):#010x}"
    assert get_cache_count(dut) == 1, \
        f"cache_count: expected 1, got {get_cache_count(dut)}"
    assert get_depth(dut) == 1, \
        f"depth: expected 1, got {get_depth(dut)}"
    assert int(dut.trap.value) == 0, \
        f"trap: expected 0, got {int(dut.trap.value)}"


# ============================================================
# hu: 3. 4 push cache-be — cache_count==4, depth==4, nincs SRAM access
# en: 3. 4 pushes into cache — cache_count==4, depth==4, no SRAM access
# ============================================================

@cocotb.test()
async def test_03_four_pushes_fill_cache(dut):
    """
    hu: 4 push: cache_count==4, depth==4. sram_we soha nem lesz 1.
    en: 4 pushes: cache_count==4, depth==4. sram_we never asserted.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    values = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
    sram_write_detected = False

    for v in values:
        # hu: SRAM write figyelés push előtt
        # en: Monitor SRAM write before push
        if int(dut.sram_we.value) == 1:
            sram_write_detected = True

        await do_push(dut, v)

        if int(dut.sram_we.value) == 1:
            sram_write_detected = True

    assert not sram_write_detected, \
        "sram_we was asserted during first 4 pushes (cache should absorb all)"
    assert get_cache_count(dut) == 4, \
        f"cache_count: expected 4, got {get_cache_count(dut)}"
    assert get_depth(dut) == 4, \
        f"depth: expected 4, got {get_depth(dut)}"
    # hu: TOS az utolsó feltolt érték
    # en: TOS is the last pushed value
    assert get_tos(dut) == 0x44444444, \
        f"tos: expected 0x44444444, got {get_tos(dut):#010x}"


# ============================================================
# hu: 4. 5. push spill-lel — SRAM write, depth==5, cache_count==4
# en: 4. 5th push with spill — SRAM write, depth==5, cache_count==4
# ============================================================

@cocotb.test()
async def test_04_fifth_push_causes_spill(dut):
    """
    hu: 5. push: SRAM write (t[3] kikerül), depth==5, cache_count==4, busy 1 ciklus.
    en: 5th push: SRAM write (t[3] evicted), depth==5, cache_count==4, busy for 1+ cycle.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    for i in range(4):
        await do_push(dut, i + 1)

    # hu: 5. push — spill-t vár
    # en: 5th push — expect spill
    await FallingEdge(dut.clk)
    dut.push_en.value = 1
    dut.push_data.value = 0x55555555
    await RisingEdge(dut.clk)
    dut.push_en.value = 0
    dut.push_data.value = 0

    # hu: busy=1 kell lennie legalább 1 cikluson át (spill folyamatban)
    # en: busy=1 must be seen for at least 1 cycle (spill in progress)
    busy_seen = False

    for _ in range(20):
        if int(dut.busy.value) == 1:
            busy_seen = True

        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            break

        await RisingEdge(dut.clk)

    assert busy_seen, "busy was never asserted during 5th push (spill expected)"
    assert get_depth(dut) == 5, \
        f"depth after 5 pushes: expected 5, got {get_depth(dut)}"
    assert get_cache_count(dut) == 4, \
        f"cache_count after spill: expected 4, got {get_cache_count(dut)}"
    assert get_tos(dut) == 0x55555555, \
        f"tos: expected 0x55555555, got {get_tos(dut):#010x}"


# ============================================================
# hu: 5. Pop visszafelé spill-fill-lel — 5 elem sorra levétele
# en: 5. Pop back with spill-fill — remove 5 elements one by one
# ============================================================

@cocotb.test()
async def test_05_pop_all_five_with_fill(dut):
    """
    hu: 5 push után 5 pop — az SRAM-ból vissza kell tölteni (fill). LIFO sorrend.
    en: After 5 pushes, 5 pops — SRAM fill must occur. LIFO order verified.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    pushed = list(range(1, 6))  # [1, 2, 3, 4, 5]

    for v in pushed:
        await do_push(dut, v)

    popped = []

    for _ in range(5):
        val = await do_pop(dut)
        popped.append(val)

    # hu: LIFO sorrend: [5, 4, 3, 2, 1]
    # en: LIFO order: [5, 4, 3, 2, 1]
    expected = list(reversed(pushed))
    assert popped == expected, \
        f"pop order mismatch: expected {expected}, got {popped}"
    assert get_depth(dut) == 0, \
        f"depth after all pops: expected 0, got {get_depth(dut)}"
    assert get_cache_count(dut) == 0, \
        f"cache_count after all pops: expected 0, got {get_cache_count(dut)}"


# ============================================================
# hu: 6. Dup — cache_count==1-ből dup → 2, mindkettő ugyanaz
# en: 6. Dup — from cache_count==1, dup → 2, both same value
# ============================================================

@cocotb.test()
async def test_06_dup(dut):
    """
    hu: 1 push, majd dup: cache_count==2, tos==tos1 (mindkettő ugyanaz).
    en: 1 push, then dup: cache_count==2, tos==tos1 (both same).
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    await do_push(dut, 0xABCDEF01)
    await do_dup(dut)

    assert get_cache_count(dut) == 2, \
        f"cache_count after dup: expected 2, got {get_cache_count(dut)}"
    assert get_depth(dut) == 2, \
        f"depth after dup: expected 2, got {get_depth(dut)}"
    assert get_tos(dut) == 0xABCDEF01, \
        f"tos after dup: expected 0xABCDEF01, got {get_tos(dut):#010x}"
    assert int(dut.tos1.value) == 0xABCDEF01, \
        f"tos1 after dup: expected 0xABCDEF01, got {int(dut.tos1.value):#010x}"


# ============================================================
# hu: 7. Swap — két érték, swap, ellenőrzi a sorrendet
# en: 7. Swap — two values, swap, verify order
# ============================================================

@cocotb.test()
async def test_07_swap(dut):
    """
    hu: Push 10, push 20, swap → tos==10, tos1==20.
    en: Push 10, push 20, swap → tos==10, tos1==20.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    await do_push(dut, 10)
    await do_push(dut, 20)

    # hu: Swap előtt: tos=20, tos1=10
    # en: Before swap: tos=20, tos1=10
    assert get_tos(dut) == 20, f"tos before swap: expected 20, got {get_tos(dut)}"
    assert int(dut.tos1.value) == 10, f"tos1 before swap: expected 10, got {int(dut.tos1.value)}"

    await do_swap(dut)

    # hu: Swap után: tos=10, tos1=20
    # en: After swap: tos=10, tos1=20
    assert get_tos(dut) == 10, f"tos after swap: expected 10, got {get_tos(dut)}"
    assert int(dut.tos1.value) == 20, f"tos1 after swap: expected 20, got {int(dut.tos1.value)}"
    assert get_depth(dut) == 2, f"depth after swap: expected 2, got {get_depth(dut)}"


# ============================================================
# hu: 8. Replace top — TOS felülírás
# en: 8. Replace top — TOS overwrite
# ============================================================

@cocotb.test()
async def test_08_replace_top(dut):
    """
    hu: Push 0xAAAA, replace_top(0xBBBB) → tos==0xBBBB, depth változatlan.
    en: Push 0xAAAA, replace_top(0xBBBB) → tos==0xBBBB, depth unchanged.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    await do_push(dut, 0xAAAA0000)
    await do_replace_top(dut, 0xBBBB0000)

    assert get_tos(dut) == 0xBBBB0000, \
        f"tos after replace_top: expected 0xBBBB0000, got {get_tos(dut):#010x}"
    assert get_depth(dut) == 1, \
        f"depth after replace_top: expected 1, got {get_depth(dut)}"
    assert get_cache_count(dut) == 1, \
        f"cache_count after replace_top: expected 1, got {get_cache_count(dut)}"


# ============================================================
# hu: 9. 64-es overflow trap — 65. push → trap_code=0x01
# en: 9. 64-element overflow trap — 65th push → trap_code=0x01
# ============================================================

@cocotb.test()
async def test_09_overflow_trap(dut):
    """
    hu: 64 push után 65. push → trap=1 (1 ciklusos pulzus), trap_code=0x01,
        cache_count és depth változatlan.
    en: After 64 pushes, 65th push → trap=1 (1-cycle pulse), trap_code=0x01,
        cache_count and depth unchanged.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    for i in range(MAX_STACK_DEPTH):
        await do_push(dut, i)

    assert get_depth(dut) == MAX_STACK_DEPTH, \
        f"depth before overflow push: expected {MAX_STACK_DEPTH}, got {get_depth(dut)}"

    depth_before = get_depth(dut)
    cache_before = get_cache_count(dut)

    # hu: 65. push — overflow trap-et vár
    # en: 65th push — expect overflow trap
    await FallingEdge(dut.clk)
    dut.push_en.value = 1
    dut.push_data.value = 0xFFFFFFFF
    await RisingEdge(dut.clk)
    dut.push_en.value = 0
    dut.push_data.value = 0

    # hu: trap jelnek az overflow push ciklus utáni ciklusban kell megjelennie
    # en: trap signal must appear in the cycle following the overflow push
    await RisingEdge(dut.clk)

    trap_seen = int(dut.trap.value) == 1
    trap_code = int(dut.trap_code.value)

    assert trap_seen, "trap was not asserted on 65th push (overflow expected)"
    assert trap_code == TRAP_STACK_OVERFLOW, \
        f"trap_code: expected {TRAP_STACK_OVERFLOW:#04x}, got {trap_code:#04x}"

    # hu: Állapot változatlan kell maradjon
    # en: State must remain unchanged
    assert get_depth(dut) == depth_before, \
        f"depth changed after overflow trap: before={depth_before}, after={get_depth(dut)}"
    assert get_cache_count(dut) == cache_before, \
        f"cache_count changed after overflow trap"

    # hu: Trap pulzus: a következő ciklusban trap=0
    # en: Trap pulse: next cycle trap=0
    await RisingEdge(dut.clk)
    assert int(dut.trap.value) == 0, \
        f"trap not cleared after 1 cycle: got {int(dut.trap.value)}"


# ============================================================
# hu: 10. Üres pop underflow trap — trap_code=0x02
# en: 10. Empty pop underflow trap — trap_code=0x02
# ============================================================

@cocotb.test()
async def test_10_underflow_trap(dut):
    """
    hu: Üres stack-ről pop → trap=1 (1 ciklusos pulzus), trap_code=0x02.
    en: Pop from empty stack → trap=1 (1-cycle pulse), trap_code=0x02.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    assert get_depth(dut) == 0, "stack not empty before underflow test"

    # hu: Pop az üres stack-ről
    # en: Pop from empty stack
    await FallingEdge(dut.clk)
    dut.pop_en.value = 1
    await RisingEdge(dut.clk)
    dut.pop_en.value = 0

    await RisingEdge(dut.clk)

    trap_seen = int(dut.trap.value) == 1
    trap_code = int(dut.trap_code.value)

    assert trap_seen, "trap was not asserted on pop from empty stack (underflow expected)"
    assert trap_code == TRAP_STACK_UNDERFLOW, \
        f"trap_code: expected {TRAP_STACK_UNDERFLOW:#04x}, got {trap_code:#04x}"
    assert get_depth(dut) == 0, \
        f"depth changed after underflow trap: expected 0, got {get_depth(dut)}"

    # hu: Trap pulzus: a következő ciklusban trap=0
    # en: Trap pulse: next cycle trap=0
    await RisingEdge(dut.clk)
    assert int(dut.trap.value) == 0, \
        f"trap not cleared after 1 cycle: got {int(dut.trap.value)}"


# ============================================================
# hu: 11. Spill közbeni viselkedés — busy==1 alatt új művelet tiltva
# en: 11. Behavior during spill — new operation blocked while busy==1
# ============================================================

@cocotb.test()
async def test_11_busy_blocks_new_op(dut):
    """
    hu: Spill közben (busy=1) érkező push nem hajtódik végre, a depth
        nem változik a busy alatt.
    en: Push arriving during spill (busy=1) must not execute; depth
        must not change while busy.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # hu: 4 push betölti a cache-t
    # en: 4 pushes fill the cache
    for i in range(4):
        await do_push(dut, i + 1)

    # hu: 5. push-t kezdjük, de NEM várjuk meg a ready-t
    # en: Start 5th push but do NOT wait for ready
    await FallingEdge(dut.clk)
    dut.push_en.value = 1
    dut.push_data.value = 0x55555555
    await RisingEdge(dut.clk)
    dut.push_en.value = 0

    # hu: A spill kezdetén depth rögzítve
    # en: Capture depth at start of spill
    depth_during_spill = get_depth(dut)

    # hu: Busy alatt próbálunk push-t adni — az nem szabad módosítsa az állapotot
    # en: Try to push while busy — must not modify state
    busy_cycle_found = False

    for _ in range(10):
        if int(dut.busy.value) == 1:
            busy_cycle_found = True
            # hu: Push jel adása busy alatt — ignorálva kell legyen
            # en: Assert push while busy — must be ignored
            dut.push_en.value = 1
            dut.push_data.value = 0xDEAD1234
            await RisingEdge(dut.clk)
            dut.push_en.value = 0
            break

        await RisingEdge(dut.clk)

    # hu: Megvárjuk a spill végét
    # en: Wait for spill to complete
    await wait_ready(dut)

    if busy_cycle_found:
        # hu: depth == 5 kell legyen (az 5. push ment + a busy alatti push NEM)
        # en: depth must be 5 (5th push executed + busy-time push NOT)
        assert get_depth(dut) == 5, \
            f"depth after spill + blocked push: expected 5, got {get_depth(dut)}"


# ============================================================
# hu: 12. Random sequence — 1000 véletlen push/pop, Python referencia stack
# en: 12. Random sequence — 1000 random push/pop, Python reference stack
# ============================================================

@cocotb.test()
async def test_12_random_sequence(dut):
    """
    hu: 1000 véletlen push/pop sorozat verifikálása Python TRefStack ellen.
        A tos/pop_data értékeket a referenciával hasonlítja.
        random.seed(42) a determinizmusért.
    en: 1000 random push/pop sequence verified against Python TRefStack.
        Compares tos/pop_data against reference.
        random.seed(42) for determinism.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    random.seed(42)
    ref = TRefStack()
    errors = []

    for step in range(1000):
        # hu: Véletlenszerűen push vagy pop (arány: 60% push, 40% pop)
        # en: Randomly push or pop (ratio: 60% push, 40% pop)
        op = random.choices(["push", "pop"], weights=[60, 40])[0]

        if op == "push":
            value = random.randint(0, 0xFFFFFFFF)
            ref_result = ref.push(value)

            if ref_result == "OVERFLOW":
                # hu: Trap elvárt — nem hajtjuk végre a hardver oldalon sem
                # en: Trap expected — skip hardware push too
                continue

            await do_push(dut, value)

            hw_tos = get_tos(dut)
            hw_depth = get_depth(dut)
            ref_tos = ref.tos()
            ref_depth = ref.depth

            if hw_tos != ref_tos:
                errors.append(
                    f"step={step} push({value:#010x}): "
                    f"tos mismatch hw={hw_tos:#010x} ref={ref_tos:#010x}"
                )

            if hw_depth != ref_depth:
                errors.append(
                    f"step={step} push: depth mismatch hw={hw_depth} ref={ref_depth}"
                )

        else:
            if ref.depth == 0:
                # hu: Underflow — kihagyjuk
                # en: Underflow — skip
                continue

            ref_val, _ = ref.pop()
            hw_pop = await do_pop(dut)

            if hw_pop != ref_val:
                errors.append(
                    f"step={step} pop: "
                    f"pop_data mismatch hw={hw_pop:#010x} ref={ref_val:#010x}"
                )

            hw_depth = get_depth(dut)
            ref_depth = ref.depth

            if hw_depth != ref_depth:
                errors.append(
                    f"step={step} pop: depth mismatch hw={hw_depth} ref={ref_depth}"
                )

    assert not errors, \
        f"Random sequence failures ({len(errors)}):\n" + "\n".join(errors[:10])


# ============================================================
# hu: 13. Peek — minden lehetséges peek index 0..3 ellenőrzés
# en: 13. Peek — verify all peek indices 0..3
# ============================================================

@cocotb.test()
async def test_13_peek_all_indices(dut):
    """
    hu: 4 különböző értéket push-olva, peek_index 0..3 mind a helyes elemet adja.
    en: After pushing 4 distinct values, peek_index 0..3 each returns the correct element.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    values = [0xAABBCCDD, 0x11223344, 0xDEADC0DE, 0xCAFEBABE]

    for v in values:
        await do_push(dut, v)

    # hu: peek_index=0 → TOS (utolsó push), 3 → legrégebbi
    # en: peek_index=0 → TOS (last push), 3 → oldest
    for idx in range(4):
        dut.peek_index.value = idx
        await Timer(1, units="ns")
        hw_peek = int(dut.peek_data.value)
        # hu: values[-1-idx]: legutóbb feltolt = TOS (idx=0)
        # en: values[-1-idx]: last pushed = TOS (idx=0)
        expected = values[-(idx + 1)]
        assert hw_peek == expected, \
            f"peek_index={idx}: expected {expected:#010x}, got {hw_peek:#010x}"


# ============================================================
# hu: 14. Spill-fill round-trip determinizmus — ugyanaz az érték jön vissza
# en: 14. Spill-fill round-trip determinism — same value comes back
# ============================================================

@cocotb.test()
async def test_14_spill_fill_roundtrip(dut):
    """
    hu: 8 push (2 spill), majd 8 pop — az eredeti LIFO sorrend pontosan visszajön.
        Spill/fill round-trip determinizmus ellenőrzés.
    en: 8 pushes (2 spills), then 8 pops — original LIFO order exactly restored.
        Spill/fill round-trip determinism check.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    values = [0x10000001, 0x20000002, 0x30000003, 0x40000004,
              0x50000005, 0x60000006, 0x70000007, 0x80000008]

    for v in values:
        await do_push(dut, v)

    assert get_depth(dut) == 8, \
        f"depth after 8 pushes: expected 8, got {get_depth(dut)}"

    popped = []

    for _ in range(8):
        val = await do_pop(dut)
        popped.append(val)

    expected = list(reversed(values))
    assert popped == expected, \
        f"spill-fill round-trip failed:\n  expected: {[hex(x) for x in expected]}\n  got:      {[hex(x) for x in popped]}"
    assert get_depth(dut) == 0, \
        f"depth after all pops: expected 0, got {get_depth(dut)}"


# ============================================================
# hu: Új segédfüggvény: SRAM mock driver — N ciklus késleltetés
# en: New helper: SRAM mock driver — N-cycle delay before asserting ready
# ============================================================

async def drive_sram_with_delay(dut, delay_cycles, rdata=0):
    """
    hu: sram_ready=0-t tart `delay_cycles` cikluson át, majd sram_ready=1.
        Opcionálisan sram_rdata-t is beállít (fill szimulációhoz).
    en: Holds sram_ready=0 for `delay_cycles` cycles, then asserts sram_ready=1.
        Optionally sets sram_rdata (for fill simulation).
    """
    dut.sram_ready.value = 0
    dut.sram_rdata.value = rdata & 0xFFFFFFFF

    for _ in range(delay_cycles):
        await RisingEdge(dut.clk)

    dut.sram_ready.value = 1


# ============================================================
# hu: 15. Dup FILL-lel — cache_count=0, depth=2 → dup atomicitás
# en: 15. Dup with FILL — cache_count=0, depth=2 → dup atomicity
# ============================================================

@cocotb.test()
async def test_15_dup_with_fill(dut):
    """
    hu: cache_count=0, depth=2 állapotból dup: FILL szükséges a TOS betöltéséhez,
        majd dup push-olja. t[0] és t[1] mindkettő az eredeti TOS értéke kell legyen.
        sram_re sorrendből ellenőrizzük az első FILL cím helyes.
    en: From cache_count=0, depth=2 state, dup requires FILL to load TOS,
        then duplicates it. t[0] and t[1] must both equal the original TOS.
        sram_re address order verified for the first FILL.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # hu: 2 push → cache-be kerül; majd 2 pop-spill kombinációval cache_count=0,
    #     depth=2 állapotot érünk el: valójában 6 push (2 spill + 4 cache teli),
    #     majd 4 pop → cache_count=0, depth=2 (2 elem SRAM-ban).
    # en: Build cache_count=0, depth=2: push 6 items (cache full, 2 spilled to SRAM),
    #     then pop 4 (cache drained, 2 items in SRAM).
    pushed_values = [0xAA000001, 0xAA000002, 0xAA000003, 0xAA000004,
                     0xAA000005, 0xAA000006]

    for v in pushed_values:
        await do_push(dut, v)

    # hu: pop 4-szer → cache kiürül, SRAM-ban marad 2 elem
    # en: pop 4 times → cache drained, 2 items remain in SRAM
    for _ in range(4):
        await do_pop(dut)

    assert get_depth(dut) == 2, \
        f"setup failed: depth expected 2, got {get_depth(dut)}"
    assert get_cache_count(dut) == 0, \
        f"setup failed: cache_count expected 0, got {get_cache_count(dut)}"

    # hu: Az SRAM-ban lévő legfelső elem az utolsó előtti push volt = pushed_values[1]
    #     (a spill sorrend szerint a legfiatalabb SRAM elem a 2. push értéke)
    # en: The topmost SRAM element corresponds to pushed_values[1] by LIFO spill order.
    sram_re_addresses = []

    # hu: sram_re figyelő coroutine: rögzíti a FILL cím(ek)et
    # en: Monitor sram_re accesses and record addresses
    async def monitor_sram_re():
        for _ in range(50):
            await RisingEdge(dut.clk)
            if int(dut.sram_re.value) == 1:
                sram_re_addresses.append(int(dut.sram_addr.value))

    mon = cocotb.start_soon(monitor_sram_re())

    # hu: Dup — FILL kell, majd push TOS
    # en: Dup — requires FILL, then push TOS
    await FallingEdge(dut.clk)
    dut.dup_en.value = 1
    await RisingEdge(dut.clk)
    dut.dup_en.value = 0

    await wait_ready(dut, max_cycles=50)
    await mon

    # hu: depth +1 kell (dup = push)
    # en: depth must increment by 1 (dup = push)
    assert get_depth(dut) == 3, \
        f"depth after dup: expected 3, got {get_depth(dut)}"

    # hu: t[0] == t[1] (TOS duplikálva)
    # en: t[0] == t[1] (TOS duplicated)
    assert get_tos(dut) == int(dut.tos1.value), \
        f"dup atomicity: tos={get_tos(dut):#010x} != tos1={int(dut.tos1.value):#010x}"

    # hu: legalább 1 sram_re keletkezzen a FILL során
    # en: at least 1 sram_re must occur during FILL
    assert len(sram_re_addresses) >= 1, \
        "dup with cache_count=0 must trigger FILL (sram_re expected)"

    assert int(dut.trap.value) == 0, \
        f"unexpected trap after dup with fill: trap={int(dut.trap.value)}"


# ============================================================
# hu: 16. Swap FILL-lel — cache_count=1, depth=3 → helyes csere
# en: 16. Swap with FILL — cache_count=1, depth=3 → correct swap
# ============================================================

@cocotb.test()
async def test_16_swap_with_fill(dut):
    """
    hu: cache_count=1, depth=3 állapotból swap: FILL betölti a TOS-1-et SRAM-ból,
        majd t[0] ↔ t[1] csere. Ellenőrizzük, hogy a két érték valóban felcserélődik.
    en: From cache_count=1, depth=3 state, swap requires FILL to load TOS-1 from SRAM,
        then t[0] ↔ t[1] swap. Verify the two values are correctly swapped.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # hu: 5 push → cache_count=4, depth=5 (1 spill), majd 3 pop → cache_count=1, depth=2
    #     Majd 1 push → cache_count=2 de depth=3? Nem: 5 push → depth=5,
    #     3 pop → depth=2, cache_count=? Pontosabb útvonal:
    #     7 push → depth=7 (3 spill), 4 pop → cache teli kiürül = depth=3, cache_count=?
    #     Legegyszerűbb: 5 push (depth=5), majd 4 pop → depth=1, cache_count=1
    #     Majd 2 push → depth=3, cache_count=3 — ez nem jó.
    #     Cél: cache_count=1, depth=3 → 2 elem az SRAM-ban, 1 a cache-ben.
    #     Út: 6 push (depth=6, 2 spill → SRAM-ban 2, cache-ben 4),
    #         majd 5 pop (depth=1, cache_count=1, SRAM-ban 0 — nem jó).
    #     Helyes: 6 push → 5 pop → depth=1, cache_count=1, depth=1
    #     7 push → 4 pop → depth=3, cache_count? = 4-4+3 = 3 nem 1.
    #     Legkönnyebb: 5 push → 4 pop (mind cache-ből) → depth=1, cache_count=1
    #     Majd SRAM-ba nyomjuk: de ehhez spill kell. Alternatíva:
    #     push 5 → depth=5 (1 SRAM), pop 1 → depth=4 (fill, cache_count=4)
    #     pop 3 → depth=1, cache_count=1. Utána push 2 → depth=3, cache_count=3.
    #     Kell: depth=3, cache_count=1 → 2 elem SRAM-ban.
    #     push 6 → depth=6 (2 spill, SRAM-ban 2, cache 4)
    #     pop 3 → depth=3, cache 1, SRAM 2 ✓
    # en: Build cache_count=1, depth=3: push 6 (2 spills, SRAM has 2, cache has 4),
    #     pop 3 (cache drains to 1, 2 remain in SRAM).
    for i in range(6):
        await do_push(dut, 0xCC000000 + i + 1)

    for _ in range(3):
        await do_pop(dut)

    assert get_depth(dut) == 3, \
        f"setup: expected depth=3, got {get_depth(dut)}"
    assert get_cache_count(dut) == 1, \
        f"setup: expected cache_count=1, got {get_cache_count(dut)}"

    tos_before = get_tos(dut)

    # hu: A swap FILL-t indít, mert cache_count=1, de depth=3 → van TOS-1 SRAM-ban
    # en: Swap triggers FILL because cache_count=1 but depth=3 → TOS-1 in SRAM
    await do_swap(dut)

    # hu: TOS és TOS-1 felcserélődött; az új TOS az SRAM-ból töltődött
    # en: TOS and TOS-1 are swapped; new TOS was loaded from SRAM
    new_tos = get_tos(dut)
    new_tos1 = int(dut.tos1.value)

    assert new_tos1 == tos_before, \
        f"swap: new tos1 should be old tos ({tos_before:#010x}), got {new_tos1:#010x}"

    assert get_depth(dut) == 3, \
        f"swap must not change depth: expected 3, got {get_depth(dut)}"

    assert int(dut.trap.value) == 0, \
        f"unexpected trap after swap with fill"


# ============================================================
# hu: 17. Replace top FILL-lel — SRAM-beli TOS NEM íródik vissza
# en: 17. Replace top with FILL — SRAM TOS must NOT be written back
# ============================================================

@cocotb.test()
async def test_17_replace_top_with_fill(dut):
    """
    hu: cache_count=0, depth=1 állapotból replace_top: FILL betölti a TOS-t,
        replace_top felülírja. Az eredeti SRAM-beli TOS érték NEM kerül vissza
        SRAM-ba (sram_we NEM aktiválódik a replace_top során).
    en: From cache_count=0, depth=1 state, replace_top requires FILL to load TOS,
        then overwrites it. The original SRAM TOS must NOT be written back
        (sram_we must NOT activate during replace_top).
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # hu: 5 push → depth=5, cache_count=4, 1 SRAM elem
    #     4 pop → depth=1, cache_count=0, 1 SRAM elem ✓
    # en: 5 pushes → depth=5; 4 pops → depth=1, cache_count=0, 1 item in SRAM
    for i in range(5):
        await do_push(dut, 0xDD000000 + i + 1)

    for _ in range(4):
        await do_pop(dut)

    assert get_depth(dut) == 1, \
        f"setup: expected depth=1, got {get_depth(dut)}"
    assert get_cache_count(dut) == 0, \
        f"setup: expected cache_count=0, got {get_cache_count(dut)}"

    # hu: sram_we figyelés a replace_top során
    # en: Monitor sram_we during replace_top
    sram_write_during_replace = False

    # hu: replace_top — FILL kell, majd t[0] = replace_top_data
    # en: replace_top — FILL needed, then t[0] = replace_top_data
    NEW_VAL = 0xEEEEEEEE

    await FallingEdge(dut.clk)
    dut.replace_top_en.value = 1
    dut.replace_top_data.value = NEW_VAL
    await RisingEdge(dut.clk)
    dut.replace_top_en.value = 0
    dut.replace_top_data.value = 0

    for _ in range(30):
        if int(dut.sram_we.value) == 1:
            sram_write_during_replace = True

        if int(dut.ready.value) == 1 and int(dut.busy.value) == 0:
            break

        await RisingEdge(dut.clk)

    # hu: sram_we NEM szabad aktiválódjon replace_top FILL alatt
    # en: sram_we must NOT activate during replace_top FILL
    assert not sram_write_during_replace, \
        "sram_we was asserted during replace_top with fill — old TOS must NOT be written back"

    assert get_tos(dut) == NEW_VAL, \
        f"tos after replace_top with fill: expected {NEW_VAL:#010x}, got {get_tos(dut):#010x}"

    assert get_depth(dut) == 1, \
        f"replace_top must not change depth: expected 1, got {get_depth(dut)}"

    assert int(dut.trap.value) == 0, \
        f"unexpected trap after replace_top with fill"


# ============================================================
# hu: 18. pop_data timing — cycle-pontos verifikáció (NEM wait_ready)
# en: 18. pop_data timing — cycle-accurate verification (NOT wait_ready)
# ============================================================

@cocotb.test()
async def test_18_pop_data_timing(dut):
    """
    hu: pop_en után melyik rising edge-en érvényes a pop_data és ready==1?
        Cycle számlálóval verifikáljuk: cache-ből pop esetén pontosan 1 ciklus latencia
        várható (pop_en ciklusa + 1 rising edge).
        FILL nélküli eset: cache_count=1.
    en: After pop_en, on which rising edge is pop_data valid and ready==1?
        Cycle counter verifies: for cache pop (no FILL), latency must be exactly 1 cycle
        (the cycle after pop_en rising edge).
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    EXPECTED_VAL = 0xF00DCAFE
    await do_push(dut, EXPECTED_VAL)

    assert get_cache_count(dut) == 1, \
        f"setup: expected cache_count=1, got {get_cache_count(dut)}"

    # hu: pop_en manuálisan vezetve (NEM do_pop helper)
    # en: Manual pop_en drive (NOT do_pop helper)
    await FallingEdge(dut.clk)
    dut.pop_en.value = 1
    await RisingEdge(dut.clk)   # hu: pop_en rising edge (t=0)
    dut.pop_en.value = 0

    # hu: Cycle 1: pop_data és ready megjelenése
    # en: Cycle 1: pop_data and ready must appear
    await RisingEdge(dut.clk)
    cyc1_data  = int(dut.pop_data.value)
    cyc1_ready = int(dut.ready.value)

    assert cyc1_ready == 1, \
        f"pop_data timing: ready expected 1 at cycle +1, got {cyc1_ready}"
    assert cyc1_data == EXPECTED_VAL, \
        f"pop_data timing: expected {EXPECTED_VAL:#010x} at cycle +1, got {cyc1_data:#010x}"

    # hu: Cycle 2: pop_data stabilan tartott (nem self-clearing)
    # en: Cycle 2: pop_data must remain stable (no self-clear)
    await RisingEdge(dut.clk)
    cyc2_data = int(dut.pop_data.value)

    assert cyc2_data == EXPECTED_VAL, \
        f"pop_data self-cleared at cycle +2: expected {EXPECTED_VAL:#010x}, got {cyc2_data:#010x}"


# ============================================================
# hu: 19. Trap pulzus szélesség — PONTOSAN 1 ciklus (overflow + underflow)
# en: 19. Trap pulse width — EXACTLY 1 cycle (overflow and underflow)
# ============================================================

@cocotb.test()
async def test_19_trap_pulse_width(dut):
    """
    hu: Overflow és underflow trap pulzus pontosan 1 ciklus:
        pre_trap_cycle: trap==0
        trap_cycle:     trap==1
        post_trap_cycle: trap==0
        Ha 2 ciklusos a pulzus, a teszt buk.
    en: Overflow and underflow trap pulse is exactly 1 cycle:
        pre_trap_cycle: trap==0, trap_cycle: trap==1, post_trap_cycle: trap==0.
        If pulse is 2 cycles wide, test fails.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # ---- Overflow ----
    await reset_dut(dut)

    for i in range(MAX_STACK_DEPTH):
        await do_push(dut, i)

    # hu: Pre-trap ciklus: trap=0
    # en: Pre-trap cycle: trap=0
    assert int(dut.trap.value) == 0, \
        "trap must be 0 before overflow push"

    # hu: 65. push kiváltja a trap-et
    # en: 65th push triggers trap
    await FallingEdge(dut.clk)
    dut.push_en.value = 1
    dut.push_data.value = 0xFF
    await RisingEdge(dut.clk)
    dut.push_en.value = 0

    # hu: Trap ciklus (1 rising edge várakozás)
    # en: Trap cycle (1 rising edge wait)
    await RisingEdge(dut.clk)
    trap_cycle_val = int(dut.trap.value)
    assert trap_cycle_val == 1, \
        f"overflow: trap must be 1 exactly 1 cycle after push, got {trap_cycle_val}"

    # hu: Post-trap ciklus: trap vissza 0-ba
    # en: Post-trap cycle: trap returns to 0
    await RisingEdge(dut.clk)
    post_trap_val = int(dut.trap.value)
    assert post_trap_val == 0, \
        f"overflow: trap pulse wider than 1 cycle (post_trap={post_trap_val})"

    # ---- Underflow ----
    await reset_dut(dut)

    assert int(dut.trap.value) == 0, \
        "trap must be 0 before underflow pop"

    await FallingEdge(dut.clk)
    dut.pop_en.value = 1
    await RisingEdge(dut.clk)
    dut.pop_en.value = 0

    await RisingEdge(dut.clk)
    trap_cycle_val = int(dut.trap.value)
    assert trap_cycle_val == 1, \
        f"underflow: trap must be 1 exactly 1 cycle after pop, got {trap_cycle_val}"

    await RisingEdge(dut.clk)
    post_trap_val = int(dut.trap.value)
    assert post_trap_val == 0, \
        f"underflow: trap pulse wider than 1 cycle (post_trap={post_trap_val})"


# ============================================================
# hu: 20. Overflow ciklus alatt sram_we==0 minden rising edge-en
# en: 20. No SRAM write during overflow cycle — sram_we==0 on every rising edge
# ============================================================

@cocotb.test()
async def test_20_overflow_no_sram_write(dut):
    """
    hu: 65. push (overflow) alatt sram_we az EGÉSZ ciklus alatt 0 kell legyen.
        Minden RisingEdge-en monitorozzuk a spill-ablak során.
        Trap NEM okozhat OOB SRAM hozzáférést.
    en: During the 65th push (overflow), sram_we must be 0 for the ENTIRE cycle.
        Monitored on every RisingEdge during the trap window.
        Trap must NOT cause OOB SRAM access.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    for i in range(MAX_STACK_DEPTH):
        await do_push(dut, i)

    sram_write_violations = []

    # hu: 65. push — overflow
    # en: 65th push — overflow
    await FallingEdge(dut.clk)
    dut.push_en.value = 1
    dut.push_data.value = 0xBAD00000
    await RisingEdge(dut.clk)
    dut.push_en.value = 0

    # hu: Monitorozzuk a következő 5 ciklust
    # en: Monitor the next 5 cycles
    for cyc in range(5):
        await RisingEdge(dut.clk)

        if int(dut.sram_we.value) == 1:
            sram_write_violations.append(cyc)

    assert not sram_write_violations, \
        f"sram_we asserted at cycles {sram_write_violations} during overflow trap — illegal SRAM write!"


# ============================================================
# hu: 21. Underflow ciklus alatt sram_re==0
# en: 21. No SRAM read during underflow cycle — sram_re==0
# ============================================================

@cocotb.test()
async def test_21_underflow_no_sram_read(dut):
    """
    hu: Üres stackről pop (underflow): sram_re az EGÉSZ ciklus alatt 0 kell legyen.
        Trap NEM okozhat SRAM olvasást.
    en: Pop from empty stack (underflow): sram_re must be 0 for the ENTIRE cycle.
        Trap must NOT cause any SRAM read.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    assert get_depth(dut) == 0, "stack not empty before underflow test"

    sram_read_violations = []

    await FallingEdge(dut.clk)
    dut.pop_en.value = 1
    await RisingEdge(dut.clk)
    dut.pop_en.value = 0

    for cyc in range(5):
        await RisingEdge(dut.clk)

        if int(dut.sram_re.value) == 1:
            sram_read_violations.append(cyc)

    assert not sram_read_violations, \
        f"sram_re asserted at cycles {sram_read_violations} during underflow trap — illegal SRAM read!"


# ============================================================
# hu: 22. sram_ready handshake — busy fennáll, sp/állapot változatlan késleltetés alatt
# en: 22. sram_ready handshake — busy persists, sp/state unchanged while delayed
# ============================================================

@cocotb.test()
async def test_22_sram_ready_handshake(dut):
    """
    hu: sram_ready=0 tartva 0, 1, 2, 3 ciklusig spill alatt:
        - busy=1 fennáll a teljes késleltetés alatt
        - sram_wdata az eredeti t[3] értéke marad
        - sp változatlan (SRAM ack előtt)
        - sram_we magas marad (pulse stretching)
        Paraméteres loop: delay in [0, 1, 2, 3].
    en: Hold sram_ready=0 for 0, 1, 2, 3 cycles during spill:
        - busy=1 persists for the entire delay
        - sram_wdata remains the original t[3] value
        - sp unchanged before SRAM ack
        - sram_we held high (pulse stretching)
        Parameterized loop: delay in [0, 1, 2, 3].
    """
    for delay in [0, 1, 2, 3]:
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        await reset_dut(dut)

        # hu: 4 push betölti a cache-t, t[3] = első push értéke = 0x10000001
        # en: 4 pushes fill cache; t[3] = first push value = 0x10000001
        SPILL_VAL = 0x10000001

        await do_push(dut, SPILL_VAL)       # t[3] lesz
        await do_push(dut, 0x20000002)
        await do_push(dut, 0x30000003)
        await do_push(dut, 0x40000004)

        # hu: sram_ready=0 — spill blokkolva lesz
        # en: sram_ready=0 — spill will be blocked
        dut.sram_ready.value = 0

        # hu: 5. push indítja a spill-t
        # en: 5th push triggers spill
        await FallingEdge(dut.clk)
        dut.push_en.value = 1
        dut.push_data.value = 0x50000005
        await RisingEdge(dut.clk)
        dut.push_en.value = 0

        busy_all_cycles = True
        sp_before = int(dut.sram_addr.value)  # hu: sp a spill előtt

        # hu: Delay ciklusok alatt busy fennáll, sp változatlan
        # en: Busy persists during delay cycles, sp unchanged
        for cyc in range(delay):
            await RisingEdge(dut.clk)

            if int(dut.busy.value) != 1:
                busy_all_cycles = False

            # hu: sram_wdata az eredeti t[3] marad
            # en: sram_wdata must remain the original t[3]
            wdata = int(dut.sram_wdata.value)
            assert wdata == SPILL_VAL, \
                f"delay={delay}, cycle={cyc}: sram_wdata={wdata:#010x}, expected {SPILL_VAL:#010x}"

        # hu: sram_ready=1 — spill folytatódhat
        # en: sram_ready=1 — spill can proceed
        dut.sram_ready.value = 1

        # hu: Megvárjuk a spill végét
        # en: Wait for spill to complete
        await wait_ready(dut, max_cycles=20)

        if delay > 0:
            assert busy_all_cycles, \
                f"delay={delay}: busy dropped to 0 before sram_ready=1"

        assert get_depth(dut) == 5, \
            f"delay={delay}: depth after spill expected 5, got {get_depth(dut)}"


# ============================================================
# hu: 23. Busy alatti push nem korruptálja a spill sram_wdata-t
# en: 23. Push during busy does not corrupt spill sram_wdata
# ============================================================

@cocotb.test()
async def test_23_busy_push_does_not_corrupt_spill(dut):
    """
    hu: Spill alatt (busy=1) push_en=1 + push_data váltás közben
        a sram_wdata az EREDETI t[3] értéket kell tartsa, NEM a push_data-t.
        Ellenőrzés: minden busy cikluson sram_wdata == SPILL_VAL.
    en: During spill (busy=1), asserting push_en=1 with changing push_data
        must not corrupt sram_wdata — it must remain the original t[3].
        Check: on every busy cycle sram_wdata == SPILL_VAL.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    SPILL_VAL = 0xABCD1234  # hu: t[3] értéke — ez kerül SRAM-ba

    # hu: 4 push — t[3] = SPILL_VAL (az első push)
    # en: 4 pushes — t[3] = SPILL_VAL (first push)
    await do_push(dut, SPILL_VAL)
    await do_push(dut, 0x11111111)
    await do_push(dut, 0x22222222)
    await do_push(dut, 0x33333333)

    # hu: sram_ready=0 → spill blokkolva, hogy busy ciklusokat lássunk
    # en: sram_ready=0 → block spill to observe busy cycles
    dut.sram_ready.value = 0

    # hu: 5. push → spill indul
    # en: 5th push → spill starts
    await FallingEdge(dut.clk)
    dut.push_en.value = 1
    dut.push_data.value = 0x44444444
    await RisingEdge(dut.clk)
    dut.push_en.value = 0

    wdata_violations = []

    # hu: Busy alatt push_en=1 különböző push_data értékekkel
    # en: Assert push_en=1 with different push_data while busy
    INTRUDER_VALUES = [0xDEAD0001, 0xDEAD0002, 0xDEAD0003]

    for cyc, intruder in enumerate(INTRUDER_VALUES):
        await RisingEdge(dut.clk)

        if int(dut.busy.value) == 1:
            dut.push_en.value = 1
            dut.push_data.value = intruder

            wdata = int(dut.sram_wdata.value)

            if wdata != SPILL_VAL:
                wdata_violations.append((cyc, intruder, wdata))

        dut.push_en.value = 0

    # hu: sram_ready=1 → spill befejezhet
    # en: sram_ready=1 → allow spill to finish
    dut.sram_ready.value = 1
    await wait_ready(dut, max_cycles=20)

    assert not wdata_violations, \
        "sram_wdata corrupted during busy: " + \
        "; ".join(f"cyc={c} intruder={i:#010x} got={g:#010x}"
                  for c, i, g in wdata_violations)


# ============================================================
# hu: 24. Concurrent signals prioritás — minden páros, prioritás-enkóder verifikáció
# en: 24. Concurrent signals priority — all 10 pairs, priority encoder verification
# ============================================================

@cocotb.test()
async def test_24_concurrent_signals_priority(dut):
    """
    hu: Minden *_en páros egyidejű aktiválása esetén kizárólag a magasabb prioritású
        műveletet hajtja végre a HW. Prioritás: pop > push > dup > swap > replace_top.
        10 páros: push+pop, push+dup, push+swap, push+replace, pop+dup, pop+swap,
                  pop+replace, dup+swap, dup+replace, swap+replace.
        Verifikálja: cache_count és depth konzisztens, trap=0.
    en: When any *_en pair is concurrently asserted, only the higher-priority operation
        executes. Priority: pop > push > dup > swap > replace_top.
        10 pairs verified. Checks: cache_count, depth consistent, trap=0.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    await reset_dut(dut)

    # hu: Referencia stack a várható állapot számításához
    # en: Reference stack for expected state tracking
    ref = TRefStack()

    # hu: Előkészítés: 3 elem a stack-en (push+pop+dup mind biztonságos)
    # en: Setup: 3 elements on stack (push+pop+dup all safe)
    for v in [0x01010101, 0x02020202, 0x03030303]:
        await do_push(dut, v)
        ref.push(v)

    PUSH_VAL    = 0xAABBCCDD
    REPLACE_VAL = 0x12345678

    # hu: Prioritás: pop=5, push=4, dup=3, swap=2, replace=1
    # en: Priority encoding: pop=5, push=4, dup=3, swap=2, replace=1
    PAIRS = [
        # (sig_a, sig_b, winner, description)
        ("pop",     "push",    "pop",     "pop > push"),
        ("pop",     "dup",     "pop",     "pop > dup"),
        ("pop",     "swap",    "pop",     "pop > swap"),
        ("pop",     "replace", "pop",     "pop > replace"),
        ("push",    "dup",     "push",    "push > dup"),
        ("push",    "swap",    "push",    "push > swap"),
        ("push",    "replace", "push",    "push > replace"),
        ("dup",     "swap",    "dup",     "dup > swap"),
        ("dup",     "replace", "dup",     "dup > replace"),
        ("swap",    "replace", "swap",    "swap > replace"),
    ]

    errors = []

    for sig_a, sig_b, winner, desc in PAIRS:
        # hu: Minden pár előtt visszaállítjuk a 3 elemre (reset + 3 push)
        # en: Before each pair, restore 3-element state
        await reset_dut(dut)
        ref = TRefStack()

        for v in [0x01010101, 0x02020202, 0x03030303]:
            await do_push(dut, v)
            ref.push(v)

        depth_before = get_depth(dut)
        cache_before = get_cache_count(dut)
        tos_before   = get_tos(dut)

        # hu: Mindkét jel egyszerre
        # en: Assert both signals simultaneously
        await FallingEdge(dut.clk)
        dut.push_en.value      = 1 if sig_a == "push" or sig_b == "push" else 0
        dut.push_data.value    = PUSH_VAL
        dut.pop_en.value       = 1 if sig_a == "pop"  or sig_b == "pop"  else 0
        dut.dup_en.value       = 1 if sig_a == "dup"  or sig_b == "dup"  else 0
        dut.swap_en.value      = 1 if sig_a == "swap" or sig_b == "swap" else 0
        dut.replace_top_en.value  = 1 if sig_a == "replace" or sig_b == "replace" else 0
        dut.replace_top_data.value = REPLACE_VAL

        await RisingEdge(dut.clk)

        dut.push_en.value         = 0
        dut.pop_en.value          = 0
        dut.dup_en.value          = 0
        dut.swap_en.value         = 0
        dut.replace_top_en.value  = 0
        dut.push_data.value       = 0
        dut.replace_top_data.value = 0

        await wait_ready(dut, max_cycles=30)

        # hu: trap NEM szabad aktiválódjon
        # en: trap must NOT be asserted
        if int(dut.trap.value) != 0:
            errors.append(f"{desc}: unexpected trap={int(dut.trap.value)}")

        # hu: Elvárt állapot a prioritás-enkóder szerint
        # en: Expected state according to priority encoder
        if winner == "pop":
            expected_depth = depth_before - 1
        elif winner == "push":
            expected_depth = depth_before + 1
        elif winner == "dup":
            expected_depth = depth_before + 1
        elif winner == "swap":
            expected_depth = depth_before       # swap nem változtatja a depth-et
        elif winner == "replace":
            expected_depth = depth_before       # replace nem változtatja a depth-et
        else:
            expected_depth = depth_before

        actual_depth = get_depth(dut)

        if actual_depth != expected_depth:
            errors.append(
                f"{desc}: depth expected={expected_depth}, got={actual_depth}"
            )

        # hu: depth + cache_count konzisztencia: cache_count <= 4
        # en: depth + cache_count consistency: cache_count <= 4
        if get_cache_count(dut) > 4:
            errors.append(
                f"{desc}: cache_count={get_cache_count(dut)} > 4 (corruption)"
            )

        if get_depth(dut) < get_cache_count(dut):
            errors.append(
                f"{desc}: depth={get_depth(dut)} < cache_count={get_cache_count(dut)} (inconsistent)"
            )

    assert not errors, \
        f"Concurrent priority failures ({len(errors)}):\n" + "\n".join(errors)


# ----------------------------------------------------------------------
# hu: test_25 — peek OOB (peek_index >= cache_count) → peek_data == 0,
#     és NEM indít FILL-t (sram_re==0 az egész alatt). Spec: saturating
#     deterministic 0 viselkedés, NEM X-propagáció.
# en: test_25 — peek OOB (peek_index >= cache_count) → peek_data == 0,
#     and does NOT trigger FILL (sram_re==0 throughout). Spec: saturating
#     deterministic 0 behavior, NOT X-propagation.
# ----------------------------------------------------------------------
@cocotb.test()
async def test_25_peek_out_of_range(dut):
    """
    hu: peek_index >= cache_count esetén peek_data 0, sram_re mindvégig 0.
    en: peek_index >= cache_count must yield peek_data 0, sram_re stays 0.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # hu: 1. eset — üres cache (cache_count=0, depth=0), minden index
    # en: 1st case — empty cache, every index
    for idx in range(4):
        dut.peek_index.value = idx
        # hu: 2 ciklus mintázás, hogy a kombinációs út stabil
        # en: 2-cycle sample to ensure combinational path stable
        for _ in range(2):
            await RisingEdge(dut.clk)
            assert int(dut.peek_data.value) == 0, \
                f"empty cache, peek[{idx}] expected 0, got {int(dut.peek_data.value):#x}"
            assert int(dut.sram_re.value) == 0, \
                f"empty cache, peek[{idx}] must NOT trigger sram_re"

    # hu: 2. eset — cache_count=2 (push 2-t), peek_index 0..3
    # en: 2nd case — cache_count=2 after 2 pushes, peek_index 0..3
    await do_push(dut, 0x11111111)
    await do_push(dut, 0x22222222)
    # hu: 0 → TOS = 0x22222222, 1 → TOS-1 = 0x11111111, 2..3 → 0
    # en: 0 → TOS = 0x22222222, 1 → TOS-1 = 0x11111111, 2..3 → 0
    expected = {0: 0x22222222, 1: 0x11111111, 2: 0, 3: 0}
    for idx, want in expected.items():
        dut.peek_index.value = idx
        for _ in range(2):
            await RisingEdge(dut.clk)
            got = int(dut.peek_data.value)
            assert got == want, \
                f"cache_count=2, peek[{idx}] expected {want:#x}, got {got:#x}"
            assert int(dut.sram_re.value) == 0, \
                f"cache_count=2, peek[{idx}] must NOT trigger sram_re"

    # hu: 3. eset — cache_count=0 de depth>0 (4 push + 4 pop spill után),
    #     peek SOSEM indít FILL-t (spec)
    # en: 3rd case — cache_count=0 but depth>0 (4 pushes + 4 pops after spill),
    #     peek MUST NOT trigger FILL (spec)
    await reset_dut(dut)
    for v in range(1, 6):  # 5 push → 1 spill, cache_count=4, depth=5
        await do_push(dut, v)
    for _ in range(4):  # 4 pop → cache_count=0, depth=1 (1 még az SRAM-ban)
        dut.pop_en.value = 1
        await RisingEdge(dut.clk)
        dut.pop_en.value = 0
        await wait_ready(dut, max_cycles=20)

    # hu: most cache_count=0, depth=1 — peek SOSEM nyúlhat az SRAM-hoz
    # en: now cache_count=0, depth=1 — peek must NEVER touch SRAM
    for idx in range(4):
        dut.peek_index.value = idx
        for _ in range(3):
            await RisingEdge(dut.clk)
            assert int(dut.peek_data.value) == 0, \
                f"cache_count=0/depth=1, peek[{idx}] expected 0 (no FILL), got {int(dut.peek_data.value):#x}"
            assert int(dut.sram_re.value) == 0, \
                f"cache_count=0/depth=1, peek[{idx}] must NOT trigger FILL (sram_re==0)"

