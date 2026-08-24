# CLI-CPU cocotb testbench-ek

A Verilog RTL verifikációja [cocotb](https://www.cocotb.org)-bal, Verilator backenden.

> English version: [README.md](README.md)

## Környezet

| Komponens | Érték |
|-----------|-------|
| Python | 3.13 (Homebrew, `/usr/local/bin/python3.13`) |
| venv | `rtl/.venv` (git-ignorált) |
| Csomagok | `cocotb==2.0.1`, `find_libpython==0.5.1` |
| Szimulátor | Verilator |

A venv felállítása nulláról:

```bash
cd rtl
/usr/local/bin/python3.13 -m venv .venv
./.venv/bin/pip install cocotb==2.0.1 find_libpython==0.5.1
```

A cocotb a **bináris wheel-ből** telepítendő. Forrásból macOS-en
(`pip install --no-binary cocotb`) nem épül: a `setup.py` egyszerre ad
`-flto`-t és `-bundle`-t, így a `libgpilog.so` Mach-O bundle-ként áll elő,
amit a linker utána nem hajlandó könyvtárként linkelni
(`ld: unsupported mach-o filetype`). Az `LDFLAGS` felülírása nem segít, mert a
beégetett `-flto` a parancssor végén marad.

## Futtatás

Minden cél külön `make` goal, összesítő cél nincs:

```bash
cd rtl/tb
make test_alu          # egy cél
make test_core         # ...
```

Minden goal a saját `sim_build/<cél>/` könyvtárába épül. A `sim_build/`
git-ignorált.

A teljes készlet futtatása és az eredmények összegyűjtése:

```bash
cd rtl/tb
for t in $(grep -E "^test_[a-z_0-9]+:" Makefile | sed 's/:.*//'); do
  make "$t" 2>&1 | grep -o "TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]* SKIP=[0-9]*" | tail -1
done
```

## A készlet jelenlegi mérete

**25 make-cél, 324 teszteset, mind zöld.** A cél- és a tesztszám egyaránt
mérhető, ezért ezt a sort inkább mérd újra, mint hogy elhidd:

- célok: `grep -cE "^test_[a-z_0-9]+:" Makefile`
- tesztfüggvények: `grep -c '^@cocotb.test' test_*.py` (322 — a
  `test_qspi_controller_offset` közülük kettőt más paraméterrel újrafuttat,
  innen a 324 végrehajtott eset)

## Hibaelhárítás

**`Abort trap: 6` a szimulátor indulásakor, még mielőtt bármelyik teszt
elindulna.** A `sim_build/<cél>/Vtop` bináris elavult: az rpath-ján keresztül
egy korábbi cocotb- vagy venv-példány könyvtáraira linkel. Töröld vagy nevezd
át a `sim_build/`-et, a következő `make` újraépíti.

```bash
cd rtl/tb && rm -rf sim_build && make test_soc
```

Két dolog, ami oknak látszik, de nem az:

- A `Using Python 3.13.9 interpreter at .../.venv/bin/python3.13` sor a cocotb
  wheel-jébe épített fordítási idejű konstans. A zölden futó céloknál is
  megjelenik, függetlenül az interpreter valódi verziójától.
- A párhuzamosság. A hiba szigorúan sorosan futtatva is előjön.
