namespace CilCpu.Linker;

/// <summary>
/// hu: Az ISA szint, amelyre a linker fordít. Meghatározza mely
/// opkódokat fogadja el.
/// <br />
/// en: The ISA level the linker targets. Determines which opcodes
/// are accepted.
/// </summary>
public enum TIsaLevel
{
    /// <summary>
    /// hu: CIL-T0 — 48 opkód, int32-only, no arrays, no objects.
    /// <br />
    /// en: CIL-T0 — 48 opcodes, int32-only, no arrays, no objects.
    /// </summary>
    CilT0,

    /// <summary>
    /// hu: CIL-Seal — CIL-T0 + tömb opkódok + [CryptoCall] external dispatch.
    /// <br />
    /// en: CIL-Seal — CIL-T0 + array opcodes + [CryptoCall] external dispatch.
    /// </summary>
    CilSeal
}
