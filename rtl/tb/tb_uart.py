# hu: Közös cocotb UART RX dekódoló — 8N1 keret, paraméterezhető baud-osztó.
#     A wrapper UART kimenet (`o_uart_tx`) byte-okra fordításához használjuk
#     a top-level integrációs tesztekben.
# en: Shared cocotb UART RX decoder — 8N1 frame, parameterizable baud
#     divider. Used by top-level integration tests to translate the wrapper's
#     UART output (`o_uart_tx`) back into bytes.

import cocotb
from cocotb.triggers import RisingEdge, Edge


async def uart_tx_byte(dut, rx_signal, clocks_per_baud, byte_val):
    """hu: Egyetlen 8N1 byte KÜLDÉSE a DUT `rx_signal` bemenetére (a teszt a
        host UART-adó). Start bit (0), 8 data bit LSB-first, stop bit (1) —
        mindegyik `clocks_per_baud` órajel-cikluson át.
    en: SENDS a single 8N1 byte onto the DUT's `rx_signal` input (the test acts
        as the host UART transmitter). Start bit (0), 8 data bits LSB-first,
        stop bit (1) — each held for `clocks_per_baud` clock cycles."""
    clk = dut.i_clk_50m if hasattr(dut, "i_clk_50m") else dut.clk

    # hu: start bit
    rx_signal.value = 0
    for _ in range(clocks_per_baud):
        await RisingEdge(clk)

    # hu: 8 data bit, LSB-first
    for i in range(8):
        rx_signal.value = (byte_val >> i) & 1
        for _ in range(clocks_per_baud):
            await RisingEdge(clk)

    # hu: stop bit (idle)
    rx_signal.value = 1
    for _ in range(clocks_per_baud):
        await RisingEdge(clk)


async def uart_tx_bytes(dut, rx_signal, clocks_per_baud, data):
    """hu: Byte-sorozat küldése egymás után a DUT rx_signal bemenetére."""
    for b in data:
        await uart_tx_byte(dut, rx_signal, clocks_per_baud, b & 0xFF)


async def uart_rx_byte(dut, tx_signal, clocks_per_baud):
    """hu: Egyetlen 8N1 byte dekódolása a `tx_signal`-ról. Vár a start bitre
        (magas → alacsony átmenet), a közepén mintavételez, majd 8 data bit
        után a stop bit-et ellenőrzi.
    en: Decode a single 8N1 byte from `tx_signal`. Waits for the start bit
        (high → low edge), samples mid-bit, then verifies the stop bit after
        8 data bits."""

    # hu: Vár a start élre (TX 1 → 0).
    # en: Wait for the start edge (TX 1 → 0).
    while int(tx_signal.value) == 1:
        await RisingEdge(dut.i_clk_50m if hasattr(dut, "i_clk_50m") else dut.clk)

    half_baud = clocks_per_baud // 2

    # hu: Start bit közepe — itt kell „1.5 baud"-ot várni az első data bit
    #     közepéig. Egyszerűbb: half + full baud.
    # en: Middle of start bit — need 1.5 baud delays to reach the middle of
    #     the first data bit. Simpler: half + full baud.
    for _ in range(half_baud):
        await RisingEdge(dut.i_clk_50m if hasattr(dut, "i_clk_50m") else dut.clk)

    if int(tx_signal.value) != 0:
        raise AssertionError("UART start bit not low at mid-sample")

    # hu: 8 data bit, LSB-first, mintavétel a bit közepén
    # en: 8 data bits, LSB-first, sampled mid-bit
    byte_val = 0
    for i in range(8):
        for _ in range(clocks_per_baud):
            await RisingEdge(dut.i_clk_50m if hasattr(dut, "i_clk_50m") else dut.clk)
        bit = int(tx_signal.value) & 1
        byte_val |= (bit << i)

    # hu: Stop bit közepe → ellenőrizzük, hogy a TX magas
    # en: Mid-stop bit → verify TX is high
    for _ in range(clocks_per_baud):
        await RisingEdge(dut.i_clk_50m if hasattr(dut, "i_clk_50m") else dut.clk)

    if int(tx_signal.value) != 1:
        raise AssertionError(
            f"UART stop bit not high (got {int(tx_signal.value)}) for byte 0x{byte_val:02X}"
        )

    return byte_val


async def uart_rx_string(dut, tx_signal, clocks_per_baud, terminator=ord('\n'),
                         max_bytes=16):
    """hu: Folyamatosan dekódol byte-okat, amíg a `terminator`-t meg nem kapja
        vagy `max_bytes`-ot el nem érünk.
    en: Decodes bytes continuously until `terminator` is received or
        `max_bytes` are reached."""
    out = bytearray()
    for _ in range(max_bytes):
        b = await uart_rx_byte(dut, tx_signal, clocks_per_baud)
        out.append(b)
        if b == terminator:
            break
    return bytes(out)
