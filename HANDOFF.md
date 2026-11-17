# Hand-off notes

Version 1.1.0 added a Windows version, and updates through Sparkle on the Mac
and WinSparkle on Windows. 1.1.1 is a review release; see "Changes in 1.1.1".
1.2.0 answers the first report from a real XK-7D; see "Changes in 1.2.0".
1.2.1 adds a switch for drawbar speech; see "Changes in 1.2.1". 1.3.0 says only
the value when the same control moves again; see "Changes in 1.3.0". All of them have been tested against the
built-in simulator only. Neither has been connected to a real XK-7D. The
Windows version has been built and tested on GitHub's Windows runners, and
nobody has used it yet with a screen reader on a real PC.

## Architecture

Three Swift modules in one package (`Package.swift`):

- **XK7DCore**: no UI, no CoreMIDI; builds for iOS as is.
  - `Parameters.swift`: the table model. A `Parameter` is one row of the
    manual (or a family of rows differing by an index, like one level per tone
    wheel); a `Setting` is a parameter with its indices filled in, which is
    one real address on the organ. `ParameterDatabase` loads
    `Resources/parameters.json` and looks settings up by SysEx address, by
    NRPN, by id and by search words.
  - `ValueFormat.swift`: raw value to the organ's display text, to speech
    text, and back from typed text.
  - `MIDIMessages.swift`: byte-stream parser (running status, real-time bytes,
    SysEx split across packets); every SysEx message on p. 177 (Data Set, Dump
    Request, Data Packet with nibblizing and check digit, Acknowledge, NRPN
    Switch, Identity); NRPN encoding; drawbar CC map and bucketing; program
    change naming.
  - `NRPNDecoder.swift`: CC 99/98/6/38 state machine. One-byte parameters
    complete on CC 6; two-byte ones wait for CC 38.
  - `Coalescer.swift`: speaks a turning knob once. Each setting speaks after
    350 ms of quiet, latest value only; a sweep longer than 2 s is spoken
    anyway, then settles again. Since 1.3.0 it also decides when only the value
    is said (see "Changes in 1.3.0").
  - `OrganSession.swift`: the heart. Decodes everything, keeps known values,
    sends changes by SysEx Data Set, hides echoes of its own changes (same
    value back within 2 s), produces announcement text, learns the organ's
    Device ID, collects and acknowledges dump packets. It also paces sends
    (a fast sweep is merged, latest value wins, at most one every 20 ms) and
    can hold sends until the other end answers an Identity Request (used for
    the simulator; see "Lost first message" below).
  - `PatchNames.swift`: the factory patch names (pp. 172-173), reading names
    out of a Temporary dump, and the spoken patch line.
  - `MIDILog.swift`: `MIDILogger`, one line per message for the MIDI log.
  - `SimulatedOrgan.swift`, `Loopback.swift`: the simulator and an
    in-process link.
- **XK7DCoreMIDI**: `CoreMIDIConnection` (list ports, connect, send, receive)
  and `VirtualSimulatorPorts` (publishes the simulator as a real MIDI source
  and destination).
- **XK7DCompanion**: the AppKit app. `AppModel` owns the session, connection,
  simulator and announcer; `MainWindowController`, `DetailView`,
  `OtherWindows` (simulator and settings), `AppDelegate` (menus, commands),
  `Announcer` (VoiceOver announcement or AVSpeechSynthesizer).

The app's name is in one place: `AppIdentity.name` in `AppDelegate.swift`.
`scripts/build-app.sh` reads it from there. The version is in one place too:
the `VERSION` file, read by `scripts/build-app.sh`, `scripts/release.sh` and
the Windows project.

## The Windows version

Three C# projects in `windows/`, on .NET 10:

- **XK7DCore**: a line-by-line port of `Sources/XK7DCore`, with the same
  names where C# allows. No UI, no MIDI API, so it builds and its tests run on
  Windows, Mac and Linux. It reads the same `parameters.json`, compiled into
  the DLL as an embedded resource (the lesson of 1.0.4: no file to lose).
- **XK7DCompanion**: the WPF app. `AppModel.cs` is a port of `AppModel.swift`
  with the same sentences; `MainWindow.cs`, `DetailPanel.cs` and
  `OtherWindows.cs` match the Mac windows; `Speech.cs` is Prism, `WinMidi.cs`
  is WinMM, `Updates.cs` is WinSparkle, `SelfTest.cs` is the silent self-test.
  The UI is built in code, no XAML.
- **UiaCheck**: CI's check of the running app through UI Automation (see CI).

**Why C# and WPF.** The screen reader experience decided it. WPF is built on UI Automation, which NVDA, JAWS and Narrator read, and
its automation API is public, so what each control exposes can be set and
then checked in CI. The slider is the case that mattered: it has to read
"340 rpm" rather than a number or a percentage. In WinForms the classes that
would need changing are internal. C# is also close enough to Swift that the
port reads line for line, the core and its tests run on this Mac with
`dotnet test`, and the app cross-builds here; only running it needs Windows.
Swift itself runs on Windows but has no accessible UI toolkit there. Python
with wxPython (Wavelength's stack) would have meant porting the core into a
dynamic language with no compiler to catch slips. The app is published
self-contained, so nobody has to install .NET: about 130 MB installed, a
47 MB installer.

**Speech.** Prism 0.18.3 (`prism.dll`, MPL-2.0), taken from the prismatoid
wheel on PyPI with its checksum pinned, the build Wavelength ships. It's
called through its C API. Automatic tries NVDA, JAWS, ZDSR, System Access,
ZoomText, Sense Reader, PC-Talker and Boy PC Reader in Wavelength's order;
if none is running but Windows' screen reader flag is set (Narrator sets it),
it sends a UI Automation notification; otherwise it uses the Windows voice
(Prism's OneCore, else SAPI). Announcements interrupt, like VoiceOver's high
priority on the Mac; the update news waits its turn. There's no "voice in
the background" setting on Windows: screen readers speak Prism's messages
whether or not the app is in front.

**MIDI.** WinMM, which every Windows has. Inputs are listed by name; the
output is the one with the same name, or the same name once Windows'
numbering ("2- XK-7D", "MIDIIN2 (XK-7D)") is taken off. WinMM has no notice
when a device comes or goes, so the app looks every 2 seconds and hands the
list to the same `PortPolicy` as the Mac. Without Windows MIDI Services, a
WinMM port can be open in only one program at a time; opening one that's in
use fails with "allocated", and the app says another program is using it.
SysEx goes out with `midiOutLongMsg` on its own thread; 16 input buffers of
1 KB take SysEx in. CI has no MIDI device, so this has run only as far as
listing ports (0 inputs, 1 output, Microsoft's synth). It hasn't talked to
any real MIDI device.

**The simulator** is in-process on Windows (Windows has no virtual MIDI
ports): the session and the simulated organ swap messages through the UI
thread's queue, the same `LoopbackLink` the Mac falls back to. Holding
messages until the simulator answers isn't needed there.

**UI details worth keeping:**

- The value slider (`ValueSlider` in `UiKit.cs`) offers UI Automation's
  Value pattern only, holding the spoken value. It has no RangeValue
  pattern, because NVDA reads a RangeValue slider as a percentage.
  Through Windows' bridge, MSAA (which JAWS leans on) reads the same name and
  value; UiaCheck checks both. Up and Right step up, as on the Mac (Windows'
  own trackbar has it the other way round). Setting the Value pattern from a
  screen reader is the same as typing a value.
- A row in the settings list whose value changes while it has the focus is
  updated when the focus moves on, so the screen reader isn't made to read
  the row again on top of the announcement.
- The tree's expand toggles are left out of what screen readers see
  (`RowPeer`); the row itself expands with the arrow keys.
- Choices are a drop-down list, and since 1.1.1 they send only on purpose
  (`PickOnEnter` in `UiKit.cs`). The arrow keys on the closed list only move,
  and the screen reader reads each item; Enter sends it and the app says
  "Organ type sent: Pipe". In the open list (Alt Down Arrow) Enter or a click
  sends. Escape, or leaving the list, puts back what was there and sends
  nothing. Windows lists normally pick as you arrow, which on an organ would
  send every Organ Type on the way. The Organ list works the same way, so
  arrowing past a MIDI port doesn't open it. WPF commits the open list's
  choice in a different order for keys and the mouse, so the decision waits
  until the list has closed. UiaCheck presses the real keys.
- Control W minimizes and says "Window minimized. Still listening." Closing
  the window (Alt F4) quits, as Windows apps do. Only one copy can run, since
  two would fight over the organ's port.
- What the Mac shows as labels (help, range, manual note, source) is a
  read-only text box called "About <setting>", so Tab reaches it.
- Settings uses lists for the wait (100 to 2000 ms in steps of 50, the Mac
  stepper's range) and the Device ID (0 to 127).

## One table, one set of answers

`Sources/XK7DCore/Resources/parameters.json` is the only table. The Swift
app compiles it in through `ParameterTable.swift`; the C# core embeds the
same file.

`Tests/Vectors/core-vectors.json` holds the Swift core's answers, written by
`Tests/XK7DCoreTests/SharedVectorTests.swift`. That Swift test fails if the
file is out of date; after a deliberate change, rewrite it with
`XK7D_WRITE_VECTORS=1 swift test --filter SharedVectorTests`. The C# tests
(`windows/XK7DCore.Tests/SharedVectorTests.cs`) must give the same answer to
every one: all 40,522 values of all 537 settings as displayed and spoken,
what typing each of those back gives, and 105 more typed inputs on every
setting that takes one (about 100,000 typed checks in all); 3,919 settings'
addresses, spoken names, Data Set bytes and where each family ends; every
NRPN number; every patch name; notes, drawbar levels and text encoding. On
top of that, every address of every indexed family, all 671,144, is checked
to look back up to itself.

The Swift tests are ported one to one, with the same names, in
`windows/XK7DCore.Tests`. The two CoreMIDI tests have no Windows
counterpart; the in-process scenario is ported, plus a System dump test.

To make the C# match exactly, it reproduces the Swift that typed values go
through: `Scanner.scanDouble` (any Unicode digit counts; "1e" stops before
the e), `CharacterSet.whitespaces` and `.letters`, Swift's `Int("...")`, and
`rounded()` (halves away from zero, where C# rounds to even by default).
Checked by breaking it on purpose: switching C# to round-to-even, or to
ASCII digits only, each made the shared-answers test fail.

**Found while porting:** 1.0.4 stops (a Swift trap) when a number too big
for Int is typed into a value field: "1e400" scans as infinity, and
99999999999999999999 as 1e20. Fixed in both cores (`whole()`), with a test
that crashes 1.0.4.

## Updates

**Mac:** Sparkle 2.10.1 through SwiftPM (`exact:`; Sparkle's manifest pins
its binary by checksum). `scripts/build-app.sh` copies `Sparkle.framework`
into Contents/Frameworks without its XPC services (they're for sandboxed
apps), adds the `@executable_path/../Frameworks` rpath, and signs inside out:
Autoupdate, Updater.app, the framework, then the app, all with the hardened
runtime. Info.plist has `SUFeedURL`, `SUPublicEDKey`,
`SUEnableAutomaticChecks` NO and `SUAllowsAutomaticUpdates` NO.
`check-packaged.sh` now also fails unless Sparkle loads from inside the app
and starts.

**Windows:** WinSparkle 0.9.4 (MIT, checksum pinned), the version Wavelength
uses, called through its C API. Only an installed copy uses it, because
WinSparkle updates by running the new installer. Its own checks are off.

**Matthew's rules, both systems:** updates are heard, not popped up. The app
looks 15 seconds after it opens and every 4 hours while it's open (Mac:
Sparkle's `checkForUpdateInformation`, which never shows a window; Windows:
the app reads `appcast-windows.xml` itself, with `Appcast.NewestIn` in the
core, tested). When it finds a newer version it says "XK-7D Companion X is
out. Help, Check for Updates shows what's new and installs it." once per
version (`toldUpdateVersion`), only when the app is in front, no dialog or
sheet is open and announcements aren't muted. Help > Check for Updates
(Command U, Control U) opens Sparkle's or WinSparkle's window. A version the
person saw there isn't announced again.

**The update lists** are release assets, read from
`releases/latest/download/appcast.xml` and `appcast-windows.xml`, as
Wavelength's are. Those URLs redirect; Sparkle and WinSparkle follow
redirects, and Wavelength's real updates have gone through them. Every
release must carry both lists, or updates break until it does.

**No portable zip for Windows.** The installer needs no administrator
password, and only an installed copy can update itself, so a zip would be
a copy that never updates.

**Code signing on Windows:** there's no Windows code signing certificate
(Wavelength has none either), so the installer and app are unsigned and
SmartScreen may warn. The README says how to get past it. Updates are still
protected: WinSparkle checks the EdDSA signature before running anything.

### The signing key

XK-7D Companion has its own EdDSA key, separate from Wavelength's, so losing
or leaking one can't affect the other. It's in the Studio's login Keychain:
"Private key for signing Sparkle updates", service
`https://sparkle-project.org`, **account `xk7d-companion`**, made 2026-11-08.
Wavelength's is the same label with account `ed25519`. The public half is in
`scripts/build-app.sh` and `windows/XK7DCompanion/Updates.cs`; the Mac and
Windows versions use the same key.

**Lose the private key and no installed copy, Mac or Windows, will accept
another update.** Back it up once, somewhere safe and never in the repo:

    "$(scripts/sparkle-tools.sh)/generate_keys" --account xk7d-companion -x ~/Desktop/xk7d-sparkle-key.txt

Put that file's contents in a password manager, then delete the file. To
restore on another Mac: `generate_keys --account xk7d-companion -f FILE`.

Only `generate_keys` can read the key without a Keychain prompt (the item's
access list names it). So `scripts/sparkle-sign.sh` has `generate_keys`
export it into a private temporary folder, has `sign_update` sign with it,
then overwrites and removes it, all in under a second. Nothing prompts and
nothing secret stays on disk. `tools/appcast.py` uses it to write both lists.

### Rehearsing an update

**Mac**, done on the Studio 2026-11-08 with no window or Dock icon:

    XK7D_TEST_FEED=http://127.0.0.1:8765/appcast.xml SIGN_IDENTITY=... scripts/build-app.sh   # copy A, 1.1.0
    XK7D_VERSION=1.1.1 XK7D_TEST_FEED=... SIGN_IDENTITY=... scripts/build-app.sh            # B, zip it
    python3 tools/appcast.py B.zip 1.1.1 http://127.0.0.1:8765/B.zip > appcast.xml       # serve both on 127.0.0.1:8765
    open -g -n --env XK7D_UPDATE_TEST=log A.app

`XK7D_UPDATE_TEST` checks the test feed, downloads, verifies and stages the
update, then quits so Sparkle installs it. A test build allows local http
and silent installs; a release build doesn't, and the rehearsal refuses to
run in one. Result: with a wrong signature Sparkle said "The update is
improperly signed" and A stayed 1.1.0; with the right one A became 1.1.1,
still valid Developer ID with the same team, and passed its self-test. The
first attempt brought up Sparkle's update window for up to a minute,
because Sparkle allows silent downloads only while its own automatic checks
are on; the rehearsal turns them on now. Afterwards, delete the `SU*` keys
from the `io.github.matthew2244.xk7dcompanion` defaults: every copy shares
that domain.

Not rehearsed: clicking Install in Sparkle's own window. After the click,
Sparkle's install path is the one rehearsed.

**Windows**: the `update-rehearsal` CI job, every push. See CI.

## CI

`.github/workflows/build.yml`, on every push:

- **core**: the C# core's tests on Windows, Mac and Linux.
- **swift**: `swift test` on a Mac runner, including the check that
  `Tests/Vectors` is current.
- **windows**: `windows/build.ps1` publishes the app, adds Prism and
  WinSparkle, runs the packaged app's self-test from a copy elsewhere, runs
  UiaCheck, builds the installer; then the job installs it silently, checks
  the Start menu entry and version, runs the installed copy's self-test
  (which also starts WinSparkle), and uninstalls it. On a tag it attaches the
  installer to the release.
- **update-rehearsal**: makes a throwaway EdDSA key (the real one never
  leaves the Studio), builds test versions 1.1.0 and 1.1.1 that trust it,
  serves a signed list from 127.0.0.1, installs 1.1.0, and checks that a
  tampered signature is downloaded and refused and a good one installs 1.1.1
  through WinSparkle.

**What UiaCheck proves.** It starts the real app (`--ui-test`: silent, on
the simulator, settings in a scratch folder) and reads it the way screen
readers do. Every control a person can reach in the main, simulator and
settings windows has a name. Search finds a setting, and its row reads
"name: value". The slider offers only the Value pattern, reads "not heard
yet", and MSAA reads the same. With real key presses (SendInput), Up Arrow on
"not heard yet" sends nothing and says why; after a typed value, Up Arrow,
Page Up and Home step and each change reaches the simulator; the row follows;
an impossible value is refused; closing the window quits cleanly. It doesn't
prove how NVDA, JAWS or Narrator speak any of it. That needs a person.

## Writing to the organ

Every change goes out as a SysEx Data Set:
`F0 55 dd 10 26 13 [5 address bytes] [data] F7`. Two-byte values are two
7-bit bytes, MSB first. The manual says SysEx is received whatever the
Individual Parameters setting is. The app never sends anything unprompted
except an Identity Request when you connect (to the configured ID and to
all-call 7F) and, since 1.2.0, a Temporary Dump Request after a User patch or
Favorite is chosen (see "Patch names"; Settings can turn it off).

## The parameter table pipeline

The manual isn't in this repository (it's Hammond's copyright); the README
says where to download it.

1. `tools/generate_parameters.py` holds every row of pp. 178-185,
   transcribed by hand with the address exactly as printed (placeholders
   like `3x`, `4b`, `0p`, `tt` included). It expands small placeholders into
   separate settings (6 external zones, 10 Patch Load banks) and keeps large
   ones as index pickers. It asserts that every NRPN equals the last two
   address bytes, that every byte is 7-bit, and that no two settings share
   an address.
2. `tools/verify_against_manual.py manual.txt` finds each row in the
   manual's text export by name and bytes, and compares the Data column's
   range with the table.
3. `tools/print_table.py N` prints page N of the generated table for
   comparison with the PDF page image. All of pp. 176-185 were compared row
   by row.
4. The Swift tests encode every worked example in the manual through the
   generated table.

`docs/PARAMETER-REVIEW.md` has the results and the full list of
ambiguities. The checks caught four real errors, all fixed: three two-byte
ranges (Leslie fast speed, mic distance, Master Tune) and the generator
reading the placeholder `ff` as the byte FF. A second pass through the
manual's menu pages settled several items the MIDI tables left unclear.

## Verified, and how

| What | How |
|---|---|
| Every address, NRPN and length in the table | Text cross-check (320 rows: 318 by name and bytes, 2 on the page image) and row-by-row comparison with page images 176-185 |
| Every worked example in the manual (Organ Type Mellow, Master Tune 442, Expression Source MIDI, Favorite E-C♯ = F04, Matrix Level -12.1 dB, Contact middle C, Pipe S04, drawbar Lower 8´ = 7, three program changes) | Unit tests |
| Two-byte signed and unsigned packing, nibblizing, check digit, packet framing | Unit tests |
| NRPN stream parsing, running status, SysEx across packets, drawbar buckets for all 128 values | Unit tests |
| Coalescing, echo suppression, device ID learning, multi-parameter Data Set | Unit tests |
| App and simulator talking both ways | Integration tests over the in-process link **and over real CoreMIDI virtual ports** |
| Values the MIDI tables left unclear (fold-back keys, percussion decay, external zone program numbers, sounding point, mic distance, preset key hold time) | Menu pages 85, 100, 103, 109, 121 and 137; unit tests |
| The built .app | Silent self-test (`XK7D_SELFTEST=path`), run repeatedly; accessibility tree read with `tools/ax-inspect.swift`: every control labelled, slider values read as the display shows them, every command in a menu with a shortcut |
| The C# core gives the Swift core's answers | `Tests/Vectors` (above), on Windows, Mac and Linux |
| The Windows app | Packaged and installed self-tests and UiaCheck on CI's Windows runners (above) |
| Mac updates | Rehearsal on the Studio: tampered refused, good one installed (above) |
| Windows updates | CI's update rehearsal (above) |

Tests: Swift, 142 unit tests and 5 integration tests. C#, 161 tests (1.3.0).

## Guessed or inferred (see PARAMETER-REVIEW.md for the full table)

- Vibrato mode order. 1.0 assumed V-1, V-2, V-3, C-1, C-2, C-3. 1.0.1 uses
  V-1, C-1, V-2, C-2, V-3, C-3, the order the positions are printed around
  the knob on p. 58 (clockwise from V-1), which is also the B-3's. Still a
  reading of a drawing, not a statement.
- Custom Pipe Pedal uses part 3 (the manual also suggests 2).
- Tone wheel brake range bottom (-24, raw 28h; the table prints 34h, and
  the menu page says -24).
- Custom set numbering order (U first, then F). The MIDI tables write
  "U1 - F4"; the menu pages list F first for most sets.
- Patch Load bank numbering (b = 0 to 9 for C to A).
- Leslie mic width (MIDI 0-100, menu 0-40 cm or Side); Impedance footages;
  preset key hold time units (MIDI says seconds, menu says ms).
- Dump check digit: XOR of the nibblized bytes. Incoming packets are accepted
  if either reading matches, and the app records which one did.
- A Data Set carrying several parameters is read by stepping the last address
  byte. The manual only says "flexible bytes".
- Answering each dump packet with an Acknowledge. The manual defines
  Acknowledge but not who sends it or when.
- Identity Request to all-call 7F as well as the configured ID.

## Needs a real organ to confirm

1. **Whether every panel edit is transmitted**, and how: with Individual
   Parameters on NRPN and on SysEx. Especially menu edits (custom Leslie
   values, tone wheel tables) and patch recall: does recalling a patch send
   all its parameters, or only a program change? If it sends them all, the
   app now says the first change and a count ("Upper: patch U05, and 40 more
   settings changed") instead of reading each one. More than 8 settings
   changing together counts as a burst.
   Also: p. 156 says the Upper, Lower and Pedal transmit channels are left
   out when External Zones are on. If that includes NRPN and drawbars on the
   Upper channel, nothing would be announced while External Zones are on.
   Worth checking first if the organ seems silent.
2. **Device ID default** (the p. 157 screenshot shows 0; the text gives only
   the range) and whether the organ answers Identity Request on all-call.
   p. 157 says the organ ignores SysEx with a different Device ID, which is
   why the app asks on all-call too and adopts the ID the organ answers with.
3. **Echoes**: does the organ send back a value it receives? (The app
   handles both.)
4. **Dump**: does a Dump Request get a reply; which check digit reading
   matches; does the organ wait for Acknowledge; packet numbering from 0 or 1.
   Save a snapshot (Command S) and keep it: with a few snapshots taken before
   and after known changes, the dump layout could be worked out, which would
   make Read from Organ show real values.
5. **Timing and throughput**: how fast the organ can take Data Sets (the
   slider sends one per step; a fast sweep on a huge range like tone wheel
   levels could flood it). Whether a small delay between messages is needed.
6. Every item in the "guessed" list above, especially vibrato mode order and
   the Pedal pipe part.
7. Whether VoiceOver speaks the app's announcements while it is in the
   background (Settings has a Mac-voice fallback for that case). This hasn't
   been tried with VoiceOver running.
8. Patch names and the dump (see "Changes in 1.2.0"), and whether Custom
   edits are sent at all in SysEx mode. A MIDI log from the organ answers
   most of it.
9. The XK-7D's USB MIDI port name, so the app recognises it on first launch.
   It matches anything containing "XK-7", "Hammond" or "Suzuki", in any case,
   with or without spaces and hyphens.

## Changes in 1.0.1 (independent review)

- Unplugging the organ is said once ("Organ disconnected"), and the app
  connects again by itself when the port comes back ("Organ connected
  again"). Before, it stayed attached to the old port and never reconnected,
  and every later MIDI setup change repeated "Organ disconnected". While the
  organ is gone, edits aren't pretended to be sent.
- An organ plugged in after launch is picked up if nothing was chosen (unless
  the person chose Disconnect).
- At launch a plugged-in organ beats a remembered simulator.
- A burst of more than 8 settings is spoken as one line with a count.
- Typing a value and pressing Return now confirms what was sent. VoiceOver
  says nothing when a text field is submitted, so it was silent before.
- Pressing Return in an empty name field no longer blanks the name on the
  organ. Typographic quotes and dashes in names become plain ASCII.
- Return in the search field with no matches says so.
- Home and End on a slider now tell VoiceOver the value changed.
- The Settings window rereads its values when opened and shows a learned
  Device ID. Before, it was built once and could write a stale Device ID back
  over the one learned from the organ.
- Vibrato mode order, see above.

## Changes in 1.0.2

- Command W (or the close button) hides the main window instead of quitting,
  and says "Window hidden. Still listening." Command 1, the Dock icon or
  opening the app again brings it back. Command Q quits.
- In Set Up Organ, the box that changes the organ's Upper send channel is off
  by default and says what it changes.
- If NRPN or drawbar messages arrive on a channel other than the app's Upper
  channel, the app says once per connection that the channels don't match
  and which channel to choose in Settings. It doesn't change anything by
  itself.

## 1.0.4: the launch crash

1.0.0 to 1.0.3 crashed at launch on every Mac except the one that built
them. The table was a SwiftPM resource read through `Bundle.module`, whose
generated code looks beside the .app (not in Contents/Resources) and then
in the build machine's `.build` folder, and calls fatalError when both
fail. On the Studio the `.build` folder was there, so every test and
Gatekeeper check passed.

Now the table is compiled in (`ParameterTable.swift`, written by the
generator; a test keeps it equal to `parameters.json`), Package.swift
declares no resources, and a table that can't be read gives a plain dialog
instead of a crash. `scripts/check-packaged.sh` (run by `release.sh`
before and after notarizing) fails if the binary names the build folder,
and runs the packaged app's self-test with `.build` moved out of reach.
Run against 1.0.3 it fails, with the same crash Matthew saw.

## Changes in 1.0.3 (picture pass)

The manual's menu screenshots and drawings were compared with the table.
They settled the EQ bass and middle frequencies, the preamp output level,
the Pedal contact count, the assign knob CC gap, which model the assign and
octave buttons apply to, and what two Patch Load items mean. The full list,
and what the pictures couldn't settle, is in docs/PARAMETER-REVIEW.md under
"Picture pass". Tests: `Tests/XK7DCoreTests/PicturePassTests.swift`.

Port choice lives in `XK7DCore/PortPolicy.swift` so it can be tested without
CoreMIDI; `Tests/XK7DCoreTests/ReviewFixTests.swift` covers it.

## Lost first message

On the first launch of a freshly built app, one message from the app to the
simulator's newly created virtual port was lost once (the other direction
worked). It never happened in tests or later runs. Now, when the simulator
starts, the session holds outgoing messages until the simulator answers an
Identity Request. It asks again every 0.3 s and, after about 3 s, sends
anyway rather than hold forever. Held messages go out with the Device ID the
reply carried. Unit tests cover this. It isn't used for the organ, which
might never answer and must still get your changes.

## Testing without disturbing the computer

- `XK7D_SELFTEST=/path/to/log`: runs a scripted session against the
  simulator, speaks nothing, writes what it would have said to the log, and
  quits. It doesn't save the port choice. The last line is
  "SELFTEST DONE 537 settings".
- `XK7D_SILENT=1`: normal app, no speech.
- `XK7D_SHOW=simulator:<parameter id>`: opens the simulator window and
  selects a setting.
- `swift tools/ax-inspect.swift <pid>` prints the accessibility tree and any
  unlabelled controls; `--increment` performs AXIncrement on the first
  slider.
- Launch with `open -g` so nothing comes to the front.
- `XK7D_UPDATE_TEST=/path/to/log`: the update rehearsal, test builds only
  (see Updates).
- Windows: `XK7DCompanion.exe --self-test LOG` is the silent self-test, and
  unlike the Mac's it checks its own results and exits 1 if a step didn't do
  what it should. `--ui-test` opens the real windows, silent, on the
  simulator. `XK7D_TEST_DIR` keeps settings in a scratch folder.
  `XK7D_SILENT=1` mutes speech.

## Not done

- Effect 1 and 2 parameters aren't named for each effect type (pp. 88-96).
- A saved snapshot can't be sent back to the organ.
- The expression pedal and damper aren't announced, on purpose: they'd be
  too chatty.
- The core has no user interface and builds for iOS, but there's no iPhone
  app.
- No Windows code signing certificate, so SmartScreen may warn.
- No Windows build for ARM. The x64 build should run under Windows on ARM's
  emulation; that hasn't been tried.

## Releasing

1. Change `VERSION`, commit and push. Wait for CI to pass.
2. Tag `vX.Y.Z` and push the tag. **Check `git log -1` shows the release
   commit before tagging** (Wavelength's 3.0.1 lesson). CI builds the Windows
   installer and attaches it to the release.
3. Write the release notes on the release page.
4. On the Studio, from the tagged commit: `scripts/release.sh`. It builds,
   signs, notarizes and staples the Mac app, checks the Windows installer on
   the release is byte for byte the one CI built and tested, signs both, writes
   and uploads `appcast.xml` and `appcast-windows.xml` with the Mac zip, then
   downloads them back and checks them, Gatekeeper included.

The Developer ID comes from the Keychain, and the App Store Connect key from
the Keychain entry `asc-api-key`. Nothing secret is in the repository or on
GitHub.

## Changes in 1.3.0

Matthew's ask: "maybe only announce the first time something is moved, but if
that same control is moved again, then the numbers get read out". So the first
time a control speaks you hear the full line ("Upper 8 foot: 6"); if the next
thing said is the same control again, you hear only the value ("4").

- **Where it lives.** `AnnouncementCoalescer` (Swift `Coalescer.swift`, C#
  `Decoding.cs`). `submit` takes an optional `valueOnly` line next to the full
  text; `dueLines(at:)` / `DueLines` returns each line as spoken plus its full
  text (`due` still returns the spoken texts). The coalescer remembers the key
  it spoke last and when. A line is value-only when the setting is on, the
  key is the one spoken last, less than `repeatQuietGap` (10 s, a constant)
  has passed since, and the change came with a value-only form.
- **The value-only text is built, never cut out of the full line.**
  `OrganSession.valueOnly(_:raw:)` / `ValueOnly` builds it from the same parts
  as `line`: the parameter's spoken value, or "on"/"off" for an Off/On
  setting. Drawbar CCs give the level, CC 1 "slow"/"fast"/"N percent", the CC
  switches "on"/"off", text settings the text or "blank". Patch changes,
  burst summaries and Leslie speed lines have no value-only form, so they're
  always full. The shared vectors now carry the value-only text of every
  setting at both ends of its range.
- **What brings the name back.** Any other line from the coalescer (another
  setting, a burst summary, a patch change), `flush()`, `OrganSession.speak`
  (status lines), the urgent Leslie line, and anything the app says itself:
  `AppModel` (both platforms) calls `coalescer.breakRepeat()` from the
  announcer's `onAnnounced` for every announcement that didn't come from the
  session. And 10 s without that control speaking.
- **A long sweep** speaks every `maxWait` (2 s); each of those interim lines
  is the same key, so the first says the name and the rest are numbers.
- **History and Repeat Last keep the full line.** `lastAnnouncement` holds
  the full text; the app passes it to `announce(_:historyText:)`, so Recent
  announcements and Repeat Last always say which control it was.
- **Setting:** "Say only the value when the same control moves again", on by
  default, saved as `sayValueOnlyOnRepeat`, a checkbox under "Speak drawbar
  changes" in Settings on both systems. `OrganSession.sayValueOnlyOnRepeat`
  passes it to the coalescer. Off says the full line every time, as 1.2.1 did.
- **Tests:** `ValueOnlyRepeatTests` in both languages (first full, repeat
  value only, another control in between, status and urgent lines, the app
  saying something, the quiet gap, a long sweep, setting off, bursts and patch
  changes, value-only forms built not cut, the coalescer alone). The
  integration scenario's knob sweep now expects "400 rpm" with the full line
  in `lastAnnouncement`. Both silent self-tests move the Upper 8 foot drawbar
  twice; the Windows one fails unless the second is said as a number alone.
  Swift 142 unit and 5 integration; C# 161.

## Changes in 1.2.1

Matthew asked to be able to turn off speech for drawbar moves only.
`OrganSession.speakDrawbars` (C# `SpeakDrawbars`), default on, saved as
`speakDrawbars`. Off, drawbar control changes and the drawbar registration
settings (00 00 01 0p 0n), on Upper, Lower and Pedal, are still tracked and
shown but not said; anything already waiting is dropped
(`AnnouncementCoalescer.cancel(keyPrefix:)`). Announcements menu, Speak
Drawbar Changes, Command Shift D (Control Shift D), says "Drawbar speech
off" or "on" even when muted. Also a checkbox in Settings. One switch, not
a set of categories: Leslie, patches and the rest stay on, and Mute covers
everything. Tests: `testDrawbarSpeechCanBeTurnedOff` in both languages.
Swift 132 unit and 5 integration; C# 151.

## Changes in 1.2.0 (first real-organ report)

Matthew's friend, who is sighted and hears the app through the Mac's voice
(no VoiceOver), is using it on a real XK-7D. His reports: "it's working
amazing", but patch changes said "F1, U2" and not the patch's name; Leslie
speed changes are announced; moving through the organ's menus says nothing;
adjusting the pedal harmonics says nothing.

### Patch names

What the manual says the organ sends on a patch change: Bank Select (CC 0 =
00 User, 01 Factory, 64-6D Favorite bank C-A; CC 32 always 00) then Program
Change (00-63 patch, 64-6D Favorite key, 7E/7F Adjust), p. 176, when Program
Change is On (p. 155). Nothing else is documented for a patch change. The
patch name is a parameter (Name Upper 00 00 10 00 00, Name Lower 00 00 10 00
01, 16 letters, p. 178) with **no NRPN**, so the organ can only send it as a
SysEx Data Set. **There is no single-parameter "Data Request" in the
manual's SysEx list** (p. 177): only Dump Request (07 Temporary: "the Patch
Parameters of the current Patch and the Adjust Presets", replies 07 and 08;
0A System). So:

1. **Factory patches** (bank 01, F00-F99) "cannot be changed" (p. 35), so
   their names come from the Factory Patches table (pp. 172-173), built in
   (`PatchNames.factoryUpper/Lower`). Upper uses the UPPER column; Lower and
   Pedal the LOWER and PEDAL column. Said at once: "Upper: Kinda Brian, F15".
   The table prints some names longer than 16 letters ("Principal Chorus +
   Mixture"), so the organ's own display may differ; we say the table's.
2. **User patches and Favorites** wait for a name (`OrganSession`
   `patchChanged`, `tickNames`):
   - If the organ sends the Name Data Set itself within the wait (it may, in
     SysEx mode, if a recall sends every parameter), that name is used and
     not said again on its own.
   - Otherwise, 0.15 s after the last patch change (so stepping through
     patches asks once), the app sends a Temporary Dump Request and reads the
     names out of the type 07 packets (`PatchNames.fromTemporaryDump`). **The
     dump layout isn't published**, so this looks for the two 16-letter names
     side by side (their addresses are neighbours): 32 printable bytes in a
     row, each half at least half letters or spaces, at least 3 letters. Our
     own request's packets are acknowledged and kept out of Read from Organ.
   - The line waits up to 1.2 s for that (0.3 s if not asking), then falls
     back to the last name learned for that slot this session, or the slot
     alone ("Upper: patch U05"). It is said once either way: the coalescer
     holds the line (`submit(holdUntil:)`) and `release` fills in the name,
     keeping its place.
   - If the organ answers no dump (or no names are found) twice on a
     connection, the app stops asking for that connection
     (`nameDumpState = .gaveUp`) so later changes aren't delayed.
   - Names are remembered per part and slot for the session, updated when
     the current patch is renamed from the app or a name arrives from the
     organ.
   - Adjust A#/B and unknown banks are said by slot only.
3. The simulator now puts the Upper and Lower names first in its Temporary
   dump (an invented layout), and its User patches carry the factory names
   until renamed (`userPatchNames`), as a new organ's do.

**To confirm on the organ** (the MIDI log shows all of it): whether the dump
arrives; whether the names are side by side in it, and whether they're
padded with spaces and carry the "U"/"L" marker; the organ's character for
the footage mark (we speak ´, ' and ’ after a number as "foot"); whether a
recall in SysEx mode sends the name by itself; whether Lower takes the
patch's Lower name; whether a dump request shows anything on the organ's
display (if it's a nuisance, Settings turns asking off).

### Speech

- Leslie: "Fast", "Slow" or "Stop", said at once and cutting off anything
  else (`onUrgentAnnouncement`), never coalesced. From p. 59: [FAST] on is
  Fast; off, it's Stop when [STOP] is lit, else Slow. [STOP] pressed while
  fast is said "Stop mode on/off". CC 92 is treated the same.
- Off/On settings are short: "Percussion on", "Leslie bypass off", not
  "Percussion on: On" (`OrganSession.line`).
- Mac voice (no VoiceOver): Settings has the voice (System voice follows
  Spoken Content through `prefersAssistiveTechnologySettings`), speed and
  loudness, and Say a Sample. Windows voice: the same through Prism's
  `set_voice`, `set_rate` and `set_volume`; Prism doesn't document ranges,
  so speed and loudness are scaled from the voice's own starting values.
  Untested on a real PC.
- With VoiceOver or a screen reader running, Automatic speaks only through
  it, as before.

### Things the organ doesn't send

- **Menu and page navigation.** The manual's MIDI implementation (pp.
  176-185) has no message for moving through the display; only parameter
  values, patch changes and controllers are transmitted. So the app can't
  follow the menus, only the values changed in them.
- **Custom settings in NRPN mode.** Every Custom set parameter (tone wheels,
  contacts, **pedal registration**, Leslie cabinets, pipes) and the patch
  names have no NRPN, so in NRPN mode (what the organ's MIDI templates set)
  they are never sent. The pedal harmonics the tester adjusted are the
  Custom Pedal Registration's sub drawbar levels (p. 118; p. 182, "Temporary Pedal", address 31 00 00
  0m 0s), which is this case. Set Up Organ switches Individual Parameters to
  SysEx. The app now says so once per connection when NRPN arrives before
  any Data Set (`onNRPNModeNoticed`). Whether the organ transmits Custom
  menu edits at all, even in SysEx mode, is unconfirmed.
- `EverySettingSpeaksTests` (both languages) sends every setting of all 537,
  every index sample, as a Data Set, and every NRPN setting as NRPN, and
  checks each is said exactly once. All are.

### The MIDI log

Help > Keep a MIDI Log (both systems) writes every message to and from the
organ, with a timestamp and a short description, to
`~/Library/Logs/XK-7D Companion/MIDI Log.txt` (Mac) or
`%APPDATA%\XK-7D Companion\Logs\MIDI Log.txt` (Windows). Notes, pitch
bend, expression (CC 11), damper (CC 64) and real-time bytes are counted, not
written. The app's own steps (asking for a name, what was found, the port,
addresses not in the table) are lines starting "---". Over 20 MB it becomes
"MIDI Log (previous).txt". Help > Show MIDI Log in Finder / Explorer.
`MIDILogger` is in the core, ported, and checked by the shared vectors.

Tests: Swift 131 unit and 5 integration; C# 150. Shared vectors now also
cover the factory names, patch lines, dump name reading, name cleaning, the
spoken line for every setting, and the MIDI log.

## Changes in 1.1.1 (independent review)

- **Choices send only when picked (Windows).** See "UI details" above. The
  Mac already worked this way: AppKit's popup button opens its menu on the
  arrow keys and only acts when an item is chosen. That's from AppKit's
  documented behavior, not from a key-press test, since tests here can't put
  a menu on screen. Both now say what they sent.
- **A value the manual doesn't list.** If the organ reports a value outside
  a setting's range, the slider shows it ("..., outside the manual's range")
  and won't step from it, like "not heard yet". A choice list shows it as
  "Unknown value N". Before, the slider snapped to the nearest end and the
  arrow keys sent from there. `Parameter.holds` / `Holds` in both cores.
- **"Sent" only when it was.** A port the app can only listen to (no MIDI
  output, or another program has the output) no longer gets "sent"
  confirmations. Both apps ask `PortPolicy.cannotSend` / `CannotSend`.
  After a failed send the Mac's controls now go back to what the organ has.
- **Windows MIDI input.** A broken SysEx message (`MIM_LONGERROR`) used to
  keep its input buffer; after 16 of them no SysEx would arrive. And a
  buffer from an earlier opening of the port could be handed back to WinMM
  after it was freed, when the port was reopened quickly with the same
  handle value. Each opening now has a number WinMM passes back.
- **Windows voice.** Prism's OneCore and SAPI backends were freed right after
  each speak call, which can cut the speech off. They're kept open now, as
  Wavelength keeps its own. Screen readers are still asked afresh each time.
- **Smaller things.** Choosing the Organ list's current port again reconnects
  if it isn't working (Windows). A second Read from Organ replaces the first
  (Windows). The update news waits its turn on the Mac too (VoiceOver's medium
  priority). Windows menu items have access keys. A Mac port that fails to
  connect is now said, not only shown.
- **Release check.** `release.sh` checks both published update lists with the
  public key the apps carry (`tools/verify-appcast.swift`): signature and
  length against the downloaded file.

Spot-checked 39 more table rows against the manual's page images (pp.
178-185, random sample). No mismatches.

## Changes in 1.1.0

- The Windows version (above).
- Updates on both systems (above).
- Typing a huge number into a value field no longer stops the Mac app.
- `CFBundleVersion` is now the version itself (it was a build number),
  because Sparkle compares it.
