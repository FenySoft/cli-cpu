using System.Text;
using System.Text.Json;

namespace CilCpu.Sim;

/// <summary>
/// hu: A <see cref="TCpuTraceEntry"/> JSONL (JSON Lines) sorosítója és parsere.
/// A JSONL formátum 1 entry / sor — minden sor egy önálló JSON objektum, így a
/// fájl streamelhető, soronként grep-elhető, és a parser nem igényel teljes
/// JSON tömb buffert.
///
/// A formátum stabil kontraktum a cocotb golden-vector harness felé:
/// minden mező kulcsa rögzített (rövid, kompakt), minden szám decimális.
/// Példa egy sorra:
/// <code>
/// {"step":0,"pc":0,"sp":12,"fp":0,"cd":1,"ac":0,"lc":0,"ed":0,"op":27,"oprnd":0,"len":1}
/// </code>
/// <br />
/// en: JSONL (JSON Lines) serializer and parser for <see cref="TCpuTraceEntry"/>.
/// JSONL format is 1 entry per line — each line is a self-contained JSON
/// object, making the file streamable, line-greppable, and parseable without
/// buffering a full JSON array.
///
/// The format is a stable contract toward the cocotb golden-vector harness:
/// field keys are short and fixed, all numbers are decimal.
/// </summary>
public static class TCpuTraceJsonl
{
    private static readonly JsonSerializerOptions FWriteOptions = new()
    {
        WriteIndented = false,
    };

    // hu: BOM nélküli UTF-8 — a JSONL streamelhetőségéhez kritikus, mert a
    //     parser-ek (Python json.loads, jq, stb.) BOM-on hibáznak.
    // en: BOM-less UTF-8 — critical for JSONL streaming since downstream
    //     parsers (Python json.loads, jq, etc.) reject BOM-prefixed input.
    private static readonly UTF8Encoding FUtf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    /// <summary>
    /// hu: A megadott entry-listát JSONL formátumban kiírja a streambe.
    /// Minden entry egy sor, lezárva '\n'-nel. A stream nem záródik.
    /// <br />
    /// en: Writes the given entry list to the stream in JSONL format.
    /// One entry per line, terminated by '\n'. The stream is not closed.
    /// </summary>
    public static void WriteAll(Stream AStream, IEnumerable<TCpuTraceEntry> AEntries)
    {
        using var writer = new StreamWriter(AStream, FUtf8NoBom, leaveOpen: true);
        writer.NewLine = "\n";

        foreach (var entry in AEntries)
        {
            writer.WriteLine(SerializeOne(entry));
        }
    }

    /// <summary>
    /// hu: A streamből beolvas minden entry-t (1 sor = 1 JSON objektum).
    /// Üres sorok átugorva. A stream nem záródik.
    /// <br />
    /// en: Parses every entry from the stream (1 line = 1 JSON object).
    /// Blank lines are skipped. The stream is not closed.
    /// </summary>
    public static IReadOnlyList<TCpuTraceEntry> ParseAll(Stream AStream)
    {
        var result = new List<TCpuTraceEntry>();
        using var reader = new StreamReader(AStream, Encoding.UTF8, leaveOpen: true);

        string? line;
        while ((line = reader.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line))
                continue;

            result.Add(DeserializeOne(line));
        }

        return result;
    }

    /// <summary>
    /// hu: Egy entry-t kompakt JSON formátumba sorosít.
    /// <br />
    /// en: Serializes one entry to compact JSON.
    /// </summary>
    private static string SerializeOne(TCpuTraceEntry AEntry)
    {
        var dict = new Dictionary<string, object>
        {
            ["step"]  = AEntry.Step,
            ["pc"]    = AEntry.Pc,
            ["sp"]    = AEntry.Sp,
            ["fp"]    = AEntry.Fp,
            ["cd"]    = AEntry.CallDepth,
            ["ac"]    = AEntry.ArgCount,
            ["lc"]    = AEntry.LocalCount,
            ["ed"]    = AEntry.EvalDepth,
            ["op"]    = AEntry.Opcode,
            ["oprnd"] = AEntry.Operand,
            ["len"]   = AEntry.LengthInBytes,
        };

        return JsonSerializer.Serialize(dict, FWriteOptions);
    }

    /// <summary>
    /// hu: Egy JSON objektumot entry-vé alakít.
    /// <br />
    /// en: Parses one JSON object into an entry.
    /// </summary>
    private static TCpuTraceEntry DeserializeOne(string AJson)
    {
        using var doc = JsonDocument.Parse(AJson);
        var root = doc.RootElement;

        return new TCpuTraceEntry(
            Step:           root.GetProperty("step").GetInt32(),
            Pc:             root.GetProperty("pc").GetInt32(),
            Sp:             root.GetProperty("sp").GetInt32(),
            Fp:             root.GetProperty("fp").GetInt32(),
            CallDepth:      root.GetProperty("cd").GetInt32(),
            ArgCount:       root.GetProperty("ac").GetInt32(),
            LocalCount:     root.GetProperty("lc").GetInt32(),
            EvalDepth:      root.GetProperty("ed").GetInt32(),
            Opcode:         (byte)root.GetProperty("op").GetInt32(),
            Operand:        root.GetProperty("oprnd").GetInt32(),
            LengthInBytes:  root.GetProperty("len").GetInt32());
    }
}
