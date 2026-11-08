# Hand-off notes

Version 1.0.2 has been tested against the built-in simulator only. It hasn't been
connected to a real XK-7D.

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
    anyway, then settles again.
  - `OrganSession.swift`: the heart. Decodes everything, keeps known values,
    sends changes by SysEx Data Set, hides echoes of its own changes (same
    value back within 2 s), produces announcement text, learns the organ's
    Device ID, collects and acknowledges dump packets. It also paces sends
    (a fast sweep is merged, latest value wins, at most one every 20 ms) and
    can hold sends until the other end answers an Identity Request (used for
    the simulator; see "Lost first message" below).
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
`scripts/build-app.sh` reads it from there.

## Writing to the organ

Every change goes out as a SysEx Data Set:
`F0 55 dd 10 26 13 [5 address bytes] [data] F7`. Two-byte values are two
7-bit bytes, MSB first. The manual says SysEx is received whatever the
Individual Parameters setting is. The app never sends anything unprompted
except an Identity Request when you connect (to the configured ID and to
all-call 7F).

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

Tests: 87 unit tests and 5 integration tests.

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
8. The XK-7D's USB MIDI port name, so the app recognises it on first launch.
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

## Testing without disturbing the Mac

- `XK7D_SELFTEST=/path/to/log`: runs a scripted session against the
  simulator, speaks nothing, writes what it would have said to the log, and
  quits. It doesn't save the port choice.
- `XK7D_SILENT=1`: normal app, no speech.
- `XK7D_SHOW=simulator:<parameter id>`: opens the simulator window and
  selects a setting.
- `swift tools/ax-inspect.swift <pid>` prints the accessibility tree and any
  unlabelled controls; `--increment` performs AXIncrement on the first
  slider.
- Launch with `open -g` so nothing comes to the front.

## Not done

- Effect 1 and 2 parameters aren't named for each effect type (pp. 88-96).
- A saved snapshot can't be sent back to the organ.
- The expression pedal and damper aren't announced, on purpose: they'd be
  too chatty.
- The core has no user interface and builds for iOS, but there's no iPhone
  app.

## Releasing

`scripts/release.sh` builds, signs with a Developer ID, notarizes, staples
and zips the app. It reads the signing identity and App Store Connect API key
from environment variables; nothing secret is in the repository.
