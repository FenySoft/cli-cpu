# TODO — halasztott taszkok

> Ez a fájl a roadmap-en kívül halasztott debug / bug-fix taszkokat tartja
> nyilván. Minden bejegyzéshez tartozik roadmap-sor és Vault-bejegyzés,
> hogy ne legyen "rejtett akna" a kódban.

---

## F2.7.D — Rekurzív CALL/RET root-frame teardown bug fix

- **Roadmap:** F2.7.D (~10 órás debug sprint), `docs/roadmap-hu.md`
- **Vault:** `project_recursive_call_bug`
- **Státusz:** ⬜ Tervezett
- **Felvéve:** 2026-05-12 (F2.7 Sub3 KÉSZ commit, `c81e3f2`)

### Tünet

A Roslyn-linkelt **rekurzív** `Math.Fibonacci` a wrapper boot-mintával
(caller frame nélkül, `boot_pc=8` közvetlenül a Fib body-tól)
`TRAP_STACK_UNDERFLOW`-val trap-el ~5 mélységnél.

### Mi működik (kontroll)

- `test_52_call_recursive_fib_5` hand-coded cocotb teszt (caller frame-mel): zöld
- `TCpuNano` C# szim Fib(10)=55: helyes ugyanazzal a binárissal
- Az iteratív Math.FibonacciIterative wrapper-rel: 1/1 PASS (Sub3)

### Gyanú

A `cilcpu_core.v` Sub5 frame manager **teardown logikája**, amikor a
"root frame"-et nem CALL hozta létre (wrapper boot directly into Fib body).

### Workaround a Sub3-ban

`Math.FibonacciIterative` (loop-os Fibonacci) — ugyanaz az eredmény,
LDLOC/STLOC/ADD/BLT_S/BR_S opkódfedéssel (mind 100% fedett).

### Debug sprint terv (~10 h)

1. Trace export rekurzív hívásnál (TCpuNanoTracer + cocotb trace mismatch)
2. Wrapper-rel azonos boot-séma a hand-coded tesztben → bug reprodukció
3. Frame manager FSM állapotok diff-je: CALL-by-CALL vs root-by-boot
4. Fix + golden vector regression
