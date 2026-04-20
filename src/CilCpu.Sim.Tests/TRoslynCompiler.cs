using System.Reflection;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;

namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: Teszt-segéd, amely egy C# forráskód string-et runtime-ban
/// lefordít egy memóriabeli .NET assembly byte-tömbbé. Ezt a linker
/// tesztek használják, hogy a Roslyn natív outputjából tudjanak
/// CIL-T0-ra fordítani, és onnan a TCpuNano szimulátor futtatni.
/// <br />
/// en: Test helper that compiles a C# source string at runtime to an
/// in-memory .NET assembly byte array. Used by linker tests to drive
/// the Roslyn-native output through the linker into the TCpuNano simulator.
/// </summary>
public static class TRoslynCompiler
{
    /// <summary>
    /// hu: Egy C# forráskódot lefordít egy classlib assembly-vé,
    /// és visszaadja a .dll byte-jait. Release config, optimization
    /// bekapcsolva, hogy a Roslyn output minimális és determinisztikus
    /// legyen.
    /// <br />
    /// en: Compiles a C# source string into a class library assembly
    /// and returns the .dll bytes. Release config, optimization on,
    /// for minimal and deterministic Roslyn output.
    /// </summary>
    /// <param name="ASource">
    /// hu: A fordítandó C# forráskód.
    /// <br />
    /// en: The C# source code to compile.
    /// </param>
    public static byte[] CompileToBytes(string ASource)
    {
        var syntaxTree = CSharpSyntaxTree.ParseText(ASource);

        // Alapvető referencia a .NET 10 BCL felé
        var trustedAssembliesPaths = ((string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")!)
            .Split(Path.PathSeparator);

        var references = trustedAssembliesPaths
            .Where(p => Path.GetFileName(p) is "System.Runtime.dll" or "System.Private.CoreLib.dll")
            .Select(p => MetadataReference.CreateFromFile(p))
            .Cast<MetadataReference>()
            .ToList();

        var compilation = CSharpCompilation.Create(
            assemblyName: "TestAssembly",
            syntaxTrees: [syntaxTree],
            references: references,
            options: new CSharpCompilationOptions(
                OutputKind.DynamicallyLinkedLibrary,
                optimizationLevel: OptimizationLevel.Release));

        using var ms = new MemoryStream();
        var result = compilation.Emit(ms);

        if (!result.Success)
        {
            var errors = string.Join("\n", result.Diagnostics
                .Where(d => d.Severity == DiagnosticSeverity.Error)
                .Select(d => d.ToString()));
            throw new InvalidOperationException($"Roslyn compilation failed:\n{errors}");
        }

        return ms.ToArray();
    }
}
