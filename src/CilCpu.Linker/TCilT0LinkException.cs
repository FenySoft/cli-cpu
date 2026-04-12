namespace CilCpu.Linker;

/// <summary>
/// hu: A CIL-CPU linker tool kivételosztálya. Akkor dobódik, ha
/// a linker egy nem CIL-T0 kompatibilis konstrukciót talál a
/// bemeneti assembly-ben (pl. nem támogatott opkód, hiányzó
/// metódus, érvénytelen header).
/// <br />
/// en: Exception class for the CLI-CPU linker tool. Thrown when the
/// linker encounters a CIL-T0 incompatible construct in the input
/// assembly (e.g. unsupported opcode, missing method, invalid header).
/// </summary>
public sealed class TCilT0LinkException : Exception
{
    /// <summary>
    /// hu: Új linker kivétel az adott üzenettel.
    /// <br />
    /// en: New linker exception with the given message.
    /// </summary>
    /// <param name="AMessage">
    /// hu: A hibaüzenet.
    /// <br />
    /// en: The error message.
    /// </param>
    public TCilT0LinkException(string AMessage) : base(AMessage)
    {
    }
}
