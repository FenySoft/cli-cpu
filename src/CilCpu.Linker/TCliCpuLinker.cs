using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;

namespace CilCpu.Linker;

/// <summary>
/// hu: A CIL-CPU linker tool — a Roslyn által generált .NET assembly
/// (.dll) byte-tömböt CIL-T0 kompatibilis bináris formátumba alakítja,
/// amelyet a TCpuNano szimulátor (vagy az F2 RTL hardver) közvetlenül
/// futtatni tud. A tool: tranzitív call-target discovery-t végez,
/// metaadat tokeneket abszolút RVA-kká old fel, CIL-T0 metódus
/// header-eket generál, és ellenőrzi az opkód-készlet kompatibilitást.
/// <br />
/// en: The CLI-CPU linker tool — converts a Roslyn-generated .NET
/// assembly (.dll) byte array into a CIL-T0 compatible binary format
/// directly executable by the TCpuNano simulator (or F2 RTL hardware).
/// The tool performs transitive call-target discovery, resolves
/// metadata tokens to absolute RVAs, generates CIL-T0 method headers,
/// and verifies opcode set compatibility.
/// </summary>
public static class TCliCpuLinker
{
    private const byte MethodHeaderMagic = 0xFE;
    private const int MethodHeaderSize = 8;

    /// <summary>
    /// hu: Egy assembly byte-tömböt CIL-T0 bináris formátumra fordít.
    /// Az entry metódusból tranzitívan felfedezi a hívott metódusokat,
    /// layout-olja őket, és feloldja a call tokeneket.
    /// <br />
    /// en: Translates an assembly byte array to CIL-T0 binary format.
    /// Transitively discovers called methods from the entry point,
    /// lays them out, and resolves call tokens.
    /// </summary>
    public static byte[] Link(byte[] AAssemblyBytes, string AClassName, string AEntryMethodName)
    {
        ArgumentNullException.ThrowIfNull(AAssemblyBytes);
        ArgumentNullException.ThrowIfNull(AClassName);
        ArgumentNullException.ThrowIfNull(AEntryMethodName);

        using var stream = new MemoryStream(AAssemblyBytes);
        using var peReader = new PEReader(stream);
        var metadata = peReader.GetMetadataReader();

        var entryHandle = FindMethod(metadata, AClassName, AEntryMethodName);

        if (entryHandle.IsNil)
            throw new TCilT0LinkException(
                $"Method '{AClassName}.{AEntryMethodName}' not found in assembly.");

        // hu: 1. Tranzitív call-target discovery — az entry metódusból
        // kiindulva rekurzívan felfedezi az összes hívott metódust.
        // en: 1. Transitive call-target discovery — recursively discovers
        // all methods called from the entry point.
        var methodOrder = new List<MethodDefinitionHandle>();
        var methodSet = new HashSet<MethodDefinitionHandle>();
        DiscoverMethods(metadata, peReader, entryHandle, methodOrder, methodSet);

        // hu: 2. Layout — kiszámítjuk minden metódus header RVA-ját.
        // en: 2. Layout — compute header RVA for each method.
        var methodIL = new Dictionary<MethodDefinitionHandle, byte[]>();
        var methodRva = new Dictionary<MethodDefinitionHandle, int>();
        var offset = 0;

        foreach (var handle in methodOrder)
        {
            var mdef = metadata.GetMethodDefinition(handle);
            var il = ReadMethodIL(peReader, mdef);
            methodIL[handle] = il;
            methodRva[handle] = offset;
            offset += MethodHeaderSize + il.Length;
        }

        // hu: 3. Call token feloldás + output generálás.
        // en: 3. Call token resolution + output generation.
        var output = new byte[offset];

        foreach (var handle in methodOrder)
        {
            var mdef = metadata.GetMethodDefinition(handle);
            var il = methodIL[handle];
            var rva = methodRva[handle];
            var argCount = CountParameters(mdef);
            var localCount = CountLocals(metadata, peReader, mdef);

            // hu: Token feloldás — a call operandusokat az abszolút RVA-kra írjuk.
            // en: Token resolution — rewrite call operands to absolute RVAs.
            var linkedIl = ResolveCallTokens(il, methodRva);

            WriteMethodHeader(output, rva, argCount, localCount, AMaxStack: 8, ACodeSize: linkedIl.Length);
            Array.Copy(linkedIl, 0, output, rva + MethodHeaderSize, linkedIl.Length);
        }

        return output;
    }

    /// <summary>
    /// hu: Rekurzívan felfedezi az összes tranzitív call target-et
    /// az entry metódusból kiindulva.
    /// <br />
    /// en: Recursively discovers all transitive call targets starting
    /// from the entry method.
    /// </summary>
    private static void DiscoverMethods(
        MetadataReader AMetadata,
        PEReader APeReader,
        MethodDefinitionHandle AHandle,
        List<MethodDefinitionHandle> AOrder,
        HashSet<MethodDefinitionHandle> AVisited)
    {
        if (!AVisited.Add(AHandle))
            return;

        AOrder.Add(AHandle);

        var mdef = AMetadata.GetMethodDefinition(AHandle);
        var il = ReadMethodIL(APeReader, mdef);
        var pc = 0;

        while (pc < il.Length)
        {
            var opcode = il[pc];
            var length = OpcodeLength(opcode, il, pc);

            if (opcode == 0x28) // call
            {
                var token = ReadUInt32LE(il, pc + 1);
                var tableType = (token >> 24) & 0xFF;
                var rowIndex = (int)(token & 0x00FFFFFF);

                if (tableType == 0x06) // MethodDef
                {
                    var targetHandle = MetadataTokens.MethodDefinitionHandle(rowIndex);
                    DiscoverMethods(AMetadata, APeReader, targetHandle, AOrder, AVisited);
                }
            }

            pc += length;
        }
    }

    /// <summary>
    /// hu: Végigjárja az IL byte-okat, és minden 'call' opkód
    /// operandusát átírja a target metódus abszolút RVA-jára.
    /// <br />
    /// en: Walks the IL bytes and rewrites every 'call' opcode operand
    /// to the target method's absolute RVA.
    /// </summary>
    internal static byte[] ResolveCallTokens(
        byte[] AIlBytes,
        Dictionary<MethodDefinitionHandle, int> AMethodRva)
    {
        var output = (byte[])AIlBytes.Clone();
        var pc = 0;

        while (pc < output.Length)
        {
            var opcode = output[pc];
            var length = OpcodeLength(opcode, output, pc);

            if (opcode == 0x28) // call
            {
                var token = ReadUInt32LE(output, pc + 1);
                var tableType = (token >> 24) & 0xFF;
                var rowIndex = (int)(token & 0x00FFFFFF);

                if (tableType != 0x06)
                    throw new TCilT0LinkException(
                        $"Unsupported call target table 0x{tableType:X2} at IL offset 0x{pc:X4}.");

                var targetHandle = MetadataTokens.MethodDefinitionHandle(rowIndex);

                if (!AMethodRva.TryGetValue(targetHandle, out var targetRva))
                    throw new TCilT0LinkException(
                        $"Call target MethodDef row {rowIndex} not found in linked methods at IL offset 0x{pc:X4}.");

                WriteUInt32LE(output, pc + 1, (uint)targetRva);
            }

            pc += length;
        }

        return output;
    }

    /// <summary>
    /// hu: A lokális változók számának kiolvasása a metódus body
    /// lokális signature-jéből.
    /// <br />
    /// en: Reads the local variable count from the method body's local
    /// signature.
    /// </summary>
    private static int CountLocals(
        MetadataReader AMetadata,
        PEReader APeReader,
        MethodDefinition AMethodDef)
    {
        var rva = AMethodDef.RelativeVirtualAddress;

        if (rva == 0)
            return 0;

        var bodyBlock = APeReader.GetMethodBody(rva);

        if (bodyBlock.LocalSignature.IsNil)
            return 0;

        var sig = AMetadata.GetStandaloneSignature(bodyBlock.LocalSignature);
        var reader = AMetadata.GetBlobReader(sig.Signature);

        // hu: A LOCAL_SIG formátum: prolog (0x07) + compressed local count + típus-leírók.
        // en: LOCAL_SIG format: prolog (0x07) + compressed local count + type descriptors.
        var prolog = reader.ReadByte();

        if (prolog != 0x07)
            return 0;

        var localCount = reader.ReadCompressedInteger();
        return localCount;
    }

    private static MethodDefinitionHandle FindMethod(
        MetadataReader AMetadata,
        string AClassName,
        string AMethodName)
    {
        foreach (var typeHandle in AMetadata.TypeDefinitions)
        {
            var typeDef = AMetadata.GetTypeDefinition(typeHandle);
            var typeName = AMetadata.GetString(typeDef.Name);

            if (typeName != AClassName)
                continue;

            foreach (var methodHandle in typeDef.GetMethods())
            {
                var methodDef = AMetadata.GetMethodDefinition(methodHandle);
                var methodName = AMetadata.GetString(methodDef.Name);

                if (methodName == AMethodName)
                    return methodHandle;
            }
        }

        return default;
    }

    private static byte[] ReadMethodIL(PEReader APeReader, MethodDefinition AMethodDef)
    {
        var rva = AMethodDef.RelativeVirtualAddress;
        var bodyBlock = APeReader.GetMethodBody(rva);
        return bodyBlock.GetILBytes() ?? [];
    }

    private static int CountParameters(MethodDefinition AMethodDef) =>
        AMethodDef.GetParameters().Count;

    private static void WriteMethodHeader(
        byte[] AOutput,
        int AOffset,
        int AArgCount,
        int ALocalCount,
        int AMaxStack,
        int ACodeSize)
    {
        AOutput[AOffset + 0] = MethodHeaderMagic;
        AOutput[AOffset + 1] = (byte)AArgCount;
        AOutput[AOffset + 2] = (byte)ALocalCount;
        AOutput[AOffset + 3] = (byte)AMaxStack;
        AOutput[AOffset + 4] = (byte)(ACodeSize & 0xFF);
        AOutput[AOffset + 5] = (byte)((ACodeSize >> 8) & 0xFF);
        AOutput[AOffset + 6] = 0;
        AOutput[AOffset + 7] = 0;
    }

    private static uint ReadUInt32LE(byte[] ABytes, int AOffset) =>
        (uint)(ABytes[AOffset]
            | (ABytes[AOffset + 1] << 8)
            | (ABytes[AOffset + 2] << 16)
            | (ABytes[AOffset + 3] << 24));

    private static void WriteUInt32LE(byte[] ABytes, int AOffset, uint AValue)
    {
        ABytes[AOffset + 0] = (byte)(AValue & 0xFF);
        ABytes[AOffset + 1] = (byte)((AValue >> 8) & 0xFF);
        ABytes[AOffset + 2] = (byte)((AValue >> 16) & 0xFF);
        ABytes[AOffset + 3] = (byte)((AValue >> 24) & 0xFF);
    }

    /// <summary>
    /// hu: Egy CIL opkód teljes hosszának kiszámítása a CIL-T0 készletre.
    /// <br />
    /// en: Computes the full length of a CIL opcode for the CIL-T0 set.
    /// </summary>
    internal static int OpcodeLength(byte AOpcode, byte[] AProgram, int APc)
    {
        if (AOpcode == 0x00) return 1;
        if (AOpcode is >= 0x02 and <= 0x09) return 1;
        if (AOpcode is >= 0x0A and <= 0x0D) return 1;
        if (AOpcode is >= 0x14 and <= 0x1E) return 1;
        if (AOpcode == 0x25) return 1;
        if (AOpcode == 0x26) return 1;
        if (AOpcode == 0x2A) return 1;
        if (AOpcode is >= 0x58 and <= 0x66) return 1;
        if (AOpcode == 0x4A) return 1;
        if (AOpcode == 0x54) return 1;
        if (AOpcode == 0xDD) return 1;

        if (AOpcode == 0x0E) return 2;
        if (AOpcode == 0x10) return 2;
        if (AOpcode == 0x11) return 2;
        if (AOpcode == 0x13) return 2;
        if (AOpcode == 0x1F) return 2;
        if (AOpcode is >= 0x2B and <= 0x33) return 2;

        if (AOpcode == 0x20) return 5;
        if (AOpcode == 0x28) return 5;

        if (AOpcode == 0xFE)
        {
            if (APc + 1 >= AProgram.Length)
                throw new TCilT0LinkException(
                    $"Truncated 0xFE prefix opcode at IL offset 0x{APc:X4}.");

            var second = AProgram[APc + 1];

            if (second is >= 0x01 and <= 0x05)
                return 2;

            throw new TCilT0LinkException(
                $"Unsupported 0xFE-prefixed opcode 0xFE{second:X2} at IL offset 0x{APc:X4}.");
        }

        throw new TCilT0LinkException(
            $"Unsupported opcode 0x{AOpcode:X2} at IL offset 0x{APc:X4} — not in CIL-T0 set.");
    }
}
