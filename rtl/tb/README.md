# CLI-CPU cocotb testbenches

Verilog RTL verification with [cocotb](https://www.cocotb.org) on the Verilator backend.

> Magyar verzió: [README-hu.md](README-hu.md)

## Environment

| Component | Value |
|-----------|-------|
| Python | 3.13 (Homebrew, `/usr/local/bin/python3.13`) |
| venv | `rtl/.venv` (git-ignored) |
| Packages | `cocotb==2.0.1`, `find_libpython==0.5.1` |
| Simulator | Verilator |

Setting up the venv from scratch:

```bash
cd rtl
/usr/local/bin/python3.13 -m venv .venv
./.venv/bin/pip install cocotb==2.0.1 find_libpython==0.5.1
```

Install cocotb from the **binary wheel**. Building it from source on macOS
(`pip install --no-binary cocotb`) fails: `setup.py` passes both `-flto` and
`-bundle`, so `libgpilog.so` is produced as a Mach-O bundle that the linker
then refuses to link against (`ld: unsupported mach-o filetype`). Overriding
`LDFLAGS` does not help, because the hardcoded `-flto` comes last on the
command line.

## Running

Every target is a separate `make` goal; there is no aggregate target:

```bash
cd rtl/tb
make test_alu          # one target
make test_core         # ...
```

Each goal builds into its own `sim_build/<target>/` directory. `sim_build/` is
git-ignored.

Running the whole suite and collecting the results:

```bash
cd rtl/tb
for t in $(grep -E "^test_[a-z_0-9]+:" Makefile | sed 's/:.*//'); do
  make "$t" 2>&1 | grep -o "TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]* SKIP=[0-9]*" | tail -1
done
```

## Current suite size

**25 make goals, 324 test cases, all passing.** The goal count and the test
count are both measurable, so re-measure rather than trusting this line:

- goals: `grep -cE "^test_[a-z_0-9]+:" Makefile`
- test functions: `grep -c '^@cocotb.test' test_*.py` (322 — `test_qspi_controller_offset`
  re-runs two of them with a different parameter, hence 324 executed cases)

## Troubleshooting

**`Abort trap: 6` when the simulator starts, before any test runs.** The
`sim_build/<target>/Vtop` binary is stale: it links against the libraries of an
earlier cocotb or venv instance via its rpath. Remove or rename `sim_build/`;
the next `make` rebuilds it.

```bash
cd rtl/tb && rm -rf sim_build && make test_soc
```

Two things that look like the cause but are not:

- The line `Using Python 3.13.9 interpreter at .../.venv/bin/python3.13` is a
  build-time constant inside the cocotb wheel. It appears on passing runs too,
  regardless of the interpreter's real version.
- Parallelism. The failure reproduces with the targets run strictly one after
  another.
