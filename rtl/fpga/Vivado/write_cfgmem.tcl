# hu: CLI-CPU F2.7 Sub5 — Vivado write_cfgmem flow.
#     A `.bit` bitstream + a CIL-T0 alkalmazás-bináris (`.t0`) egyetlen
#     `.mcs` config image-be az IS25L128F (128 Mbit = 16 MB) QSPI flash-re.
# en: CLI-CPU F2.7 Sub5 — Vivado write_cfgmem flow.
#     Combines the `.bit` bitstream + the CIL-T0 application binary
#     (`.t0`) into one `.mcs` config image for the IS25L128F
#     (128 Mbit = 16 MB) QSPI flash.
#
# Használat / Usage:
#   vivado -mode batch -source write_cfgmem.tcl -tclargs /path/to/app.t0
#
# -----------------------------------------------------------------------
# FLASH OFFSET PARITÁS (sim <-> hardver) — Sub5.A-ban MEGOLDVA
# FLASH OFFSET PARITY (sim <-> hardware) — RESOLVED in Sub5.A
# -----------------------------------------------------------------------
# hu: A `cilcpu_qspi_controller` a CODE szegmenst (cpu_addr[23:20] = 0x0)
#     a flash `CODE_BASE_OFFSET + {4'h0, cpu_addr[19:0]}` címére fordítja.
#     A `CODE_BASE_OFFSET` paraméterezhető generic (Sub5.A):
#       - SIM: default 0 → a cocotb `TQSPIFlashModel` a `.t0[i]`-t az `i`
#         flash-címre teszi (offszet 0), bit-azonos sim-paritás.
#       - FPGA: a Vivado `create_project.tcl` `set_property generic`
#         CODE_BASE_OFFSET=32'hC00000-ra állítja (12 MB), a ~9,9 MB
#         XC7A200T bitstream FÖLÉ. A config-flash a `.bit`-et 0x0-tól
#         tölti (SPIx4 master config), az app a bitstream fölött, NINCS
#         ütközés. Forrás: rtl/src/cilcpu_qspi_controller.v ST_IDLE
#         `SEG_CODE` ág (CODE_BASE_OFFSET generic).
#
#     >>> EGYETLEN FORRÁS / SINGLE SOURCE: az alábbi CODE_BASE_OFFSET_HEX
#     konstans = a create_project.tcl-beli CODE_BASE_OFFSET generic. A
#     kettő MINDIG egyezzen — a `.t0` PONTOSAN erre az offszetre kerül a
#     `.mcs`-ben, hogy a core a flash-en ott találja, ahol az RTL keresi.
#     BOOT_PC = 0x08 (8-byte method header után), a CODE-ablakon belül.
# en: The `cilcpu_qspi_controller` maps the CODE segment
#     (cpu_addr[23:20] = 0x0) to flash address
#     `CODE_BASE_OFFSET + {4'h0, cpu_addr[19:0]}`. `CODE_BASE_OFFSET` is
#     a parameterizable generic (Sub5.A):
#       - SIM: default 0 → cocotb `TQSPIFlashModel` stores `.t0[i]` at
#         flash address `i`, bit-identical sim parity.
#       - FPGA: Vivado `create_project.tcl` `set_property generic` sets
#         CODE_BASE_OFFSET=32'hC00000 (12 MB), ABOVE the ~9.9 MB
#         XC7A200T bitstream. The config-flash loads `.bit` from 0x0
#         (SPIx4 master config); the app sits above it, NO collision.
#     >>> SINGLE SOURCE: the CODE_BASE_OFFSET_HEX constant below = the
#     CODE_BASE_OFFSET generic in create_project.tcl. The two must
#     ALWAYS match — the `.t0` is embedded at EXACTLY this offset in the
#     `.mcs` so the core finds it on flash where the RTL looks.
# -----------------------------------------------------------------------

# hu: EZ AZ EGYETLEN FORRÁS — egyezzen a create_project.tcl
#     CODE_BASE_OFFSET=32'hC00000 generic-jével.
# en: THE SINGLE SOURCE — must match the create_project.tcl
#     CODE_BASE_OFFSET=32'hC00000 generic.
set CODE_BASE_OFFSET_HEX "0x00C00000"

if {$argc < 1} {
    error "ERROR: használat: write_cfgmem.tcl -tclargs <app.t0> \[app_offset_hex\]"
}

set app_bin   [lindex $argv 0]
# hu: APP_OFFSET default = CODE_BASE_OFFSET_HEX (0x00C00000) — a
#     create_project.tcl CODE_BASE_OFFSET generic-jével egyező egyetlen
#     forrás. Felülírható 2. arggal (pl. egyedi RTL-offszet teszteléshez),
#     de akkor a generic-et IS ugyanarra kell állítani.
# en: APP_OFFSET default = CODE_BASE_OFFSET_HEX (0x00C00000) — single
#     source matching the create_project.tcl CODE_BASE_OFFSET generic.
#     Override via 2nd arg (e.g. testing a custom RTL offset), but then
#     the generic MUST be set to the same value.
set app_offset $CODE_BASE_OFFSET_HEX
if {$argc >= 2} {
    set app_offset [lindex $argv 1]
}

set project_dir [file dirname [file normalize [info script]]]
set build_dir   "$project_dir/build"
set top_module  "cilcpu_a7lite_board"
set bitfile     "$build_dir/cilcpu_a7lite.runs/impl_1/$top_module.bit"
set mcsfile     "$build_dir/cilcpu_a7lite.mcs"

if {![file exists $bitfile]} {
    error "ERROR: bitstream nincs meg: $bitfile (futtasd elobb a create_project.tcl-t)"
}
if {![file exists $app_bin]} {
    error "ERROR: app binaris nincs meg: $app_bin"
}

puts "INFO: bitstream  = $bitfile"
puts "INFO: app .t0    = $app_bin"
puts "INFO: app offset = $app_offset (CODE_BASE_OFFSET generic-kel egyezzen)"

# hu: IS25L128F = 128 Mbit = 16 MB; SPIx4 interfész (a XDC-vel egyezően:
#     BITSTREAM.CONFIG.SPI_BUSWIDTH 4). A bitstream loadaddr 0.
#     A `.t0` adatfájl a megadott offszetre, `up` byte-sorrenddel.
# en: IS25L128F = 128 Mbit = 16 MB; SPIx4 (matches the XDC
#     BITSTREAM.CONFIG.SPI_BUSWIDTH 4). Bitstream loadaddr 0.
#     The `.t0` data file at the given offset, `up` byte order.
write_cfgmem -format mcs -interface SPIx4 -size 16 \
    -loadbit "up 0x00000000 $bitfile" \
    -loaddata "up $app_offset $app_bin" \
    -file $mcsfile -force

puts ""
puts "=========================================================="
puts "INFO: cfgmem KESZ: $mcsfile"
puts "INFO: SPIx4, 16 MB (IS25L128F), bitstream\@0x0, app\@$app_offset"
puts ""
puts "Programozas (Hardware Manager) / Programming:"
puts "  add_configuration_memory_part is25lp128f-... \[lindex...\]"
puts "  program_hw_cfgmem  (lasd README-hu.md Sub5 runbook)"
puts "=========================================================="
