using CilCpu.Linker;
using CilCpu.Sim;

namespace CilCpu.Sim.Runner;

/// <summary>
/// hu: A CLI-CPU Runner core logikája — tesztelhető, konzol-független
/// osztály, amely .t0 bináris fájlokat futtat a TCpuNano szimulátoron,
/// és .NET assembly-ket (.dll) linkel CIL-T0 formátumra.
/// <br />
/// en: CLI-CPU Runner core logic — testable, console-independent
/// class that runs .t0 binary files on the TCpuNano simulator and
/// links .NET assemblies (.dll) to CIL-T0 format.
/// </summary>
public static class TRunner
{
    /// <summary>
    /// hu: Egy CIL-T0 bináris program futtatása a megadott entry RVA-ról.
    /// <br />
    /// en: Runs a CIL-T0 binary program from the given entry RVA.
    /// </summary>
    /// <param name="AProgram">
    /// hu: A CIL-T0 bináris byte-tömb.
    /// <br />
    /// en: The CIL-T0 binary byte array.
    /// </param>
    /// <param name="AEntryRva">
    /// hu: A belépési metódus header offszetje.
    /// <br />
    /// en: The entry method header offset.
    /// </param>
    /// <param name="AArgs">
    /// hu: Opcionális argumentumok a belépési metódusnak.
    /// <br />
    /// en: Optional arguments for the entry method.
    /// </param>
    public static TRunResult RunBinary(byte[] AProgram, int AEntryRva, int[]? AArgs = null)
    {
        ArgumentNullException.ThrowIfNull(AProgram);

        if (AProgram.Length == 0)
            throw new ArgumentException("Program cannot be empty.", nameof(AProgram));

        var cpu = new TCpuNano();

        try
        {
            cpu.Execute(AProgram, AEntryRva, AArgs);

            var tos = cpu.StackDepth > 0 ? cpu.Peek(0) : (int?)null;

            return new TRunResult(tos, null, null);
        }
        catch (TTrapException ex)
        {
            return new TRunResult(null, ex.Reason, ex.Message);
        }
    }

    /// <summary>
    /// hu: Egy CIL-T0 bináris program futtatása fájlból.
    /// <br />
    /// en: Runs a CIL-T0 binary program from a file.
    /// </summary>
    /// <param name="AFilePath">
    /// hu: A .t0 fájl elérési útja.
    /// <br />
    /// en: Path to the .t0 file.
    /// </param>
    /// <param name="AEntryRva">
    /// hu: A belépési metódus header offszetje.
    /// <br />
    /// en: The entry method header offset.
    /// </param>
    /// <param name="AArgs">
    /// hu: Opcionális argumentumok.
    /// <br />
    /// en: Optional arguments.
    /// </param>
    public static TRunResult RunFile(string AFilePath, int AEntryRva = 0, int[]? AArgs = null)
    {
        if (!File.Exists(AFilePath))
            throw new FileNotFoundException($"CIL-T0 binary file not found: {AFilePath}", AFilePath);

        var programBytes = File.ReadAllBytes(AFilePath);

        return RunBinary(programBytes, AEntryRva, AArgs);
    }

    /// <summary>
    /// hu: Egy .NET assembly (.dll) byte-tömb linkelése CIL-T0 binárisra.
    /// A TCliCpuLinker.Link() wrapper-e, amely a Runner API konzisztenciáját
    /// biztosítja.
    /// <br />
    /// en: Links a .NET assembly (.dll) byte array to CIL-T0 binary format.
    /// A wrapper around TCliCpuLinker.Link() for Runner API consistency.
    /// </summary>
    /// <param name="ADllBytes">
    /// hu: A .NET assembly byte-tömb.
    /// <br />
    /// en: The .NET assembly byte array.
    /// </param>
    /// <param name="AClassName">
    /// hu: A belépési osztály neve.
    /// <br />
    /// en: The entry class name.
    /// </param>
    /// <param name="AMethodName">
    /// hu: A belépési metódus neve.
    /// <br />
    /// en: The entry method name.
    /// </param>
    public static byte[] LinkDll(byte[] ADllBytes, string AClassName, string AMethodName)
    {
        ArgumentNullException.ThrowIfNull(ADllBytes);
        ArgumentNullException.ThrowIfNull(AClassName);
        ArgumentNullException.ThrowIfNull(AMethodName);

        return TCliCpuLinker.Link(ADllBytes, AClassName, AMethodName);
    }
}
