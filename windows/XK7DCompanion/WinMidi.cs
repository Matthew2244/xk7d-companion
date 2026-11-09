using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using XK7D.Core;

namespace XK7D.Companion;

/// <summary>MIDI through WinMM, the MIDI API every version of Windows has. One input and one output,
/// opened by name. Without Windows MIDI Services (Windows 11 24H2 and later turns it on), a WinMM
/// port can be open in only one program at a time; opening it then fails with "allocated", which
/// the app explains.</summary>
public sealed class WinMidiConnection : IMidiOutput, IDisposable
{
    // winmm.dll
    const int CALLBACK_NULL = 0, CALLBACK_FUNCTION = 0x30000;
    const int MIM_DATA = 0x3C3, MIM_LONGDATA = 0x3C4, MIM_LONGERROR = 0x3C6;
    const int MMSYSERR_ALLOCATED = 4;
    const int MHDR_DONE = 1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MIDIINCAPS
    {
        public ushort wMid, wPid;
        public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
        public uint dwSupport;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MIDIOUTCAPS
    {
        public ushort wMid, wPid;
        public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
        public ushort wTechnology, wVoices, wNotes, wChannelMask;
        public uint dwSupport;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MIDIHDR
    {
        public IntPtr lpData;
        public uint dwBufferLength;
        public uint dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags;
        public IntPtr lpNext;
        public IntPtr reserved;
        public uint dwOffset;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)] public IntPtr[] dwReserved;
    }

    delegate void MidiInProc(IntPtr h, int msg, IntPtr instance, IntPtr p1, IntPtr p2);

    [DllImport("winmm.dll")] static extern int midiInGetNumDevs();
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int midiInGetDevCapsW(IntPtr id, ref MIDIINCAPS caps, int size);
    [DllImport("winmm.dll")] static extern int midiOutGetNumDevs();
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int midiOutGetDevCapsW(IntPtr id, ref MIDIOUTCAPS caps, int size);
    [DllImport("winmm.dll")] static extern int midiInOpen(out IntPtr h, int id, MidiInProc cb, IntPtr instance, int flags);
    [DllImport("winmm.dll")] static extern int midiInStart(IntPtr h);
    [DllImport("winmm.dll")] static extern int midiInStop(IntPtr h);
    [DllImport("winmm.dll")] static extern int midiInReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int midiInClose(IntPtr h);
    [DllImport("winmm.dll")] static extern int midiInPrepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int midiInUnprepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int midiInAddBuffer(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int midiOutOpen(out IntPtr h, int id, IntPtr cb, IntPtr instance, int flags);
    [DllImport("winmm.dll")] static extern int midiOutClose(IntPtr h);
    [DllImport("winmm.dll")] static extern int midiOutReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int midiOutShortMsg(IntPtr h, int msg);
    [DllImport("winmm.dll")] static extern int midiOutLongMsg(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int midiOutPrepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int midiOutUnprepareHeader(IntPtr h, IntPtr hdr, int size);

    static readonly int HdrSize = Marshal.SizeOf<MIDIHDR>();
    static readonly int BytesRecordedOffset = Marshal.OffsetOf<MIDIHDR>(nameof(MIDIHDR.dwBytesRecorded)).ToInt32();
    static readonly int FlagsOffset = Marshal.OffsetOf<MIDIHDR>(nameof(MIDIHDR.dwFlags)).ToInt32();
    const int InBufferSize = 1024, InBufferCount = 16;

    /// <summary>Bytes from the organ, delivered on the thread given to post (the UI thread).</summary>
    public Action<byte[]>? OnReceive { get; set; }
    readonly Action<Action> post;

    IntPtr inHandle, outHandle;
    MidiInProc? callback;                      // kept alive while WinMM may call it
    readonly List<IntPtr> inHeaders = new();
    volatile bool closing;
    /// <summary>Which opening of the input a callback belongs to (WinMM hands it back as the
    /// instance value). A buffer from an earlier opening is never queued again: it has been freed,
    /// and a reopened port can get the same handle value.</summary>
    int generation;
    BlockingCollection<byte[]>? sendQueue;
    Thread? sender;

    public WinMidiConnection(Action<Action> post) { this.post = post; }

    public bool CanSend => outHandle != IntPtr.Zero;
    /// <summary>Why the output couldn't be opened, as a sentence, or null.</summary>
    public string? OutputProblem { get; private set; }

    /// <summary>Input port names, in WinMM's order.</summary>
    public static List<string> InputNames()
    {
        var names = new List<string>();
        try
        {
            var n = midiInGetNumDevs();
            for (var i = 0; i < n; i++)
            {
                var caps = new MIDIINCAPS();
                names.Add(midiInGetDevCapsW(i, ref caps, Marshal.SizeOf<MIDIINCAPS>()) == 0 ? caps.szPname : "");
            }
        }
        catch (Exception) { }
        return names;
    }

    public static List<string> OutputNames()
    {
        var names = new List<string>();
        try
        {
            var n = midiOutGetNumDevs();
            for (var i = 0; i < n; i++)
            {
                var caps = new MIDIOUTCAPS();
                names.Add(midiOutGetDevCapsW(i, ref caps, Marshal.SizeOf<MIDIOUTCAPS>()) == 0 ? caps.szPname : "");
            }
        }
        catch (Exception) { }
        return names;
    }

    /// <summary>"2- XK-7D", "MIDIIN2 (XK-7D)" and "XK-7D" are the same device to a person.</summary>
    public static string Plain(string name)
    {
        var s = System.Text.RegularExpressions.Regex.Replace(name, @"^\d+-\s*", "");
        s = System.Text.RegularExpressions.Regex.Replace(s, @"^MIDI(IN|OUT)\d*\s*\((.*)\)$", "$2", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return s.Trim();
    }

    /// <summary>The output that goes with an input of this name: the same name, or the same name once
    /// Windows' numbering is taken off.</summary>
    public static int OutputFor(string inputName)
    {
        var outs = OutputNames();
        var exact = outs.IndexOf(inputName);
        if (exact >= 0) return exact;
        var plain = Plain(inputName);
        return outs.FindIndex(o => string.Equals(Plain(o), plain, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Open the input called name and its output. Throws with a sentence a person can act on.</summary>
    public void Connect(string name)
    {
        Disconnect();
        closing = false;
        var inId = InputNames().IndexOf(name);
        if (inId < 0) throw new InvalidOperationException($"The MIDI port {name} is not available.");
        callback = OnMidiIn;
        OutputProblem = null;
        generation++;
        var r = midiInOpen(out inHandle, inId, callback, new IntPtr(generation), CALLBACK_FUNCTION);
        if (r != 0)
        {
            inHandle = IntPtr.Zero;
            throw new InvalidOperationException(r == MMSYSERR_ALLOCATED
                ? $"Another program is using {name}. Close it, then choose the organ again."
                : $"Windows couldn't open {name} (MIDI error {r}).");
        }
        for (var i = 0; i < InBufferCount; i++)
        {
            var hdr = Marshal.AllocHGlobal(HdrSize);
            var buf = Marshal.AllocHGlobal(InBufferSize);
            Marshal.StructureToPtr(new MIDIHDR { lpData = buf, dwBufferLength = InBufferSize, dwReserved = new IntPtr[8] }, hdr, false);
            if (midiInPrepareHeader(inHandle, hdr, HdrSize) == 0 && midiInAddBuffer(inHandle, hdr, HdrSize) == 0) inHeaders.Add(hdr);
            else { Marshal.FreeHGlobal(buf); Marshal.FreeHGlobal(hdr); }
        }
        midiInStart(inHandle);

        var outId = OutputFor(name);
        if (outId >= 0)
        {
            r = midiOutOpen(out outHandle, outId, IntPtr.Zero, IntPtr.Zero, CALLBACK_NULL);
            if (r != 0)
            {
                outHandle = IntPtr.Zero;   // listening still works; sending is said to be unavailable
                OutputProblem = r == MMSYSERR_ALLOCATED
                    ? $"Another program is using {name}'s MIDI output, so changes can't be sent. Close it, then choose the organ again."
                    : $"Windows couldn't open {name}'s MIDI output (MIDI error {r}), so changes can't be sent.";
            }
        }
        else OutputProblem = $"{name} has no MIDI output Windows could find, so changes can't be sent.";
        if (outHandle != IntPtr.Zero)
        {
            sendQueue = new BlockingCollection<byte[]>();
            var queue = sendQueue;
            var handle = outHandle;
            sender = new Thread(() => SendLoop(handle, queue)) { IsBackground = true, Name = "MIDI out" };
            sender.Start();
        }
    }

    public void Disconnect()
    {
        closing = true;
        if (sendQueue is { } q) { q.CompleteAdding(); sender?.Join(3000); }
        sendQueue = null;
        sender = null;
        if (outHandle != IntPtr.Zero)
        {
            try { midiOutReset(outHandle); midiOutClose(outHandle); } catch (Exception) { }
            outHandle = IntPtr.Zero;
        }
        if (inHandle != IntPtr.Zero)
        {
            try
            {
                midiInStop(inHandle);
                midiInReset(inHandle);          // hands every buffer back
                foreach (var hdr in inHeaders) midiInUnprepareHeader(inHandle, hdr, HdrSize);
                midiInClose(inHandle);
            }
            catch (Exception) { }
            inHandle = IntPtr.Zero;
        }
        foreach (var hdr in inHeaders)
        {
            var h = Marshal.PtrToStructure<MIDIHDR>(hdr);
            Marshal.FreeHGlobal(h.lpData);
            Marshal.FreeHGlobal(hdr);
        }
        inHeaders.Clear();
    }

    /// <summary>WinMM calls this on its own thread. Nothing here calls WinMM back; the data goes to
    /// the UI thread, which re-queues the buffer.</summary>
    void OnMidiIn(IntPtr h, int msg, IntPtr instance, IntPtr p1, IntPtr p2)
    {
        if (msg == MIM_DATA)
        {
            var packed = p1.ToInt64();
            var status = (byte)(packed & 0xFF);
            var len = MessageLength(status);
            var bytes = new[] { status, (byte)((packed >> 8) & 0x7F), (byte)((packed >> 16) & 0x7F) }.Take(len).ToArray();
            post(() => OnReceive?.Invoke(bytes));
        }
        else if (msg is MIM_LONGDATA or MIM_LONGERROR)
        {
            // MIM_LONGERROR is a broken SysEx message. Its buffer still has to go back to WinMM, or
            // each one would take a buffer away for good, and after 16 no SysEx would arrive at all.
            var hdr = p1;
            var bytes = Array.Empty<byte>();
            if (msg == MIM_LONGDATA)
            {
                var count = Marshal.ReadInt32(hdr, BytesRecordedOffset);
                var data = Marshal.ReadIntPtr(hdr);
                bytes = new byte[count];
                if (count > 0) Marshal.Copy(data, bytes, 0, count);
            }
            var handle = h;
            var opening = instance.ToInt32();
            post(() =>
            {
                if (bytes.Length > 0) OnReceive?.Invoke(bytes);
                if (!closing && opening == generation && handle == inHandle && inHeaders.Contains(hdr))
                    midiInAddBuffer(handle, hdr, HdrSize);
            });
        }
    }

    static int MessageLength(byte status) => status switch
    {
        >= 0xF8 => 1,
        0xF1 or 0xF3 => 2,
        0xF2 => 3,
        0xF6 => 1,
        _ => (status & 0xF0) is 0xC0 or 0xD0 ? 2 : 3,
    };

    public void Send(byte[] bytes)
    {
        if (sendQueue is { IsAddingCompleted: false } q) q.Add(bytes);
    }

    static void SendLoop(IntPtr handle, BlockingCollection<byte[]> queue)
    {
        foreach (var bytes in queue.GetConsumingEnumerable())
        {
            try
            {
                if (bytes.Length > 0 && bytes[0] == 0xF0) SendLong(handle, bytes);
                else SendShort(handle, bytes);
            }
            catch (Exception) { }
        }
    }

    static void SendShort(IntPtr handle, byte[] bytes)
    {
        var parser = new MidiByteParser();
        foreach (var m in parser.Feed(bytes))
        {
            var b = m.Bytes;
            var packed = b[0] | (b.Length > 1 ? b[1] << 8 : 0) | (b.Length > 2 ? b[2] << 16 : 0);
            midiOutShortMsg(handle, packed);
        }
    }

    static void SendLong(IntPtr handle, byte[] bytes)
    {
        var hdr = Marshal.AllocHGlobal(HdrSize);
        var buf = Marshal.AllocHGlobal(bytes.Length);
        var free = true;
        try
        {
            Marshal.Copy(bytes, 0, buf, bytes.Length);
            Marshal.StructureToPtr(new MIDIHDR { lpData = buf, dwBufferLength = (uint)bytes.Length, dwBytesRecorded = (uint)bytes.Length, dwReserved = new IntPtr[8] }, hdr, false);
            if (midiOutPrepareHeader(handle, hdr, HdrSize) != 0) return;
            if (midiOutLongMsg(handle, hdr, HdrSize) == 0)
            {
                // Wait for the driver to finish with the buffer before freeing it (at most 2 s).
                for (var i = 0; i < 2000 && (Marshal.ReadInt32(hdr, FlagsOffset) & MHDR_DONE) == 0; i++) Thread.Sleep(1);
            }
            // A driver still holding the buffer keeps it: freeing it then could crash the app.
            free = midiOutUnprepareHeader(handle, hdr, HdrSize) == 0;
        }
        finally
        {
            if (free)
            {
                Marshal.FreeHGlobal(buf);
                Marshal.FreeHGlobal(hdr);
            }
        }
    }

    public void Dispose() => Disconnect();
}
