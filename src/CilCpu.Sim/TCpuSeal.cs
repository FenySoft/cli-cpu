namespace CilCpu.Sim;

/// <summary>
/// hu: A Seal Core szoftveres referencia szimulátora (CIL-Seal ISA).
/// A TCpuManaged-ből származik, hozzáadja: external call dispatch
/// ([CryptoCall] — SHA-256, WOTS+, Merkle HW unit szimuláció).
/// Az SRAM 64 KB (Seal Core spec).
/// <br />
/// en: Software reference simulator for the Seal Core (CIL-Seal ISA).
/// Extends TCpuManaged, adds: external call dispatch ([CryptoCall] —
/// SHA-256, WOTS+, Merkle HW unit simulation). SRAM is 64 KB (Seal
/// Core spec).
/// </summary>
public sealed class TCpuSeal : TCpuManaged
{
    /// <summary>
    /// hu: Az external call dispatch határ — RVA >= ettől external.
    /// <br />
    /// en: External call dispatch boundary — RVA >= this is external.
    /// </summary>
    public const uint ExternalCallBase = 0xFFFF_0000;

    /// <summary>
    /// hu: Új Seal CPU példány létrehozása 64 KB SRAM-mal.
    /// <br />
    /// en: Creates a new Seal CPU instance with 64 KB SRAM.
    /// </summary>
    public TCpuSeal()
        : base(65536)
    {
    }

    /// <summary>
    /// hu: Új Seal CPU példány létrehozása egyedi SRAM mérettel.
    /// <br />
    /// en: Creates a new Seal CPU instance with a custom SRAM size.
    /// </summary>
    public TCpuSeal(int ASramSize)
        : base(ASramSize)
    {
    }

    /// <summary>
    /// hu: Egyetlen utasítás végrehajtása — a call opkódnál ellenőrzi,
    /// hogy external dispatch-e (RVA >= 0xFFFF_0000).
    /// <br />
    /// en: Executes a single instruction — for call opcodes, checks
    /// whether it's an external dispatch (RVA >= 0xFFFF_0000).
    /// </summary>
    protected override void ExecuteStep(byte[] AProgram)
    {
        var opcode = AProgram[FProgramCounter];

        if (opcode == 0x28) // call
        {
            var pc = FProgramCounter;
            var targetRva = ReadUInt32LE(AProgram, pc + 1);

            if (targetRva >= ExternalCallBase)
            {
                var dispatchIndex = (ushort)(targetRva - ExternalCallBase);
                ExecuteExternalCall(dispatchIndex, pc);
                FProgramCounter = pc + 5;
                return;
            }
        }

        base.ExecuteStep(AProgram);
    }

    /// <summary>
    /// hu: SHA-256 kezdő hash értékek (FIPS 180-4 Section 5.3.3, big-endian).
    /// Az első 8 prímszám négyzetgyökének törtrészéből.
    /// <br />
    /// en: SHA-256 initial hash values (FIPS 180-4 Section 5.3.3, big-endian).
    /// From the fractional parts of the square roots of the first 8 primes.
    /// </summary>
    private static readonly byte[] Sha256InitialHash =
    {
        0x6A, 0x09, 0xE6, 0x67,  // h0
        0xBB, 0x67, 0xAE, 0x85,  // h1
        0x3C, 0x6E, 0xF3, 0x72,  // h2
        0xA5, 0x4F, 0xF5, 0x3A,  // h3
        0x51, 0x0E, 0x52, 0x7F,  // h4
        0x9B, 0x05, 0x68, 0x8C,  // h5
        0x1F, 0x83, 0xD9, 0xAB,  // h6
        0x5B, 0xE0, 0xCD, 0x19   // h7
    };

    private void ExecuteExternalCall(ushort ADispatchIndex, int APc)
    {
        switch (ADispatchIndex)
        {
            case 0x0000: // Sha256.Init — returns byte[32] with IV
                ExecuteSha256Init(APc);
                break;

            case 0x0001: // Sha256.Update(state, data) — void
                ExecuteSha256Update(APc);
                break;

            case 0x0002: // Sha256.Final(state, totalLength) → byte[32]
                ExecuteSha256Final(APc);
                break;

            // hu: Jövőbeli dispatch-ek:
            // 0x0003 = WotsPlus.Verify
            // 0x0004 = MerklePath.Verify

            default:
                throw new TTrapException(TTrapReason.InvalidExternalCall, APc,
                    $"Unknown CryptoCall dispatch index 0x{ADispatchIndex:X4} at PC=0x{APc:X4}.");
        }
    }

    private void ExecuteSha256Init(int APc)
    {
        // hu: 32 byte-os tömb allokálása a heap-en + IV másolás
        // en: Allocate 32-byte array on heap + copy IV

        // newarr(32) szimulálása: push 32, newarr
        EvalPush(32, APc);

        // hu: A TCpuManaged newarr logikáját hívjuk egy trükkel:
        //     a "newarr" opkódot nem futtatjuk újra, hanem közvetlenül
        //     allokálunk a heap-en.
        // en: We directly allocate on the heap (same logic as newarr).
        var length = EvalPop(APc); // 32
        var dataSize = (length + 3) & ~3;
        var totalSize = 4 + dataSize;
        var newHp = HeapPointer - totalSize;

        if (newHp <= FSp)
            throw new TTrapException(TTrapReason.SramOverflow, APc,
                $"Heap/stack collision during Sha256.Init at PC=0x{APc:X4}.");

        SetHeapPointer(newHp);

        // hu: Length mező
        // en: Length field
        SramWriteInt32(newHp, length);

        // hu: IV byte-ok másolása
        // en: Copy IV bytes
        for (var i = 0; i < 32; i++)
            FSram[newHp + 4 + i] = Sha256InitialHash[i];

        // hu: Tömb referencia push a stackre
        // en: Push array reference onto stack
        EvalPush(newHp, APc);
    }

    private void ExecuteSha256Update(int APc)
    {
        // hu: Stack: [state_ref, data_ref] → pop data, pop state. Void.
        // en: Stack: [state_ref, data_ref] → pop data, pop state. Void.
        var dataRef = EvalPop(APc);
        var stateRef = EvalPop(APc);

        var dataLen = SramReadInt32(dataRef);     // tömb length mező
        var dataStart = dataRef + 4;             // tömb adat kezdete

        // hu: State kiolvasása az SRAM-ból (8 × uint32, big-endian)
        // en: Read state from SRAM (8 × uint32, big-endian)
        var h = new uint[8];

        for (var i = 0; i < 8; i++)
            h[i] = ReadUInt32BE(FSram, stateRef + 4 + i * 4);

        // hu: Blokkonként (64 byte) feldolgozás
        // en: Process block by block (64 bytes)
        var offset = 0;

        while (offset + 64 <= dataLen)
        {
            Sha256CompressBlock(h, FSram, dataStart + offset);
            offset += 64;
        }

        // hu: Maradék byte-ok tárolása — az Update nem padel,
        //     csak teljes blokkokat dolgoz fel. A maradékot
        //     a FUnprocessedBytes-ben tároljuk a Final-hez.
        //     Egyszerűsítés: a nem-blokk maradékot a state tömb
        //     végéhez csatolt extra byte-okban tároljuk NEM —
        //     ehelyett a Final kezeli (újraolvassa az inputot).
        //     F1.x szimulátor: az Update CSAK teljes blokkokat
        //     dolgoz, a Final a maradékot.
        // en: Remaining bytes — Update only processes full blocks.
        //     Final handles the remainder with padding.

        // hu: State visszaírása az SRAM-ba
        // en: Write state back to SRAM
        for (var i = 0; i < 8; i++)
            WriteUInt32BE(FSram, stateRef + 4 + i * 4, h[i]);

        // hu: Void return — a firmware lokálisokból hívja az Update-et,
        //     a ref-eket a lokálisok tartják (nem a stack).
        // en: Void return — firmware calls Update from locals,
        //     refs are held in locals (not on stack).
    }

    private void ExecuteSha256Final(int APc)
    {
        // hu: Stack: [state_ref, data_ref, totalLength] → pop all. Returns hash ref.
        // en: Stack: [state_ref, data_ref, totalLength] → pop all. Returns hash ref.
        var totalLength = EvalPop(APc);
        var dataRef = EvalPop(APc);
        var stateRef = EvalPop(APc);

        // hu: State kiolvasása
        // en: Read state
        var h = new uint[8];

        for (var i = 0; i < 8; i++)
            h[i] = ReadUInt32BE(FSram, stateRef + 4 + i * 4);

        // hu: Maradék byte-ok kiolvasása a data tömbből (az Update csak
        //     teljes blokkokat dolgozott fel).
        // en: Read remainder bytes from data array (Update only processed
        //     full blocks).
        var remainder = totalLength % 64;
        var fullBlocksProcessed = (totalLength / 64) * 64;
        var dataStart = dataRef + 4; // tömb adat kezdete
        var padBlock = new byte[64];

        for (var i = 0; i < remainder; i++)
            padBlock[i] = FSram[dataStart + fullBlocksProcessed + i];

        // hu: Padding: 0x80, nullák, 64-bit big-endian bit-length
        // en: Padding: 0x80, zeros, 64-bit big-endian bit-length
        padBlock[remainder] = 0x80;
        var bitLength = (long)totalLength * 8;

        if (remainder >= 56)
        {
            // hu: Két blokk kell a padding-hez
            // en: Padding needs two blocks
            Sha256CompressBlock(h, padBlock, 0);
            padBlock = new byte[64];
        }

        // hu: Bit-length az utolsó 8 byte-ba (big-endian)
        // en: Bit-length in last 8 bytes (big-endian)
        padBlock[56] = (byte)(bitLength >> 56);
        padBlock[57] = (byte)(bitLength >> 48);
        padBlock[58] = (byte)(bitLength >> 40);
        padBlock[59] = (byte)(bitLength >> 32);
        padBlock[60] = (byte)(bitLength >> 24);
        padBlock[61] = (byte)(bitLength >> 16);
        padBlock[62] = (byte)(bitLength >> 8);
        padBlock[63] = (byte)bitLength;

        Sha256CompressBlock(h, padBlock, 0);

        // hu: Eredmény tömb allokálása (32 byte) és hash írása
        // en: Allocate result array (32 bytes) and write hash
        var totalSize = 4 + 32;
        var newHp = HeapPointer - totalSize;

        if (newHp <= FSp)
            throw new TTrapException(TTrapReason.SramOverflow, APc,
                $"Heap/stack collision during Sha256.Final at PC=0x{APc:X4}.");

        SetHeapPointer(newHp);
        SramWriteInt32(newHp, 32);

        for (var i = 0; i < 8; i++)
            WriteUInt32BE(FSram, newHp + 4 + i * 4, h[i]);

        EvalPush(newHp, APc);
    }

    // ------------------------------------------------------------------
    // SHA-256 compression function (FIPS 180-4)
    // ------------------------------------------------------------------

    private static readonly uint[] Sha256K =
    {
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
        0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
        0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
        0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
        0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
        0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
        0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
        0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
        0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    };

    private static void Sha256CompressBlock(uint[] AHash, byte[] ABlock, int AOffset)
    {
        var w = new uint[64];

        for (var i = 0; i < 16; i++)
            w[i] = ReadUInt32BE(ABlock, AOffset + i * 4);

        for (var i = 16; i < 64; i++)
        {
            var s0 = RotR(w[i - 15], 7) ^ RotR(w[i - 15], 18) ^ (w[i - 15] >> 3);
            var s1 = RotR(w[i - 2], 17) ^ RotR(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }

        uint a = AHash[0], b = AHash[1], c = AHash[2], d = AHash[3];
        uint e = AHash[4], f = AHash[5], g = AHash[6], h = AHash[7];

        for (var i = 0; i < 64; i++)
        {
            var s1 = RotR(e, 6) ^ RotR(e, 11) ^ RotR(e, 25);
            var ch = (e & f) ^ (~e & g);
            var temp1 = h + s1 + ch + Sha256K[i] + w[i];
            var s0 = RotR(a, 2) ^ RotR(a, 13) ^ RotR(a, 22);
            var maj = (a & b) ^ (a & c) ^ (b & c);
            var temp2 = s0 + maj;

            h = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
        }

        AHash[0] += a;
        AHash[1] += b;
        AHash[2] += c;
        AHash[3] += d;
        AHash[4] += e;
        AHash[5] += f;
        AHash[6] += g;
        AHash[7] += h;
    }

    private static uint RotR(uint AValue, int ABits) =>
        (AValue >> ABits) | (AValue << (32 - ABits));

    private static uint ReadUInt32BE(byte[] ABytes, int AOffset) =>
        (uint)((ABytes[AOffset] << 24)
            | (ABytes[AOffset + 1] << 16)
            | (ABytes[AOffset + 2] << 8)
            | ABytes[AOffset + 3]);

    private static void WriteUInt32BE(byte[] ABytes, int AOffset, uint AValue)
    {
        ABytes[AOffset] = (byte)(AValue >> 24);
        ABytes[AOffset + 1] = (byte)(AValue >> 16);
        ABytes[AOffset + 2] = (byte)(AValue >> 8);
        ABytes[AOffset + 3] = (byte)AValue;
    }

    private static uint ReadUInt32LE(byte[] ABytes, int AOffset) =>
        (uint)(ABytes[AOffset]
            | (ABytes[AOffset + 1] << 8)
            | (ABytes[AOffset + 2] << 16)
            | (ABytes[AOffset + 3] << 24));
}
