# XK-7D Companion

A Mac app for the Hammond XK-7D organ, made for players who use VoiceOver.
It speaks the changes you make on the organ. It also lets you see and change
the settings the manual's MIDI tables list, from the keyboard.

The XK-7D's deeper settings live behind a small display. The Owner's Manual
publishes a MIDI address for nearly every one of them, and this app is built
on that map.

**This app hasn't been tested with a real organ yet.** Everything follows the
manual, and the manual has gaps and a few contradictions. Read
[docs/PARAMETER-REVIEW.md](docs/PARAMETER-REVIEW.md) before relying on it.

It isn't made by, endorsed by or affiliated with Hammond or Suzuki.

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
  popup. Numbers use a slider, plus a box where you can type the value the way
  the organ shows it.
- **Doesn't guess.** The organ can't be asked for one setting's value. Until
  the organ reports a setting, or you set it from the app, it reads "not
  heard yet". The slider won't move from the keyboard until then, because the
  end of a range can be drastic (0 rpm stops the Leslie horn).
- **Includes a simulator** of the XK-7D, clearly labelled, so you can try it
  without an organ.

## Getting started

1. Connect the organ to the Mac with a USB cable and open the app. It picks a
   MIDI port whose name contains XK-7, Hammond or Suzuki. If it doesn't, pick
   the organ in the **Organ** popup. If you plug the organ in after opening
   the app, it connects when the organ shows up. If the cable comes out or the
   organ is turned off, the app says "Organ disconnected", and connects again
   when it's back.
2. Choose **Organ > Set Up Organ for This App** (Command Shift U). It offers
   four changes to the organ's MIDI settings, each with a checkbox. Nothing is
   sent until you choose Send to Organ. The one that matters most is
   Individual Parameters set to SysEx. Without it, settings that have no NRPN
   number (custom Leslie cabinets, custom tone wheels and patch names, among
   others) are never sent by the organ. To keep these settings after the
   organ is turned off, record the System settings on the organ (manual page
   142).
3. Play. Changes are spoken.

To change a setting from the Mac, press Command F and type part of its name,
or press Command L to go to the list. Right Arrow opens a category. Tab moves
to the editor for the selected setting. In a slider, the arrow keys step by
one. Page Up and Page Down move a tenth of the range. VoiceOver reads the
value as the organ's display shows it.

## Keys

| Key | Does |
|---|---|
| Command F | Search settings |
| Command L | Go to the settings list |
| Command R | Read from organ |
| Command Shift U | Set up organ for this app |
| Command Shift M | Mute or unmute announcements |
| Command Shift L | Repeat the last announcement |
| Command 1, Command 2 | Main window, simulator window |
| Command S | Save the last organ snapshot as a .syx file |
| Command comma | Settings |

Everything the app has spoken is listed under Recent announcements, at the
bottom of the main window.

## Settings

Announcements can go through VoiceOver or the Mac's own voice. Automatic uses
VoiceOver when it's running. There's also an option to use the Mac's voice
while the app is in the background, and a setting for how long a knob has to
rest before it's spoken.

## The simulator

Choose Built-in simulator in the Organ popup. If you quit while using it,
the app opens on the simulator next time, unless the organ is plugged in. It shows up as a real MIDI port
called "XK-7D Simulator (not a real organ)", so the app talks to it the same
way it would talk to the organ. Its window (Command 2) has buttons that act
like the organ's panel. It also logs what it received.

## Known limits

- **It can't read the organ's current settings.** The manual defines a memory
  dump, and Read from Organ asks for one, checks it and can save it as a .syx
  file. The manual doesn't describe what's inside a dump, though, so the app
  can't turn it into values.
- Some values are shown only by their end points, such as "step 12 of 36".
  The manual doesn't give the curve in between. This covers Leslie rise, fall
  and brake times, vibrato rate, EQ frequencies and contact delay.
- Effect 1 and Effect 2 parameters are numbered 1 to 8 rather than named for
  each effect type.
- The manual gives no MIDI for some actions, so the app can't record patches,
  use a USB stick, reset the organ or update firmware.
- It needs macOS 14 or later. So far it has only been run on macOS 26.

## Building

You need Xcode 26 or later.

    swift test                 # unit and integration tests
    scripts/build-app.sh       # builds "build/XK-7D Companion.app"

### The parameter table

`Sources/XK7DCore/Resources/parameters.json` holds the settings. It's
generated by `tools/generate_parameters.py`, which contains the manual's
table rows, transcribed by hand. Run it to rebuild the JSON:

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
    tools/                   table generator, manual cross-check, table printer, accessibility inspector
    docs/PARAMETER-REVIEW.md how the table was checked
    HANDOFF.md               how it fits together, and what needs a real organ

## License

MIT. See [LICENSE](LICENSE).
