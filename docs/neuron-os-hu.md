# Neuron OS

> **📦 A Neuron OS vízió dokumentuma átköltözött a saját repójába.**
>
> **Új hely:** [`FenySoft/NeuronOS/docs/vision-hu.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md)

> English version: [neuron-os-en.md](neuron-os-en.md)

> Version: 2.0 (2026-04-17 — stub, csak átirányításra)

## Mi ez?

A **Neuron OS** a **Cognitive Fabric Processing Unit (CFPU)** aktor-alapú operációs rendszere. Korábban ebben a repóban tartottuk a teljes vízió dokumentumot (`docs/neuron-os-hu.md`, ~1000 sor), de a Neuron OS implementációja saját repót kapott ([`FenySoft/NeuronOS`](https://github.com/FenySoft/NeuronOS)) — és ahhoz tartozóan a **vízió is átköltözött** oda.

Ez a fájl csak azért marad itt, hogy a régi belső és külső linkek ne törjenek el.

## Hol van most a tartalom?

| Korábbi hivatkozás | Új hely |
|--------------------|---------|
| Teljes vízió, filozófia, tervezési alapelvek | [`vision-hu.md`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md) |
| Capability-alapú biztonság (377-413. sor) | [`vision-hu.md#capability-alapú-biztonság`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#capability-alapú-biztonság) |
| A capability fogalma (388-398. sor) | [`vision-hu.md#a-capability-fogalma`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#a-capability-fogalma) |
| Per-core privát GC (366-369. sor) | [`vision-hu.md#per-core-privát-gc`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#per-core-privát-gc) |
| Kernel aktorok (244. sor, `hot_code_loader`) | [`vision-hu.md#kernel-aktorok-root-level`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#kernel-aktorok-root-level) |
| Aktor `Start` (278. sor, cooperative multitasking) | [`vision-hu.md#2-start`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#2-start) |
| Új aktor dinamikusan indítása (434. sor) | [`vision-hu.md#új-aktor-dinamikusan-indítása`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#új-aktor-dinamikusan-indítása) |
| F4 multi-core scheduler + router (617-624. sor) | [`vision-hu.md#f4--multi-core-scheduler--router`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#f4--multi-core-scheduler--router) |
| "Nem monolit kernel" döntés (731. sor) | [`vision-hu.md#2-nem-monolit-kernel--helyette-aktor-hierarchia`](https://github.com/FenySoft/NeuronOS/blob/main/docs/vision-hu.md#2-nem-monolit-kernel--helyette-aktor-hierarchia) |

## Miért külön repó?

Három ok:

1. **Eltérő fejlesztői közönség** — egy .NET fejlesztőnek ne kelljen Verilog-ot, cocotb-t vagy Yosys scripteket olvasnia ahhoz, hogy aktor runtime-hoz hozzájáruljon.
2. **Független életciklus** — a Neuron OS bármely CIL hoszton fut ma; nem blokkol a szilícium elkészültén.
3. **Tiszta licenszek** — Apache-2.0 (NeuronOS) illeszkedik a .NET ökoszisztémához; CERN-OHL-S (CLI-CPU) a hardver design-okhoz megfelelő.

## OS → HW visszacsatolás

Ha a Neuron OS fejlesztése közben hardveres követelmény merül fel (`osreq`), a menetét a [`FenySoft/NeuronOS/docs/osreq-to-cfpu/`](https://github.com/FenySoft/NeuronOS/tree/main/docs/osreq-to-cfpu) követi nyomon, CLI-CPU oldalon pedig az `osreq-from-os` címkéjű issue-kként.
