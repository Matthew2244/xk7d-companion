# XK-7D Companion

An app for the Hammond XK-7D organ, made for players who use a screen
reader. There's a Mac version for VoiceOver and a Windows version for NVDA,
JAWS and Narrator. It speaks the changes you make on the organ. It also lets
you see and change the settings the manual's MIDI tables list, from the
keyboard.

The XK-7D's deeper settings live behind a small display. The Owner's Manual
publishes a MIDI address for nearly every one of them, and this app is built
on that map.

**This app hasn't been tested with a real organ yet.** Everything follows the
manual, and the manual has gaps and a few contradictions. Read
[docs/PARAMETER-REVIEW.md](docs/PARAMETER-REVIEW.md) before relying on it.

**The Windows version is new.** It's been built and tested on GitHub's
Windows computers, through the same interface screen readers use. Nobody has
tried it yet with NVDA, JAWS or Narrator on a real Windows PC.

It isn't made by, endorsed by or affiliated with Hammond or Suzuki.

## Download

Get the latest from the
[releases page](https://github.com/Matthew2244/xk7d-companion/releases/latest).

- **Mac:** `XK-7D-Companion-<version>.zip`. Unzip it and move XK-7D
  Companion to Applications. It needs macOS 14 or later.
- **Windows:** `XK-7D-Companion-<version>-Setup.exe`. It installs for you
  only, so it doesn't ask for an administrator password, and adds XK-7D
  Companion to the Start menu. It needs 64-bit Windows 10 or 11.

The Windows installer isn't signed with a code signing certificate, so
Windows may say "Windows protected your PC" the first time. Choose More info,
then Run anyway.

## What it does

- **Speaks changes made on the organ.** For example "Leslie horn fast speed:
  340 rpm", "Upper 8 foot: 6" or "Upper: patch F15". The setting's name comes
  first. A knob you're turning is spoken once, when it stops. If lots of
  settings change at once, as they might when you recall a patch, you hear
  the first one and how many others changed.
- **Lists the settings the manual gives a MIDI address for.** There are 537,
  by category, with a search field. Each row reads "name: value", so you
  don't have to select a setting to hear its value.
- **Sends your changes to the organ straight away.** Named choices use a
  popup menu on the Mac and a drop-down list on Windows. Numbers use a slider, plus
  a box where you can type the value the way the organ shows it.
- **Doesn't guess.** The organ can't be asked for one setting's value. Until
  the organ reports a setting, or you set it from the app, it reads "not
  heard yet". The slider won't move from the keyboard until then, because the
  end of a range can be drastic (0 rpm stops the Leslie horn).
- **Includes a simulator** of the XK-7D, clearly labelled, so you can try it
  without an organ.

## Getting started

1. Connect the organ to the computer with a USB cable and open the app. It
   picks a MIDI port whose name contains XK-7, Hammond or Suzuki. If it
   doesn't, pick the organ in the **Organ** list. If you plug the organ in
   after opening the app, it connects when the organ shows up. If the cable
   comes out or the organ is turned off, the app says "Organ disconnected",
   and connects again when it's back.
2. Choose **Organ > Set Up Organ for This App** (Command Shift U on the Mac,
   Control Shift U on Windows). It offers four changes to the organ's MIDI
   settings, each with a checkbox. Three are ticked. The fourth changes the
   organ's Upper send channel and is off, since it can affect other MIDI
   gear. If the organ sends on a different channel from the app, the app
   tells you, and it's usually easier to change Upper channel in the app's
   Settings. Nothing is sent until you choose Send to Organ. The one that
   matters most is Individual Parameters set to SysEx. Without it, settings
   that have no NRPN number (custom Leslie cabinets, custom tone wheels and
   patch names, among others) are never sent by the organ. To keep these
   settings after the organ is turned off, record the System settings on the
   organ (manual page 142). Loading one of the organ's MIDI templates puts
   Individual Parameters back to NRPN, so run Set Up Organ again after that.
3. Play. Changes are spoken.

To change a setting from the computer, press Command F (Control F on
Windows) and type part of its name, or press Command L (Control L) to go to
the list. Right Arrow opens a category. Tab moves to the editor for the
selected setting. In a slider, the arrow keys step by one. Page Up and Page
Down move a tenth of the range. The screen reader reads the value as the
organ's display shows it.

On Windows, a MIDI port can usually be open in only one program at a time.
If another program is using the organ, the app says so. Close that program
and choose the organ again.

## Keys

| Does | Mac | Windows |
|---|---|---|
| Search settings | Command F | Control F |
| Go to the settings list | Command L | Control L |
| Read from organ | Command R | Control R |
| Set up organ for this app | Command Shift U | Control Shift U |
| Mute or unmute announcements | Command Shift M | Control Shift M |
| Repeat the last announcement | Command Shift L | Control Shift L |
| Main window, simulator window | Command 1, Command 2 | Control 1, Control 2 |
| Put the main window away; the app keeps listening | Command W (hides it) | Control W (minimizes it) |
| Save the last organ snapshot as a .syx file | Command S | Control S |
| Settings | Command comma | Control comma |
| Check for updates | Command U | Control U |
| Help | Command question mark | F1 |
| Quit | Command Q | Alt F4 |

None of the Windows keys use Insert, Caps Lock or Control Alt, so they don't
collide with NVDA, JAWS or Narrator commands, or with AltGr on European
keyboards.

Putting the main window away doesn't stop anything. The app says "Window
hidden. Still listening." on the Mac and "Window minimized. Still
listening." on Windows.

Everything the app has spoken is listed under Recent announcements, at the
bottom of the main window.

## Settings

On the Mac, announcements can go through VoiceOver or the Mac's own voice.
Automatic uses VoiceOver when it's running. There's also an option to use the
Mac's voice while the app is in the background.

On Windows, announcements go through the screen reader that's running. NVDA,
JAWS and several others are spoken to directly, and Narrator through UI
Automation. Automatic uses the Windows voice when no screen reader is
running.

Both have a setting for how long a knob has to rest before it's spoken.

## Updates

From version 1.1.0 the app updates itself. While it's open, it looks for a
new version every four hours. When there is one, it says so once, in one
sentence, when the app is in front and no dialog is open. It never opens a
window by itself. Help > Check for Updates shows what's new and installs it.
Every update is signed, and the app won't install one whose signature
doesn't match.

Copies older than 1.1.0 can't update themselves. Download 1.1.0 once by hand.

## The simulator

Choose Built-in simulator in the Organ list. If you quit while using it, the
app opens on the simulator next time, unless the organ is plugged in. On the
Mac it shows up as a real MIDI port called "XK-7D Simulator (not a real
organ)". Windows has no virtual MIDI ports, so there it's built into the app.
Either way the app talks to it with the same messages it sends the organ. Its
window (Command 2 or Control 2) has buttons that act like the organ's panel.
It also logs what it received.

## Known limits

- **It can't read the organ's current settings.** The manual defines a memory
  dump, and Read from Organ asks for one, checks it and can save it as a .syx
  file. The manual doesn't describe what's inside a dump, though, so the app
  can't turn it into values.
- Some values are shown only by their end points, such as "step 12 of 36".
  The manual doesn't give the curve in between. This covers Leslie rise, fall
  and brake times, vibrato rate, the EQ treble frequency, the vibrato
  emphasis frequency and contact delay.
- Effect 1 and Effect 2 parameters are numbered 1 to 8 rather than named for
  each effect type. The menu pages name each effect's settings, but the
  manual doesn't say which name goes with which number.
- The manual gives no MIDI for some actions, so the app can't record patches,
  use a USB stick, reset the organ or update firmware.
- The Mac version needs macOS 14 or later. So far it has only been run on
  macOS 26.

## Building

### Mac

You need Xcode 26 or later.

    swift test                 # unit and integration tests
    scripts/build-app.sh       # builds "build/XK-7D Companion.app"
    scripts/check-packaged.sh  # checks the built app runs without this folder's .build

### Windows

The Windows version is in `windows/`, written in C# with WPF on .NET 10. The
core and its tests build and run anywhere .NET 10 does, including a Mac:

    dotnet test windows/XK7DCore.Tests

The app itself is built on Windows by `windows/build.ps1`, which GitHub
Actions runs on every push (`.github/workflows/build.yml`). It needs the .NET
10 SDK and Inno Setup 6.

### The parameter table

`Sources/XK7DCore/Resources/parameters.json` holds the settings. Both
versions read this one file. It's generated by
`tools/generate_parameters.py`, which contains the manual's table rows,
transcribed by hand. The generator also writes
`Sources/XK7DCore/ParameterTable.swift`, the same table compiled into the Mac
app. Run it to rebuild both:

    python3 tools/generate_parameters.py

The manual itself isn't in this repository; it's Hammond's copyright.
Download the XK-7 / XK-7D Owner's Manual V1.10 from Suzuki:
<https://www.suzuki-music.co.jp/app/uploads/00457-40226_V110_20260323.pdf>

With the PDF you can check the table against it:

    pdftotext -layout 00457-40226_V110_20260323.pdf manual.txt
    python3 tools/verify_against_manual.py manual.txt
    python3 tools/print_table.py 183      # one page of the table, to compare with the PDF

[docs/PARAMETER-REVIEW.md](docs/PARAMETER-REVIEW.md) records how the table
was checked and lists every place where the manual is unclear.

## Layout

    Sources/XK7DCore         parameter table, MIDI, session, simulator (no user interface)
    Sources/XK7DCoreMIDI     CoreMIDI connection and the simulator's virtual ports
    Sources/XK7DCompanion    the Mac app
    Tests/                   unit tests and app-to-simulator tests
    Tests/Vectors            answers from the Swift core that the Windows tests check against
    windows/XK7DCore         the same core in C#
    windows/XK7DCompanion    the Windows app
    windows/XK7DCore.Tests   the Swift tests ported to C#, plus the shared answers
    windows/UiaCheck         CI's check of the Windows app through UI Automation
    tools/                   table generator, manual cross-check, table printer, appcast writer
    docs/PARAMETER-REVIEW.md how the table was checked
    HANDOFF.md               how it fits together, and what needs a real organ

## License

MIT. See [LICENSE](LICENSE). The Windows version includes Prism (Mozilla
Public License 2.0) and WinSparkle (MIT); their licenses are installed with
it.
