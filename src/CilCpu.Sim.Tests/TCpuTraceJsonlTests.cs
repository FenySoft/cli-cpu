using System.Text;

namespace CilCpu.Sim.Tests;

/// <summary>
/// hu: A TCpuTraceJsonl serializer unit tesztjei. A JSONL (JSON Lines) formátum
/// 1 entry / sor — minden sor egy önálló <see cref="TCpuTraceEntry"/>-t kódol
/// kompakt formában. A formátum stabil kontraktum a cocotb harness és más
/// külső eszközök felé.
/// <br />
/// en: Unit tests for the TCpuTraceJsonl serializer. JSONL (JSON Lines) format
/// is 1 entry per line — each line encodes a single <see cref="TCpuTraceEntry"/>
/// compactly. The format is a stable contract toward the cocotb harness and
/// other external tools.
/// </summary>
public class TCpuTraceJsonlTests
{
    /// <summary>
    /// hu: Roundtrip — egy entry-listát JSONL-be sorosítunk, majd visszaolvassuk;
    /// minden mező értéke megőrződik.
    /// <br />
    /// en: Roundtrip — serialize a list of entries to JSONL, then parse back;
    /// every field value is preserved.
    /// </summary>
    [Fact]
    public void Roundtrip_PreservesAllFields()
    {
        var entries = new[]
        {
            new TCpuTraceEntry(
                Step: 0, Pc: 0, Sp: 12, Fp: 0,
                CallDepth: 1, ArgCount: 0, LocalCount: 0, EvalDepth: 0,
                Opcode: 0x1B, Operand: 0, LengthInBytes: 1),
            new TCpuTraceEntry(
                Step: 1, Pc: 1, Sp: 12, Fp: 0,
                CallDepth: 1, ArgCount: 0, LocalCount: 0, EvalDepth: 1,
                Opcode: 0x2A, Operand: 42, LengthInBytes: 2),
        };

        using var ms = new MemoryStream();
        TCpuTraceJsonl.WriteAll(ms, entries);
        ms.Position = 0;

        var parsed = TCpuTraceJsonl.ParseAll(ms);

        Assert.Equal(entries.Length, parsed.Count);
        for (var i = 0; i < entries.Length; i++)
            Assert.Equal(entries[i], parsed[i]);
    }

    /// <summary>
    /// hu: Üres bemenet esetén üres listát kapunk.
    /// <br />
    /// en: Empty input yields an empty list.
    /// </summary>
    [Fact]
    public void ParseAll_EmptyStream_ReturnsEmptyList()
    {
        using var ms = new MemoryStream();
        var parsed = TCpuTraceJsonl.ParseAll(ms);
        Assert.Empty(parsed);
    }

    /// <summary>
    /// hu: A formátum 1 entry/sor — minden sor önálló JSON objektum, az utolsó
    /// sort lezáró '\n' opcionális.
    /// <br />
    /// en: Format is 1 entry per line — each line is a self-contained JSON
    /// object; the trailing '\n' of the last line is optional.
    /// </summary>
    [Fact]
    public void WriteAll_OneEntryPerLine()
    {
        var entries = new[]
        {
            new TCpuTraceEntry(
                Step: 0, Pc: 0, Sp: 12, Fp: 0,
                CallDepth: 1, ArgCount: 0, LocalCount: 0, EvalDepth: 0,
                Opcode: 0x1B, Operand: 0, LengthInBytes: 1),
            new TCpuTraceEntry(
                Step: 1, Pc: 1, Sp: 12, Fp: 0,
                CallDepth: 1, ArgCount: 0, LocalCount: 0, EvalDepth: 1,
                Opcode: 0x2A, Operand: 0, LengthInBytes: 1),
        };

        using var ms = new MemoryStream();
        TCpuTraceJsonl.WriteAll(ms, entries);

        var text = Encoding.UTF8.GetString(ms.ToArray());
        // hu: Pontosan 2 '\n' egy 2-elemű listához
        Assert.Equal(2, text.Count(c => c == '\n'));
    }

    /// <summary>
    /// hu: End-to-end — TCpuNanoTracer trace-jét közvetlenül szerializáljuk
    /// és visszaolvassuk; az összes adat megőrződik.
    /// <br />
    /// en: End-to-end — serialize a TCpuNanoTracer trace and parse it back;
    /// all data is preserved.
    /// </summary>
    [Fact]
    public void EndToEnd_TracerOutput_RoundtripsThroughJsonl()
    {
        var program = new byte[] { 0x18, 0x19, 0x58, 0x2A };  // 2+3, RET
        var tracer = new TCpuNanoTracer();
        tracer.Execute(program);

        using var ms = new MemoryStream();
        TCpuTraceJsonl.WriteAll(ms, tracer.Entries);
        ms.Position = 0;

        var parsed = TCpuTraceJsonl.ParseAll(ms);

        Assert.Equal(tracer.Entries.Count, parsed.Count);
        for (var i = 0; i < tracer.Entries.Count; i++)
            Assert.Equal(tracer.Entries[i], parsed[i]);
    }
}
