using System.Globalization;
using System.Text;
using XK7D.Core;

namespace XK7D.Companion;

/// <summary>The MIDI log: everything that goes to and from the organ, written to a text file someone
/// can send back. Off unless turned on (Help, Keep a MIDI Log). Notes and the expression pedal are
/// counted, not written (MidiLogger). Port of the Mac's MIDILogFile.</summary>
public sealed class MidiLogFile
{
    public static string Folder => Path.Combine(AppSettings.Folder, "Logs");
    public static string FilePath => Path.Combine(Folder, "MIDI Log.txt");
    static string PreviousPath => Path.Combine(Folder, "MIDI Log (previous).txt");
    const long Limit = 20_000_000;

    readonly AppSettings settings;
    readonly MidiLogger logger = new();
    StreamWriter? writer;

    public MidiLogFile(AppSettings settings) { this.settings = settings; }

    public bool IsOn
    {
        get => settings.GetBool("keepMIDILog");
        set
        {
            settings.Set("keepMIDILog", value);
            if (value) Note($"MIDI log started, XK-7D Companion {Updates.Version}");
            else { Note("MIDI log stopped"); Close(); }
        }
    }

    public void Midi(bool incoming, byte[] bytes)
    {
        if (!IsOn) return;
        foreach (var line in logger.Lines(incoming, bytes)) Write(line);
    }

    public void Note(string text)
    {
        if (!IsOn) return;
        Write("--- " + text);
    }

    void Write(string line)
    {
        try
        {
            if (writer is null)
            {
                Directory.CreateDirectory(Folder);
                writer = new StreamWriter(FilePath, append: true, new UTF8Encoding(false)) { AutoFlush = true };
            }
            writer.WriteLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " " + line);
            if (writer.BaseStream.Length > Limit)
            {
                Close();
                File.Delete(PreviousPath);
                File.Move(FilePath, PreviousPath);
            }
        }
        catch (Exception)
        {
            // A log that can't be written must never stop the app.
        }
    }

    void Close()
    {
        try { writer?.Dispose(); } catch (Exception) { }
        writer = null;
    }
}
