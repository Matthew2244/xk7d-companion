# XK-7D Companion

The Hammond XK-7D keeps most of its settings behind a small display. XK-7D
Companion makes them usable with a screen reader. Play the organ and the app
tells you what you changed. Sit at the computer and you can read and change
those settings from the keyboard.

There's a Mac version for VoiceOver and a Windows version for NVDA, JAWS and
Narrator.

**It hasn't been tried on a real organ yet.** It follows the XK-7D Owner's
Manual, which has gaps and a few contradictions.
[docs/PARAMETER-REVIEW.md](docs/PARAMETER-REVIEW.md) lists every one.

**The Windows version is new.** It's been built and tested on GitHub's
Windows computers, through the same interface screen readers use. Nobody has
used it yet with NVDA, JAWS or Narrator on a real PC.

It isn't made by, endorsed by or affiliated with Hammond or Suzuki.

## Download

- **Mac:** [download XK-7D Companion for Mac](https://github.com/Matthew2244/xk7d-companion/releases/latest/download/XK-7D-Companion-mac.zip).
  Unzip it and move XK-7D Companion to Applications. It needs macOS 14 or
  later.
- **Windows:** [download XK-7D Companion for Windows](https://github.com/Matthew2244/xk7d-companion/releases/latest/download/XK-7D-Companion-Setup.exe)
  and run it. It installs for you only, so it doesn't ask for an
  administrator password, and adds XK-7D Companion to the Start menu. It
  needs 64-bit Windows 10 or 11.

Both links always get the newest version. Older versions are on the
[releases page](https://github.com/Matthew2244/xk7d-companion/releases).

The Windows installer isn't signed with a code signing certificate, so
Windows may say "Windows protected your PC" the first time. Choose More info,
then Run anyway.

## Two ways to use it

**From the organ.** You play and make changes on the organ as you always
would: drawbars, patches, the Leslie, the menus. The computer sits nearby
with the app open and says each change out loud. You don't touch the
computer at all.

**From the computer.** You look up any setting in the app's list, hear its
value, and change it there. The change goes straight to the organ.

You can mix the two. Whatever you change on the organ shows up in the app's
list, and whatever you change in the app is sent to the organ.

## Setting up (once)

1. **Connect the organ** to the computer with a USB cable and open the app.
   It looks for a MIDI port named XK-7, Hammond or Suzuki. If it doesn't
   find the organ, pick it in the **Organ** list. If the organ is plugged in or turned on later, the app
   connects when it shows up. If the cable comes out or the organ is turned
   off, the app says "Organ disconnected" and connects again when it's back.
2. **Choose Organ > Set Up Organ for This App** (Command Shift U on the Mac,
   Control Shift U on Windows). This step matters. Out of the box the organ
   doesn't report every change, so without it some changes you make on the
   organ are never spoken. The app offers four changes to the organ's MIDI
   settings, each with a checkbox:
   - Three are ticked. The important one sets Individual Parameters to
     SysEx. That's what makes the organ report things like custom Leslie
     cabinets, custom tone wheels and patch names.
   - The fourth changes the organ's Upper send channel and is left unticked,
     because it can affect other MIDI gear. If the organ sends on a
     different channel from the app, the app tells you. It's usually easier
     to change Upper channel in the app's Settings instead.

   Nothing changes on the organ until you choose Send to Organ.
3. **Save it on the organ.** To keep these settings after the organ is
   turned off, record the System settings on the organ (manual page 142).
   Loading one of the organ's MIDI templates undoes the important setting,
   so run Set Up Organ again after that.

## Playing with the app listening

Once it's set up, just play. Some examples of what you'll hear:

- Pull a drawbar: "Upper 8 foot: 6". The name comes first, then the value.
- Change patches: "Upper: patch F15".
- Change a Leslie setting in the menus: "Leslie horn fast speed: 340 rpm".

A few things make it easier to follow while you play:

- **A knob or drawbar you're moving is spoken once, when you stop.** You
  hear where it ended up, not every step on the way. Settings has how long it
  waits.
- **When lots of settings change at once**, as they may when you call up a
  patch, you hear the first one and how many others changed, not a list of
  forty.
- **The app doesn't need to be in front.** Command W (Control W on Windows)
  puts the window away and the app keeps listening. It says "Window hidden.
  Still listening." on the Mac and "Window minimized. Still listening." on
  Windows.
- **On the Mac, VoiceOver may not speak for an app that's in the
  background.** If changes go quiet while you're in another app, turn on the
  Settings option to use the Mac's voice while the app is in the background.
  On Windows the screen reader speaks either way.
- **Missed something?** Command Shift L (Control Shift L) repeats the last
  announcement. Everything said so far is under Recent announcements, at the
  bottom of the main window.
- **Need quiet?** Command Shift M (Control Shift M) mutes and unmutes the
  announcements. The app keeps listening and keeps its list up to date.

The app only listens. It never sends anything to the organ unless you change
something in the app or choose Set Up Organ.

### If the organ seems silent

- Check that Set Up Organ for This App has been sent since the last time a
  MIDI template was loaded.
- Check the organ is chosen in the Organ list. The app says "Organ
  disconnected" if it lost the connection.
- If External Zones are on, the organ may stop sending the Upper channel
  (manual page 156). Try with them off.
- On the Mac, see the background note above.
- Check the app isn't muted (Command Shift M or Control Shift M).

## Changing settings from the computer

The app lists the 537 settings the manual gives a MIDI address for, sorted
into categories, with a search field. Each row reads "name: value", so you
hear the value without opening the setting.

- Press Command F (Control F on Windows) and type part of a name, or
  Command L (Control L) to go to the list. Right Arrow opens a category.
- Tab moves to the editor for the selected setting.
- **Numbers** use a slider. The arrow keys step by one, and Page Up and Page
  Down move a tenth of the range. There's also a box where you can type the
  value the way the organ's display shows it. Each change is sent straight
  away.
- **Named choices**, such as Organ Type, are sent only when you pick one. See
  "Choosing from a list" below.

**It doesn't guess.** The organ can't be asked for one setting's value, so a
setting reads "not heard yet" until the organ reports it or you set it from
the app. Until then the slider won't move from the keyboard, because the end
of a range can be drastic: 0 rpm stops the Leslie horn.

### Choosing from a list

Walking through a list of choices doesn't send anything. That matters on an
organ: arrowing from Tone Wheel to Pipe in Organ Type shouldn't send every
type on the way.

- **Mac:** VO Space opens the popup menu. Choose an item and it's sent.
  Escape closes the menu and sends nothing.
- **Windows:** the arrow keys move through the closed list and the screen
  reader reads each choice, but nothing is sent. Press Enter to send the one
  you're on. Alt Down Arrow opens the list; Enter there sends too. Escape puts
  back what was there. If you Tab away without pressing Enter, nothing is sent
  and the app says so.

Either way the app then says what it sent, for example "Organ type sent:
Pipe". The Organ list on Windows works the same way: arrow to the organ and
press Enter to connect.

On Windows, a MIDI port can usually be open in only one program at a time.
If another program is using the organ, the app says so. Close that program,
then choose the organ in the Organ list and press Enter.

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

## Trying it without an organ

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
