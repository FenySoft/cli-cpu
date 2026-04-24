# LED blink — OpenXC7 build

> English version: [README.md](README.md)

Ugyanaz a `led_blink.v` mint a Vivado build-ben, csak **nyílt forráskódú toolchain**-en át: **Yosys + nextpnr-xilinx + Project X-Ray**. Célja megmutatni, hogy a CLI-CPU F2.7 smoke-tesztje nem Vivado-specifikus, és megalapozni az F4 körüli párhuzamos CI-t.

**Státusz (2026-04-24):** ✅ Sikeres build és programozás az A7-Lite 200T-re (`xc7a200tfbg484-2`). Bitstream: 9.3 MB, chipdb: 331 MB. Programozás openFPGALoader v1.1.1-gyel Vivado nélkül — LED-ek villognak.

## Fájlok

| Fájl | Szerep |
|------|--------|
| `led_blink.xdc` | Pin constraint OpenXC7 formában (nincs `-dict`, `LOC` / `IOSTANDARD` külön) |
| `Makefile` | Build pipeline: Yosys → nextpnr-xilinx → fasm2frames → xc7frames2bit |
| `build.sh` | WSL wrapper: PATH beállítás, S: drvfs mount, `make` indítás |

A `led_blink.v` **ugyanaz** mint a Vivado build-nél — egy szinttel feljebb (`../led_blink.v`) található.

## Követelmények

- **Ubuntu 22.04** (vagy kompatibilis) WSL2-ben
- **OpenXC7 snap package**: `wget -qO - https://raw.githubusercontent.com/openXC7/toolchain-installer/main/toolchain-installer.sh | bash`
  - Telepíti: `yosys`, `nextpnr-xilinx`, `bbasm`, `fasm2frames`, `xc7frames2bit`, `bit2fasm` → `/snap/bin/`
- **make**: `sudo apt install make`
- **python3** (chipdb generáláshoz; `pypy3` gyorsabb, de opcionális)

## Használat

WSL Ubuntu-ból (vagy WSL wrapperrel Windows CMD/PowerShell-ből):

```bash
# Teljes build
bash build.sh all

# Csak környezet ellenőrzés
bash build.sh check-env

# Takarítás
bash build.sh clean
```

Windows PowerShell-ből (külön mount-olás nélkül — a build.sh intézi):
```powershell
wsl -d Ubuntu-22.04 -- bash /mnt/s/github.com/FenySoft/CLI-CPU/rtl/fpga/smoke_test/OpenXC7/build.sh all
```

## Build pipeline fázisai

```
led_blink.v
    │
    ▼ [yosys synth_xilinx]
led_blink.json (post-synth netlist)
    │
    ▼ [nextpnr-xilinx --chipdb xxx.bin --xdc yyy.xdc]
led_blink.fasm (FPGA Assembly — szöveges)
    │
    ▼ [fasm2frames --part xx --db-root prjxray-db/artix7]
led_blink.frames (binary frames)
    │
    ▼ [xc7frames2bit --part_file part.yaml]
led_blink.bit (bitstream — feltölthető)
```

**Első build:** ~10–15 perc (a chipdb generálása miatt, ami ~5–10 perc a 200T-re pypy3-mal, ~15–25 perc python3-mal).
**Későbbi build-ek:** ~1–2 perc (chipdb már cache-elve van a `chipdb/` mappában).

## Eredmény összehasonlítás Vivado-val

A sikeres OpenXC7 build bizonyíték arra, hogy:
- A `led_blink.v` design **tool-független** — nem használ Vivado-specifikus primitiveket
- Az **XC7A200T teljes pipeline** (synth + P&R + bitstream) működik open source toolchain-nel
- Az F4 (Nano core, csak MMCM + UART) párhuzamos CI **technikailag kivitelezhető**

## Bitstream programozás

**Vivado Hardware Manager-rel** (a mi esetünkben ez a kényelmes):

A `led_blink.bit` ugyanúgy betölthető a Vivado GUI-val, mint az eredeti Vivado-generált bitstream. A bitstream formátum azonos.

**Open source alternatíva (`openFPGALoader` WSL-ből, verifikált 2026-04-24):**

Előfeltétel: **usbipd-win** USB passthrough, hogy a Windows host FTDI-ja elérhető legyen WSL-ben.

```powershell
# Windows admin PowerShell — egyszeri bind (telepítéskor):
winget install --interactive --exact dorssel.usbipd-win
& "C:\Program Files\usbipd-win\usbipd.exe" bind --busid <BUSID>
```

```powershell
# Windows normál PowerShell — attach WSL-hez (minden session-ben):
& "C:\Program Files\usbipd-win\usbipd.exe" attach --wsl --busid <BUSID>
```

```bash
# WSL — openFPGALoader build (egyszeri):
sudo apt install libftdi1-dev libhidapi-dev libusb-1.0-0-dev cmake build-essential git pkg-config libudev-dev zlib1g-dev
git clone https://github.com/trabucayre/openFPGALoader.git
cd openFPGALoader && mkdir build && cd build && cmake .. && make -j$(nproc) && sudo make install

# WSL — programozás (A7-Lite 200T-re):
sudo openFPGALoader --cable ft232 --fpga-part xc7a200tfbg484 --bitstream led_blink.bit
```

Az A7-Lite USB-JTAG-ja egy FTDI FT232H (VID:PID `0403:6014`). Az `--cable ft232` paraméter jó, a `--fpga-part xc7a200tfbg484` megmondja a pontos chipet.

**Megjegyzés:** mielőtt openFPGALoader-t futtatsz, **Vivado Hardware Manager-ből Disconnect**-áld a board-ot, hogy felszabadítsa a JTAG device-t. Ha a `usbipd attach` lefutott, a Windows-ból egyébként is „eltűnik" a device és csak WSL-ben elérhető.

## Ismert különbségek a Vivado build-hez képest

| Elem | Vivado | OpenXC7 |
|------|--------|---------|
| XDC szintaxis | `set_property -dict { PACKAGE_PIN X IOSTANDARD Y }` | `set_property LOC X [...]` + `set_property IOSTANDARD Y [...]` |
| Clock constraint | `create_clock -period 20.000` az XDC-ben | nextpnr auto-detekt (külön nem szükséges LED blink-hez) |
| Bitstream config | `CONFIG_VOLTAGE`, `CFGBVS`, `BITSTREAM.*` az XDC-ben | command-line argumentum `xc7frames2bit`-hez |
| Warning stílus | `[Synth 8-7080]`, `[Place 30-2953]` | Yosys + nextpnr natív stílus |
| Build idő (LED blink) | ~45 sec | ~15 perc (első, chipdb) / ~1 perc (cached) |
| Bitstream méret | ~1–2 MB (compressed) | 9.3 MB (uncompressed) |
| Timing report részletesség | Teljes WNS/TNS/WHS/THS | Slack szám, kevésbé részletes vizualizáció |

## Hibakeresés

**`make: command not found`** — `sudo apt install make`

**`yosys: command not found`** — A `/snap/bin` nincs a PATH-ban. A `build.sh` ezt kezeli. Ha saját kézből futtatod: `export PATH=/snap/bin:$PATH`

**`cannot access /mnt/s`** — Nem default mount WSL-ben. A `build.sh` futtatáskor automatikusan mount-olja. Kézzel: `sudo mount -t drvfs S: /mnt/s`

**`chipdb generation failed`** — pypy3 lenne ideális, python3 is megy. Ha pypy3-at akarsz: `sudo apt install pypy3`, aztán a `Makefile`-ban `PYTHON := pypy3`

**`libffi.so.7: cannot open shared object file`** — figyelmeztetés a `fasm2frames`-nél, nem hiba. Lassabb Python parser fallback használódik. Ha gyorsítani akarod: `pip install -v fasm` — de a LED blink tesztre nem szükséges.

**Sokkal hosszabb P&R mint várt** — Az XC7A200T nagy, az első P&R ~1–2 perc. Ha sokkal több, valami XDC hiba (pl. nem létező pin).
