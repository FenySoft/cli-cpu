namespace CilCpu.Sim.Runner;

/// <summary>
/// hu: A CilCpu.Sim.Runner CLI belépési pont — CIL-T0 bináris fájlok
/// és C# forráskódok futtatása a TCpu szimulátoron.
/// <br />
/// en: CilCpu.Sim.Runner CLI entry point — runs CIL-T0 binary files
/// and C# source code on the TCpu simulator.
/// </summary>
public static class Program
{
    /// <summary>
    /// hu: CLI belépési pont. Támogatott parancsok:
    ///   run &lt;file.t0&gt; [--entry &lt;rva&gt;] [--args &lt;a1,a2,...&gt;]
    ///   link &lt;file.dll&gt; --class &lt;name&gt; --method &lt;name&gt; -o &lt;output.t0&gt;
    /// <br />
    /// en: CLI entry point. Supported commands:
    ///   run &lt;file.t0&gt; [--entry &lt;rva&gt;] [--args &lt;a1,a2,...&gt;]
    ///   link &lt;file.dll&gt; --class &lt;name&gt; --method &lt;name&gt; -o &lt;output.t0&gt;
    /// </summary>
    /// <param name="AArgs">
    /// hu: Parancssori argumentumok.
    /// <br />
    /// en: Command-line arguments.
    /// </param>
    public static int Main(string[] AArgs)
    {
        if (AArgs.Length == 0)
        {
            PrintUsage();
            return 1;
        }

        var command = AArgs[0].ToLowerInvariant();

        if (command == "run")
            return HandleRun(AArgs);

        if (command == "link")
            return HandleLink(AArgs);

        PrintUsage();
        return 1;
    }

    /// <summary>
    /// hu: A 'run' parancs kezelése — .t0 fájl betöltése és futtatása.
    /// <br />
    /// en: Handles the 'run' command — loads and runs a .t0 file.
    /// </summary>
    private static int HandleRun(string[] AArgs)
    {
        if (AArgs.Length < 2)
        {
            Console.Error.WriteLine("Error: 'run' requires a file path.");
            PrintUsage();
            return 1;
        }

        var filePath = AArgs[1];
        var entryRva = 0;
        int[]? args = null;

        try
        {
            for (var i = 2; i < AArgs.Length; i++)
            {
                if (AArgs[i] == "--entry" && i + 1 < AArgs.Length)
                {
                    entryRva = int.Parse(AArgs[i + 1]);
                    i++;
                }
                else if (AArgs[i] == "--args" && i + 1 < AArgs.Length)
                {
                    args = ParseIntArray(AArgs[i + 1]);
                    i++;
                }
            }

            var result = TRunner.RunFile(filePath, entryRva, args);

            if (result.Trapped)
            {
                Console.Error.WriteLine($"Trap: {result.TrapReason} — {result.TrapMessage}");
                return 2;
            }

            Console.WriteLine(result.Result?.ToString() ?? "(no result)");
            return 0;
        }
        catch (FileNotFoundException ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
            return 1;
        }
        catch (FormatException ex)
        {
            Console.Error.WriteLine($"Error: Invalid argument format — {ex.Message}");
            return 1;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
            return 1;
        }
    }

    /// <summary>
    /// hu: A 'link' parancs kezelése — .dll assembly linkelése .t0 binárisra.
    /// <br />
    /// en: Handles the 'link' command — links a .dll assembly to .t0 binary.
    /// </summary>
    private static int HandleLink(string[] AArgs)
    {
        if (AArgs.Length < 2)
        {
            Console.Error.WriteLine("Error: 'link' requires a file path.");
            PrintUsage();
            return 1;
        }

        var dllPath = AArgs[1];
        string? className = null;
        string? methodName = null;
        string? outputPath = null;

        for (var i = 2; i < AArgs.Length; i++)
        {
            if (AArgs[i] == "--class" && i + 1 < AArgs.Length)
            {
                className = AArgs[i + 1];
                i++;
            }
            else if (AArgs[i] == "--method" && i + 1 < AArgs.Length)
            {
                methodName = AArgs[i + 1];
                i++;
            }
            else if (AArgs[i] == "-o" && i + 1 < AArgs.Length)
            {
                outputPath = AArgs[i + 1];
                i++;
            }
        }

        if (className is null)
        {
            Console.Error.WriteLine("Error: --class is required.");
            return 1;
        }

        if (methodName is null)
        {
            Console.Error.WriteLine("Error: --method is required.");
            return 1;
        }

        if (outputPath is null)
        {
            Console.Error.WriteLine("Error: -o output path is required.");
            return 1;
        }

        try
        {
            var dllBytes = File.ReadAllBytes(dllPath);
            var t0Bytes = TRunner.LinkDll(dllBytes, className, methodName);
            File.WriteAllBytes(outputPath, t0Bytes);
            Console.WriteLine($"Linked: {outputPath}");
            return 0;
        }
        catch (FileNotFoundException ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
            return 1;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
            return 1;
        }
    }

    /// <summary>
    /// hu: Vesszővel elválasztott egész számok parse-olása int[]-re.
    /// <br />
    /// en: Parses comma-separated integers into an int array.
    /// </summary>
    private static int[] ParseIntArray(string AValue)
    {
        return AValue
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(int.Parse)
            .ToArray();
    }

    /// <summary>
    /// hu: Használati útmutató kiírása a standard kimenetre.
    /// <br />
    /// en: Prints usage information to standard output.
    /// </summary>
    private static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  run <file.t0> [--entry <rva>] [--args <a1,a2,...>]");
        Console.WriteLine("  link <file.dll> --class <name> --method <name> -o <output.t0>");
    }
}
