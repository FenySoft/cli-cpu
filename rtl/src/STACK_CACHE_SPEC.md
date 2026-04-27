# F2.3 Stack Cache — Kontrakt és Portspec

> Belső munka-spec a TDD ciklushoz. Aranypélda: `TCpuNano.EvalPush/EvalPop/EvalPeek` (`src/CilCpu.Sim/TCpuNano.cs`).
>
> **Hatókör:** Belső RTL munka-spec, nem publikus dokumentum. A publikus ISA spec a `docs/ISA-CIL-T0-{hu,en}.md`.
>
> **Verzió:** 1.1 — 2026-04-27

## Cél

Fizikai 4-elem Top-of-Stack cache + spill/fill az SRAM stack régiójába (`0x2000_0000`). A felsőbb microcode felé transzparens — `push_en`, `pop_en`, `dup_en`, `swap_en`, `replace_top_en` jelekkel vezérelhető. A teljes eval stack max. mélység 64 (`MAX_STACK_DEPTH`).

## Modul: `cilcpu_stack_cache`

### Portok

| Irány | Név | Szélesség | Leírás |
|-------|-----|-----------|--------|
| in | `clk` | 1 | Órajel |
| in | `rst_n` | 1 | Aszinkron aktív-low reset |
| in | `sp_load` | 1 | SP regiszter betöltés engedélyezés |
| in | `sp_init` | 14 | Kezdeti SP érték (frame setup-ból) |
| in | `push_en` | 1 | Push művelet — `push_data` a stack tetejére |
| in | `push_data` | 32 | Push adat |
| in | `pop_en` | 1 | Pop művelet — `pop_data` a régi TOS |
| in | `dup_en` | 1 | Duplikálás — TOS push (push TOS) |
| in | `swap_en` | 1 | TOS ↔ TOS-1 csere |
| in | `replace_top_en` | 1 | TOS felülírás (ALU result, peek után írás) |
| in | `replace_top_data` | 32 | Új TOS érték |
| in | `peek_index` | 2 | Olvasandó offszet (0=TOS, 1=TOS-1, 2=TOS-2, 3=TOS-3) |
| out | `peek_data` | 32 | Olvasott érték (kombinációs) |
| out | `tos` | 32 | TOS érték (kombinációs, gyors út) |
| out | `tos1` | 32 | TOS-1 érték (kombinációs) |
| out | `pop_data` | 32 | Pop eredménye (regisztrált) |
| out | `depth` | 7 | Teljes eval stack mélység (0..64) |
| out | `cache_count` | 3 | Cache-ben lévő elemek (0..4) |
| out | `busy` | 1 | Spill/fill folyamatban — új művelet TILTVA |
| out | `ready` | 1 | Művelet befejeződött, eredmény érvényes |
| out | `trap` | 1 | Trap pulzus |
| out | `trap_code` | 8 | `TRAP_STACK_OVERFLOW` (0x01) vagy `TRAP_STACK_UNDERFLOW` (0x02) |
| out | `sram_addr` | 14 | SRAM cím (master) |
| out | `sram_wdata` | 32 | SRAM íróadat |
| in | `sram_rdata` | 32 | SRAM olvasott adat |
| out | `sram_we` | 1 | SRAM write enable |
| out | `sram_re` | 1 | SRAM read enable |
| in | `sram_ready` | 1 | SRAM kész jel (1-ciklusos SRAM esetén lehet 1'b1) |

### Belső állapot

- 4×32-bit TOS regiszter: `t[0..3]`, ahol `t[0]` = TOS, `t[3]` = TOS-3
- `sp[13:0]` — pointer a következő szabad SRAM slot-ra (relatív a stack régió bázisához vagy abszolút, F1-kompatibilis)
- `cache_count[2:0]` — 0..4
- `state[1:0]` — `IDLE`, `SPILL`, `FILL`

### Viselkedés

#### Reset
- `rst_n=0` → `cache_count=0`, `state=IDLE`, `sp` undefined (sp_load + sp_init kell elindulás előtt)
- `trap=0`, `busy=0`, `ready=1`

#### Push (`push_en=1` IDLE-ban)
- Ha `depth >= 64` → `trap=1`, `trap_code=TRAP_STACK_OVERFLOW` (1 ciklus pulzus), állapot változatlan
- Ha `cache_count < 4`: T léptetés (`t[3]<=t[2]`, `t[2]<=t[1]`, `t[1]<=t[0]`, `t[0]<=push_data`), `cache_count++`. 1 ciklus, `ready=1`
- Ha `cache_count == 4`: SPILL állapotba — `state=SPILL`, `busy=1`, `ready=0`. Ekkor `sram_we=1`, `sram_addr=sp`, `sram_wdata=t[3]`. SRAM ack után: `sp+=4`, T léptetés + push_data, `cache_count` marad 4, vissza `IDLE`-be, `ready=1` (legalább 2 ciklus)

#### Pop (`pop_en=1` IDLE-ban)
- Ha `depth == 0` → `trap=1`, `trap_code=TRAP_STACK_UNDERFLOW`, állapot változatlan
- Ha `cache_count > 0`: `pop_data <= t[0]`, T léptetés (`t[0]<=t[1]`, `t[1]<=t[2]`, `t[2]<=t[3]`, `t[3]` = X), `cache_count--`. 1 ciklus
- Ha `cache_count == 0` és `depth > 0`: FILL — `state=FILL`, `busy=1`. `sp-=4`, `sram_re=1`, `sram_addr=sp`. SRAM ack után: `pop_data <= sram_rdata`, vissza `IDLE`. (Megj.: a `depth==0 && cache_count==0` esetben az underflow-ra kell ügyelni — ha `depth>=1` de `cache_count==0`, akkor van SRAM-ban legalább 1 elem.)

#### Dup (`dup_en=1`)
- Megegyezik egy push-szal, ahol a `push_data` a `t[0]` aktuális értéke
- Ha `cache_count==0` és `depth==0` → `TRAP_STACK_UNDERFLOW` (nincs mit duplikálni)
- Ha `cache_count==0` és `depth>0` → előbb FILL kell — multi-cycle: FILL után SPILL/PUSH

#### Swap (`swap_en=1`)
- `t[0] ↔ t[1]`
- Ha `cache_count<2` és `depth>=2` → előbb FILL hogy `cache_count>=2` legyen
- Ha `depth<2` → `TRAP_STACK_UNDERFLOW`

#### Replace top (`replace_top_en=1`)
- `t[0] <= replace_top_data`
- Ha `cache_count==0` és `depth==0` → `TRAP_STACK_UNDERFLOW`
- Ha `cache_count==0` és `depth>0` → FILL előbb

#### Több jel egyszerre
- Egy ciklusban egyszerre csak 1 művelet engedélyezett (microcode garantálja). Ha mégis több — a viselkedés definiálatlan, de a teszt fedezi le, hogy NEM omlik össze (`trap=1` és `cache_count` nem korruptálódik).

### `depth` definíció

`depth = cache_count + sram_count`, ahol `sram_count = (sp - sp_init) / 4`. A spill/fill közben a `depth` változatlan kell maradjon (csak az elhelyezkedés változik cache vs. SRAM között).

### Trap szemantika

- Trap **pontosan 1 órajel-ciklusos pulzus** a `trap` és `trap_code` jeleken, edge-aligned: a megelőző `*_en` ciklust követő rising edge-en jelenik meg, és a következő rising edge-en már `trap=0`
- Trap alatt az állapot **változatlan** (nem írunk semmit, nem léptetünk)
- Trap alatt **`sram_we==0` és `sram_re==0` az ENGÉSZ ciklus alatt** — overflow/underflow trap NEM okozhat OOB SRAM hozzáférést
- A felsőbb microcode felelős a trap propagálásáért és a CPU halt-olásáért

### `pop_data` érvényességi ablak

- `pop_data` regisztrált, és a `ready=1` jellel egyidőben (ugyanazon rising edge-en) lesz érvényes
- Egyciklusos pop esetén: `pop_en` ciklus után 1 órajellel áll be
- FILL-es pop esetén: amíg `busy=1`, a `pop_data` undefined; `ready=1` rising edge-én áll be
- Az érték a következő művelet `*_en` jelének rising edge-éig stabilan tartott (nincs "1 ciklus után self-clear")

### `peek_data` szemantika

- Csak `cache_count > peek_index` esetén definiált
- Ha `peek_index >= cache_count`: `peek_data = 32'h0` (deterministic 0, NEM X) — saturating viselkedés
- A microcode felelőssége nem hívni `peek`-et OOB indexszel; ezt a stack cache nem trap-eli (ez nem ISA-szintű hiba)
- A `peek` SOSEM indít FILL-t — kizárólag a cache regiszterekből olvas

### `sram_ready` handshake (KÖTELEZŐ)

- A SPILL és FILL állapot **mindig megvárja** az `sram_ready=1`-et
- Amíg `sram_ready=0` a SPILL/FILL alatt, a Verilog-nak: `busy=1` fennáll, `sp` változatlan, a cache regiszterek változatlanok, `sram_we`/`sram_re` magasan tartott (pulse stretching, NEM 1-ciklusos)
- A teszt különböző `sram_ready` késleltetésekkel (0, 1, 2, 3 ciklus) verifikálja
- Sky130 PDK SRAM-ja 1-ciklusos, tehát `sram_ready=1'b1` állandóan elfogadható — de a Verilog NEM építhet erre, mert F2.4 QSPI-PSRAM 2-3 ciklusos

### `busy` alatti `*_en` jelek

- Bármely `*_en` jel `busy=1` alatt **csendben ignorálva**, NEM regisztrált, NEM várólistára helyezett, NEM trap
- A microcode felelős nem aktiválni új műveletet `busy` alatt
- A teszt direkt a busy alatti push-jelek és a SPILL belső `sram_wdata` épségét egyszerre verifikálja

### Egyidejű `*_en` jelek prioritása

A jelek egyidejű aktiválása illegális microcode hibát jelez, de a HW-nek **determinisztikusan, biztonságosan** kell viselkednie. Prioritás-enkóder, fentről lefelé:

1. `pop_en` (legmagasabb)
2. `push_en`
3. `dup_en`
4. `swap_en`
5. `replace_top_en` (legalacsonyabb)

Egynél több jel egyidejű aktiválás esetén kizárólag a legmagasabb prioritású hajtódik végre, a többi figyelmen kívül hagyva. A trap nem aktiválódik (ez a microcode hibája, nem ISA-szintű hiba).

### `sp_init` igazítás

- `sp_init` **word-aligned** (alsó 2 bit 0) — a HW NEM ellenőrzi és NEM trap-eli
- A microcode/firmware felelős a helyes `sp_init` átadásáért
- Reset alatt érkező `sp_load` figyelmen kívül hagyva

### `sram_addr` IDLE-ban

- IDLE állapotban (`busy=0`) a `sram_addr` érték **don't-care**, de a Verilog tervezőnek **stabilan tartani kell** (ne legyen lebegő, ne X) — ajánlott a `sp` aktuális értékét hajtani rá, ezzel a SPILL/FILL kezdetekor 0 előre-glitch
- A `sram_we`/`sram_re` IDLE-ban kötelezően `0` — ezért az `sram_addr` értéke fizikailag nem hat a memóriára

### Reset szemantika (kibővítve)

- `rst_n=0` aszinkron törli: `cache_count=0`, `state=IDLE`, `trap=0`, `busy=0`, `ready=1`
- `sp` reset alatt undefined (X) — a microcode-nak el kell végeznie egy `sp_load` ciklust az első push előtt
- Reset assert ALATT érkező `*_en`/`sp_load`/`push_data` jelek figyelmen kívül hagyottak (FF nem írható)
- `rst_n=1` rising edge után **legalább 1 ciklusig** a `*_en` jelek hatástalanok (re-sync ablak)

## Tesztstratégia (TDD)

A teszt-sorrend (a 2. taskban):

1. **Reset és inicializálás** — `cache_count=0`, `depth=0`, `ready=1` reset után
2. **Egyszerű push** — 1 push, `tos == push_data`, `cache_count==1`, `depth==1`
3. **4 push cache-be** — `cache_count==4`, `depth==4`, nincs SRAM access
4. **5. push spill-lel** — SRAM write-ot megfigyelve a t[3] kerül ki, `depth==5`, `cache_count==4`
5. **Pop visszafelé spill-fillel** — sorra leveszi az 5 elemet, fill az SRAM-ból
6. **Dup** — `cache_count==1`-ből dup → 2, mindkettő ugyanaz
7. **Swap** — két érték, swap, ellenőrzi a sorrendet
8. **Replace top** — TOS felülírás
9. **64-es overflow trap** — 65. push → `trap_code=0x01`, `cache_count` változatlan
10. **Üres pop underflow trap** — `trap_code=0x02`
11. **Spill közbeni viselkedés** — `busy==1` alatt új művelet nem hajtódik végre
12. **Random sequence** — 1000 véletlen push/pop sorozat, verifikálás Python referencia stack ellen
13. **Peek** — minden lehetséges peek index 0..3 ellenőrzés
14. **Spill-fill round-trip determinizmus** — ugyanaz az érték jön vissza

### Devil's Advocate review #1 alapján kiegészített tesztek

15. **`dup` FILL-lel** — `cache_count=0, depth=2` állapotból dup; FILL atomicitás, helyes `t[0]/t[1]` és `sram_re` címsorrend
16. **`swap` FILL-lel** — `cache_count=1, depth=3` állapotból swap; FILL után `t[0]/t[1]` helyes csere
17. **`replace_top` FILL-lel** — `cache_count=0, depth=1` állapotból replace_top; régi SRAM-beli TOS NEM íródik vissza
18. **`pop_data` cycle-pontos timing** — `pop_en` után melyik rising edge-en érvényes a `pop_data`; cycle számláló alapú
19. **Trap pulzus szélesség** — overflow + underflow eseteiben `trap=1` PONTOSAN 1 ciklus, sem több, sem kevesebb
20. **Overflow ciklus alatt nincs SRAM write** — 65. push alatt `sram_we==0` az egész ciklus alatt
21. **Underflow ciklus alatt nincs SRAM read** — üres pop alatt `sram_re==0`
22. **`sram_ready` handshake** — `sram_ready=0` 1, 2, 3 ciklusig spill alatt; `busy` fennáll, `sp` és `t[3]` változatlan, írás csak `ready=1` után
23. **Busy alatti push nem korruptálja a spill-t** — busy alatt push_en+push_data váltás közben `sram_wdata` az eredeti `t[3]` marad
24. **Concurrent signals prioritás** — minden páros (push+pop, dup+swap, push+dup, …) tesztelve a prioritás-enkóder szerint; `cache_count` és `depth` konzisztens marad
25. **`peek_index` OOB** — `peek_index >= cache_count` esetén `peek_data == 0`, és NEM indít FILL-t (`sram_re==0`)

## Changelog

| Verzió | Dátum | Változás |
|--------|-------|---------|
| 1.0 | 2026-04-27 | Első verzió — 4-elem TOS cache, SPILL/FILL, 14 teszt-pont |
| 1.1 | 2026-04-27 | Devil's Advocate review után: trap pulzus pontos timing, pop_data validity ablak, peek OOB saturating 0, sram_ready handshake, busy alatti *_en ignorálás, concurrent prioritás-enkóder, sp_init word-aligned, kibővített reset, sram_addr IDLE-ban don't-care; +11 teszt (test_15..test_25) |
