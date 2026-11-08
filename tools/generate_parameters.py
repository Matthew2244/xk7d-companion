#!/usr/bin/env python3
"""Build Sources/XK7DCore/Resources/parameters.json from the XK-7 / XK-7D
Owner's Manual (V1.10), MIDI INFORMATION appendix, pages 178 to 185.

Every row below was transcribed by hand from the manual's tables and checked
against the page images (the text export drops sharps and loses table columns
on some pages). The address strings are written exactly as the manual prints
them, placeholders included ("3x", "4b", "0p", "tt" ...). The generator expands
the small placeholders (zones, banks) into separate parameters and keeps the
large ones (tone wheel numbers, keys, footages) as index dimensions the app
shows as pickers.

Run:  python3 tools/generate_parameters.py
Then: python3 tools/verify_against_manual.py   (cross-checks every row against
      reference/manual.txt)

Conventions in the value shorthand (third-from-last column of each row):
  onoff                    00 Off, 01 On
  enum:A|B|C               00 A, 01 B, 02 C
  int:LO-HI                raw hex range shown as the plain number
  num:LO-HI:ZERO:ORIGIN:STEP:DEC:UNIT[:plus]
                           shown = ORIGIN + (raw - ZERO) * STEP (hex raws)
  steps:LO-HI:low text:high text
                           the manual gives only the end points; the curve in
                           between is not published, so we show "step N"
  sint14:LO..HI[:UNIT]     two-byte signed, 40 00 = 0 (e.g. 3F 7E = -2)
  note                     00-7F note number, named the way the display does
                           (note 60 = 3C, note 0 = -2C)
  pan                      00-40-7F  L64 - Center - R63
  chan16off                00-10  1-16, Off
  text16                   16 ASCII characters
  db1041                   0 -inf, 1..1041 = -100.0 .. +4.0 dB (0.1 dB steps)
  db193                    0 -inf, 1..193 = -92.0 .. +4.0 dB (0.5 dB steps)
  db77                     0 -inf, 1..77  = -76 .. 0 dB (1 dB steps)
  special forms are spelled out where used.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "Sources", "XK7DCore", "Resources", "parameters.json")

FOOT9 = ["16'", "5 1/3'", "8'", "4'", "2 2/3'", "2'", "1 3/5'", "1 1/3'", "1'"]
FOOT_SPOKEN = {"16'": "16 foot", "5 1/3'": "5 and a third foot", "8'": "8 foot", "4'": "4 foot",
               "2 2/3'": "2 and two thirds foot", "2'": "2 foot", "1 3/5'": "1 and three fifths foot",
               "1 1/3'": "1 and a third foot", "1'": "1 foot", "32'": "32 foot"}
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
BANKS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A"]


def h(s):
    return int(s, 16)


# ----------------------------------------------------------------- values --

def onoff():
    return {"type": "enum", "options": [[0, "Off"], [1, "On"]]}


def enum(labels, start=0):
    return {"type": "enum", "options": [[start + i, l] for i, l in enumerate(labels)]}


def number(lo, hi, zero=None, origin=None, step=1, dec=0, unit="", plus=False, special=None):
    if zero is None:
        zero = lo
    if origin is None:
        origin = zero
    v = {"type": "number", "min": lo, "max": hi, "zero": zero, "origin": origin,
         "step": step, "decimals": dec, "unit": unit, "plus": plus}
    if special:
        v["special"] = [[k, s] for k, s in special]
    return v


def parse_value(spec):
    if spec == "onoff":
        return onoff()
    if spec.startswith("enum:"):
        return enum(spec[5:].split("|"))
    if spec.startswith("int:"):
        lo, hi = spec[4:].split("-")
        return number(h(lo), h(hi), zero=0, origin=0)
    if spec.startswith("num:"):
        parts = spec[4:].split(":")
        lo, hi = parts[0].split("-")
        zero, origin, step, dec, unit = h(parts[1]), float(parts[2]), float(parts[3]), int(parts[4]), parts[5]
        plus = len(parts) > 6 and parts[6] == "plus"
        return number(h(lo), h(hi), zero, origin, step, dec, unit, plus)
    if spec.startswith("steps:"):
        _, rng, low, high = spec.split(":")
        lo, hi = rng.split("-")
        return {"type": "steps", "min": h(lo), "max": h(hi), "low": low, "high": high}
    if spec.startswith("sint14:"):
        parts = spec[7:].split(":")
        lo, hi = [int(x) for x in parts[0].split("..")]
        unit = parts[1] if len(parts) > 1 else ""
        return number(0x2000 + lo, 0x2000 + hi, 0x2000, 0, 1, 0, unit, True)
    if spec == "note":
        return {"type": "note", "min": 0, "max": 127}
    if spec == "pan":
        return {"type": "pan", "min": 0, "max": 127, "center": 64, "left": "L%d", "right": "R%d", "centerLabel": "Center"}
    if spec == "chorusmix":
        return {"type": "pan", "min": 0, "max": 127, "center": 64, "left": "D%d", "right": "%dV", "centerLabel": "Even"}
    if spec == "chan16off":
        return number(0, 16, 0, 1, 1, 0, "", special=[(16, "Off")])
    if spec == "chan16":
        return number(0, 15, 0, 1)
    if spec == "text16":
        return {"type": "text", "length": 16}
    if spec == "db1041":
        return number(0, 1041, 1, -100.0, 0.1, 1, "dB", True, special=[(0, "-inf")])
    if spec == "db193":
        return number(0, 193, 1, -92.0, 0.5, 1, "dB", True, special=[(0, "-inf")])
    if spec == "db77":
        return number(0, 77, 1, -76, 1, 0, "dB", True, special=[(0, "-inf")])
    if spec == "gain9":
        return number(0, 0x12, 9, 0, 1, 0, "", True)
    if spec == "len1to10":
        return number(0, 9, 0, 1)
    if spec == "custom8":
        return enum(["U1", "U2", "U3", "U4", "F1", "F2", "F3", "F4"])
    if spec == "custom6":
        return enum(["U1", "U2", "U3", "F1", "F2", "F3"])
    if spec in SPECIAL:
        return SPECIAL[spec]()
    raise ValueError("unknown value spec " + spec)


def knob_functions(last_b):
    labels = ["Off", "Keyclick Level", "Leakage Level", "Tone Control Value", "TR Vibrato Rate",
              "Tremulant Rate", "Sustain Length U", "Sustain Length L", "Sustain Length P",
              "Pitch Bend", "Expression", last_b,
              "EXZ U1 Volume", "EXZ U1 Pan", "EXZ U2 Volume", "EXZ U2 Pan", "EXZ U3 Volume", "EXZ U3 Pan",
              "EXZ L1 Volume", "EXZ L1 Pan", "EXZ L2 Volume", "EXZ L2 Pan", "EXZ P Volume", "EXZ P Pan",
              "EXZ U1 CC", "EXZ U2 CC", "EXZ U3 CC", "EXZ L1 CC", "EXZ L2 CC", "EXZ P1 CC"]
    # The table heads this "00 - 17" but lists entries up to 1D. We follow the list.
    return enum(labels)


def button_functions():
    return enum(["Off", "Sustain U", "Sustain L", "Sustain P", "Damper", "Sostenuto", "TW Brake", "Spring",
                 "EXZ U1 On", "EXZ U2 On", "EXZ U3 On", "EXZ L1 On", "EXZ L2 On", "EXZ P On"])


def knob_cc():
    # Page 179. Raw value -> the controller number it sends, with the manual's name.
    rows = [(0, 1, "Modulation"), (1, 2, "Breath"), (2, 3, "Undefined"), (3, 4, "Foot Controller"),
            (4, 5, "Portamento Time"), (5, 8, "Balance"), (6, 9, "Undefined"), (7, 12, "Effect Ctrl 1"),
            (8, 13, "Effect Ctrl 2"), (9, 14, "Undefined"), (0xA, 15, "Undefined")]
    rows += [(0xB + i, 16 + i, "VCont %d" % (i + 1)) for i in range(4)]
    rows += [(0xF + i, 20 + i, "Undefined") for i in range(12)]
    rows += [(0x1B, 65, "Portamento")]
    rows += [(0x1C + i, None, None) for i in range(4)]  # not listed in the manual
    rows += [(0x20, 70, "Sound Variation"), (0x21, 71, "Resonance"), (0x22, 72, "Release Time"),
             (0x23, 73, "Attack Time"), (0x24, 74, "Cutoff Freq")]
    rows += [(0x25 + i, 75 + i, "Undefined") for i in range(9)]
    rows += [(0x2E, 84, "Portamento Ctrl")]
    rows += [(0x2F + i, 85 + i, "Undefined") for i in range(6)]
    rows += [(0x35, 91, "Reverb Send"), (0x36, 92, "Leslie Fast"), (0x37, 93, "Chorus Send"),
             (0x38, 94, "Delay Send"), (0x39, 95, "Phaser Send")]
    rows += [(0x3A + i, 102 + i, "Undefined") for i in range(18)]
    opts = []
    for raw, cc, name in rows:
        if cc is None:
            opts.append([raw, "Value %02X (not listed in the manual)" % raw])
        else:
            opts.append([raw, "CC %d %s" % (cc, name)])
    assert [o[0] for o in opts] == list(range(0, 0x4C)), "knob CC table must cover 00-4B"
    return {"type": "enum", "options": opts}


def foot_switch():
    labels = ["Off", "Leslie S/F Alt", "Leslie S/F Mom", "Leslie S/F Tri", "TW Brake", "Patch Fwd",
              "Patch Back", "Favorite Fwd", "Favorite Back", "Spring Shock", "Delay Time", "Damper",
              "Sostenuto", "Sustain", "Pedal To Lower", "ProChord"]
    for i in range(25):  # 10-28: Bass 1C - 3C
        n = i
        labels.append("Bass %d%s" % (1 + n // 12, NOTE_NAMES[n % 12]))
    labels += ["To Adjust A#", "To Adjust B"]
    assert len(labels) == 0x2B
    return enum(labels)


def patch_numbers():
    opts = [[i, "U%02d" % i] for i in range(100)] + [[100 + i, "F%02d" % i] for i in range(100)]
    return {"type": "enum", "options": opts}


def pipe_stops():
    stops = ["C-Open Diapason", "C-Principal", "C-Diapason", "C-Bourdon 1", "C-Bourdon 2", "C-Gedeckt",
             "C-Rohr Flute", "C-Flute Harmonic", "C-Flautino", "C-Voix Celeste II", "C-Clarinet",
             "C-Hautbois", "C-Oboe", "C-Vox Humana", "C-Trompette", "C-Cornet V", "C-Mixture III",
             "C-Mixture IV", "C-Sesquialtera II", "C-Reserved 1", "C-Reserved 2", "T-Tibia Clausa",
             "T-Brass Saxophone", "T-Brass Trumpet", "T-Clarinet", "T-English PostHorn",
             "T-Orchestral Oboe", "T-Style D Trumpet", "T-Viol d'Orchestre", "T-Vox Humana",
             "T-Viol Celeste", "T-Reserved 1", "T-Reserved 2", "P-ConVln 32' & Brdn 16'",
             "P-ConBmb 32' & Prn 16'", "P-ConBrdn 32' & Flte 16'", "P-Trompette 16'", "P-Fagott 16'",
             "P-SubBs 16' & Gedeckt 8'", "P-Diapason 8' & Flute 4'", "P-PrnChors 8' + Mixt IV",
             "P-Tibia 16' & Flute 8'", "P-Diap 16' & PostHorn", "P-Cornopean", "P-Reserved 1",
             "P-Reserved 2"]
    assert len(stops) == 46
    return {"type": "enum", "options": [[i, "S%02d %s" % (i + 1, s)] for i, s in enumerate(stops)]}


def leslie_fast():
    # 00 00, 00 01 - 02 2D: two 7-bit bytes, so 02 2D = 2*128 + 45 = 301.
    return number(0, 301, 1, 200, 1, 0, "rpm", special=[(0, "0 rpm")])


def leslie_slow():
    return number(0, 101, 1, 20, 1, 0, "rpm", special=[(0, "0 rpm")])


def stop_angle():
    # 02 67 = 2*128 + 103 = 359; 02 68 = 360 means Random.
    return number(0, 360, 0, 0, 1, 0, "degrees", special=[(360, "Random")])


SPECIAL = {
    "knob_xk7": lambda: knob_functions("Modulation"),
    "knob_xk7d": lambda: knob_functions("Leslie Speed"),
    "buttons": button_functions,
    "knob_cc": knob_cc,
    "footswitch": foot_switch,
    "patchnum": patch_numbers,
    "pipestop": pipe_stops,
    "leslie_fast": leslie_fast,
    "leslie_slow": leslie_slow,
    "stop_angle": stop_angle,
    # 03 2E - 03 38 - 03 42 are two 7-bit bytes: 3*128+46 = 430 ... 450. The raw value is the pitch in Hz.
    "master_tune": lambda: number(430, 450, 430, 430, 1, 0, "Hz"),
    "brake_range": lambda: number(0x28, 0x4C, 0x40, 0, 1, 0, "semitones", True),
    "brake_time": lambda: number(0, 0x31, 0, 0.1, 0.1, 1, "sec"),
    "exp_level": lambda: number(0, 0x29, 1, -40, 1, 0, "dB", True, special=[(0, "Off")]),
    "mic_center": lambda: number(0x0E, 0x72, 0x40, 0, 1, 0, "cm", True),
    # 00 1E - 01 48 = 30 ... 200 (two 7-bit bytes). Shown as 0-170 cm like the menu page.
    "mic_distance": lambda: number(30, 200, 30, 0, 1, 0, "cm"),
    "stereo_image": lambda: number(0, 0x7F, 0, 0, 1, 0, "", special=[(0, "Mono")]),
    "leslie_delay": lambda: number(0, 5, 0, 0.0, 0.2, 1, "sec"),
    "decay_pedal": lambda: number(0, 0x0A, 0, 1, 1, 0, "", special=[(0x0A, "Continue")]),
    "sounding_point": lambda: enum(["Patch", "1", "2", "3", "4", "5", "6", "Velocity"]),
    "vibrato_mode": lambda: enum(["V-1", "C-1", "V-2", "C-2", "V-3", "C-3"]),
    "custom_cabinet": lambda: enum(["U%d" % i for i in range(1, 11)] + ["F%d" % i for i in range(1, 11)]),
    "velocity_curve": lambda: enum(["Off", "1 (hard)", "2", "3", "4 (easy)"]),
    "exz_cc": lambda: enum(["Off", "7 (Volume)", "11 (Expression)"]),
    "pitch_up": lambda: number(0, 0x0C, 0, 0, 1, 0, "semitones"),
    "pitch_down": lambda: number(0, 0x18, 0, 0, 1, 0, "semitones"),
    "brightness": lambda: number(0, 9, 0, 1),
    "pedal_sub_level": lambda: number(0, 8, 0, 0),
    # Fold-back key points: the menu shows keys 1C-2C and 4G-5C (p. 109); the MIDI table counts the same 13 and 6 steps.
    "tw_lowest": lambda: enum(["%d%s" % (1 + i // 12, NOTE_NAMES[i % 12]) for i in range(13)]),
    "tw_highest": lambda: enum(["4G", "4G#", "4A", "4A#", "4B", "5C"]),
    # Percussion decay: menu "1 - 24, Cont" (p. 85) is exactly the 25 raw values 00-18.
    "perc_decay": lambda: number(0, 0x18, 0, 1, 1, 0, "", special=[(0x18, "Cont")]),
    "program128": lambda: number(0, 0x7F, 0, 1),
    "hold_ms": lambda: number(0, 0x0A, 0, 0, 10, 0, "ms"),
    "formant_phase": lambda: number(0, 359, 0, 0, 1, 0, "degrees"),  # 02 67 = 359
    "contact_leaf": lambda: number(0, 5, 0, 1),
    "pipe_footage": lambda: enum(["32'", "16'", "5 1/3'", "8'", "4'", "2 2/3'", "2'", "1 3/5'", "1 1/3'", "1'"]),
    "cent50": lambda: number(0x2000 - 50, 0x2000 + 50, 0x2000, 0, 1, 0, "cents", True),
    "cutoff": lambda: number(0x2000 - 127, 0x2000, 0x2000, 0, 1, 0, "", True),
    "exp_min": lambda: number(0, 0x3F, 0, 0),
    "exp_max": lambda: number(0x40, 0x7F, 0, 0),
    "drawbar": lambda: number(0, 8, 0, 0),
}

# ----------------------------------------------------------------- indices --


def wheels108():
    o = [[i, "#%02d" % (i + 1)] for i in range(12)]
    o += [[0x0C + i, "#F%02d" % (i + 1)] for i in range(12)]
    o += [[0x18 + i, "#%02d" % (13 + i)] for i in range(79)]
    o += [[0x67 + i, "#F%02d" % (92 + i)] for i in range(5)]
    assert len(o) == 108 and o[-1][0] == 0x6B and o[0x66][1] == "#91"
    return o


def wheels96():
    o = [[i, "#%02d" % (i + 1)] for i in range(12)]
    o += [[0x0C + i, "#%02d" % (13 + i)] for i in range(79)]
    o += [[0x5B + i, "#F%02d" % (92 + i)] for i in range(5)]
    assert len(o) == 96 and o[0x5A][1] == "#91" and o[-1][0] == 0x5F
    return o


def keys61():
    o = []
    for n in range(61):
        name = "%d%s" % (n // 12 + 1, NOTE_NAMES[n % 12])  # the display names keys "1C" to "6C" (p. 109)
        if n == 0:
            name += " (lowest C)"
        elif n == 24:
            name += " (middle C)"
        elif n == 60:
            name += " (highest C)"
        o.append([n, name])
    return o


def foot_opts(kind):
    if kind == "manual":
        return [[i, f] for i, f in enumerate(FOOT9)]
    if kind == "manual8":
        return [[i, f] for i, f in enumerate(FOOT9[:8])]
    if kind == "perc_leak":
        return [[3, "Second"], [4, "Third"]]
    if kind == "perc01":
        return [[0, "Second"], [1, "Third"]]
    if kind == "pedal_pairs":
        o = []
        for main_i, main in enumerate(["16'", "8'"]):
            for k, sub in enumerate(FOOT9[:8]):
                o.append([main_i * 8 + k, "%s-%s" % (main, sub)])
        return o
    if kind == "pedal2":
        return [[0, "16'"], [1, "8'"]]
    raise ValueError(kind)


def favorite_keys():
    return [[b * 10 + k, "%s-%s" % (BANKS[b], BANKS[k])] for b in range(10) for k in range(10)]


def dim(name, pos, options):
    return {"name": name, "position": pos, "options": options}


# ----------------------------------------------------------------- tables --
# Each row: (manual category, manual parameter name, display name, nrpn "MM LL" or "--",
#            sysex address as printed, length (hex as printed), value spec, page, help, extras)
# extras: dict with optional "notes" (caveat shown to the user), "indices", "xk7only".

ROWS = []


def row(cat, mname, name, nrpn, addr, length, value, page, help_text="", **extra):
    ROWS.append(dict(cat=cat, mname=mname, name=name, nrpn=nrpn, addr=addr, length=length,
                     value=value, page=page, help=help_text, extra=extra))


# --- PATCH PARAMETERS, p.178 ---------------------------------------------------
row("Name Upper", "Name Upper", "Patch name, upper", "--", "00 00 10 00 00", "10", "text16", 178,
    "The name of the current Upper patch, up to 16 letters.")
row("Name Lower", "Name Lower", "Patch name, lower", "--", "00 00 10 00 01", "10", "text16", 178,
    "The name of the current Lower patch, up to 16 letters.")
IZ = "Internal Zones"
row(IZ, "Octave Upper", "Upper octave shift", "1A 00", "00 00 00 1A 00", "02", "sint14:-2..2:octaves", 178)
row(IZ, "Split On", "Split on", "1A 01", "00 00 00 1A 01", "01", "onoff", 178,
    "Splits the keyboard into Lower and Upper. XK-7 only.", xk7only=True)
row(IZ, "Split Point", "Split point", "1A 02", "00 00 00 1A 02", "01", "note", 178,
    "The key where the split happens. XK-7 only.", xk7only=True)
row(IZ, "Octave Split Lower", "Lower octave shift when split", "1E 00", "00 00 00 1E 00", "02", "sint14:-2..2:octaves", 178)
row(IZ, "Octave Real Lower", "Lower octave shift", "1E 01", "00 00 00 1E 01", "02", "sint14:-2..2:octaves", 178)
row(IZ, "Pedal to Lower On", "Pedal to Lower on", "1E 02", "00 00 00 1E 02", "01", "onoff", 178,
    "Plays the Pedal part from the lower keys.")
row(IZ, "Pedal to Lower Mode", "Pedal to Lower mode", "1E 03", "00 00 00 1E 03", "01", "enum:Lowest|Chord|Poly", 178)
row(IZ, "Pedal to Lower Upper Limit", "Pedal to Lower top key", "1E 04", "00 00 00 1E 04", "01", "note", 178)
row(IZ, "Octave Pedal", "Pedal octave shift", "21 00", "00 00 00 21 00", "02", "sint14:-2..2:octaves", 178)
row(IZ, "Lower to Pedal On", "Lower to Pedal on", "21 01", "00 00 00 21 01", "01", "onoff", 178)
row(IZ, "Lower to Pedal Upper Limit", "Lower to Pedal top key", "21 02", "00 00 00 21 02", "01", "note", 178)

EXZ = "External Zones"
EXZ_ROWS = [
    ("Octave", "octave shift", "05", "02", "sint14:-2..2:octaves", ""),
    ("Transpose", "transpose", "06", "02", "sint14:-6..6:semitones", ""),
    ("On", "on", "00", "01", "onoff", ""),
    ("MIDI Channel", "MIDI channel", "01", "01", "chan16", ""),
    ("Bank Select MSB", "bank select MSB", "02", "01", "int:00-7F", ""),
    ("Bank Select LSB", "bank select LSB", "03", "01", "int:00-7F", ""),
    ("Program Change", "program change", "04", "01", "program128", "Shown 1 to 128, as on the organ's display (p. 103)."),
    ("Key Range Low", "lowest key", "07", "01", "note", ""),
    ("Key Range High", "highest key", "08", "01", "note", ""),
    ("Volume", "volume", "09", "01", "int:00-7F", ""),
    ("Pan", "pan", "0A", "01", "pan", ""),
    ("Velocity Curve", "velocity curve", "0B", "01", "velocity_curve", ""),
    ("Damper Enable", "damper", "0C", "01", "onoff", ""),
    ("Expression Enable", "expression", "0D", "01", "onoff", ""),
    ("Expression Minimum", "expression minimum", "0E", "01", "exp_min", ""),
    ("Expression Maximum", "expression maximum", "0F", "01", "exp_max", ""),
    ("Expression CC", "expression controller", "10", "01", "exz_cc", ""),
]
for mname, short, lsb, length, spec, hlp in EXZ_ROWS:
    row(EXZ, mname, short, "3x " + lsb, "00 00 00 3x " + lsb, length, spec, 178, hlp,
        expand={"x": [(0, "Upper 1"), (1, "Upper 2"), (2, "Upper 3"), (3, "Lower 1"), (4, "Lower 2"), (5, "Pedal")]},
        expand_format="External zone {label}: {name}", expand_category="External zone {label}")

CU = "Control Upper"
row(CU, "TW Brake Range", "Tone wheel brake range", "18 00", "00 00 00 18 00", "01", "brake_range", 178,
    "How far the pitch drops or rises when the tone wheel brake is used.",
    notes="The manual's data column reads 34-64-4C, which does not match its own -24 to +12 semitones. "
          "This app uses 28-40-4C (-24, 0, +12), which matches the menu page (p. 100). Confirm on the organ.")
row(CU, "TW Brake Time", "Tone wheel brake time", "18 01", "00 00 00 18 01", "01", "brake_time", 178)
row(CU, "TW Brake Amp", "Tone wheel brake volume change", "18 02", "00 00 00 18 02", "01", "onoff", 178)
row(CU, "Damper Enable Upper", "Damper on Upper", "18 03", "00 00 00 18 03", "01", "onoff", 178)
row(CU, "Pitch Bend Up", "Pitch bend up range", "18 04", "00 00 00 18 04", "01", "pitch_up", 178)
row(CU, "Pitch Bend Down", "Pitch bend down range", "18 05", "00 00 00 18 05", "01", "pitch_down", 178)
row(CU, "ProChord Mode", "ProChord mode", "18 06", "00 00 00 18 06", "01", "enum:Off|Close|Open", 178)
row("Control Lower", "Damper Enable Lower", "Damper on Lower", "1D 01", "00 00 00 1D 01", "01", "onoff", 178)
row("Control Pedal", "Damper Enable Pedal", "Damper on Pedal", "20 00", "00 00 00 20 00", "01", "onoff", 178)
KNOB_NOTE = ("The manual heads this range 00-17 but its list goes on to 1D (the EXZ CC choices). "
             "All listed choices are offered.")
CA7 = "Control Assignable (XK-7)"
for i in range(3):
    row(CA7, "Knob %d (XK-7)" % (i + 1) if i == 0 else "Knob %d" % (i + 1), "XK-7 assign knob %d" % (i + 1),
        "19 %02X" % i, "00 00 00 19 %02X" % i, "01", "knob_xk7", 178,
        "What ASSIGN knob %d does, on the single-manual XK-7." % (i + 1), xk7only=True, notes=KNOB_NOTE)
for i in range(3):
    row(CA7, "Button %d" % (i + 1), "Assign button %d" % (i + 1), "19 %02X" % (3 + i), "00 00 00 19 %02X" % (3 + i),
        "01", "buttons", 178, "What ASSIGN button %d does." % (i + 1),
        notes="The manual heads this table 'XK-7', but the specification (p. 188) says the assign buttons "
              "are on the XK-7D only.")
CA = "Control Assignable (XK-7D and XK-7D)"
for i in range(3):
    row(CA, "Knob %d" % (i + 1), "Assign knob %d function" % (i + 1), "19 %02X" % (6 + i), "00 00 00 19 %02X" % (6 + i),
        "01", "knob_xk7d", 179, "What ASSIGN knob %d controls." % (i + 1), notes=KNOB_NOTE)
CC = "Control Assignable CC (Control Change)"
for i in range(3):
    row(CC, "Knob %d" % (i + 1), "Assign knob %d controller number" % (i + 1), "19 %02X" % (9 + i),
        "00 00 00 19 %02X" % (9 + i), "01", "knob_cc", 179,
        "Which MIDI controller ASSIGN knob %d sends to the external zones." % (i + 1))

DU = "Drawbars Upper"
row(DU, "Octave", "Upper drawbars octave", "10 00", "00 00 00 10 00", "02", "sint14:-2..2:octaves", 179)
row(DU, "Key Range Low", "Upper lowest key", "10 01", "00 00 00 10 01", "01", "note", 179)
row(DU, "Key Range High", "Upper highest key", "10 02", "00 00 00 10 02", "01", "note", 179)
row(DU, "Loudness", "Upper loudness", "10 03", "00 00 00 10 03", "01", "int:00-7F", 179)
row(DU, "Organ Type", "Organ type", "10 04", "00 00 00 10 04", "01", "enum:Tone Wheel|Mellow|Vx.|Farf.|Ace.|Pipe", 179,
    "Tone Wheel, Mellow, the transistor organs Vx., Farf. and Ace., or Pipe.",
    notes="The table heads the range 00-04 but lists 05: Pipe as well; Pipe is included.")
row(DU, "Key Click Level", "Key click level", "10 05", "00 00 00 10 05", "01", "int:00-7F", 179)
row(DU, "Leakage Level", "Leakage level", "10 06", "00 00 00 10 06", "01", "int:00-7F", 179)
row(DU, "Custom TW", "Custom tone wheel set", "10 07", "00 00 00 10 07", "01", "custom8", 179)
row(DU, "Custom Contact", "Custom contact set", "10 08", "00 00 00 10 08", "01", "custom6", 179)
row(DU, "Custom Pipe", "Custom pipe set", "10 09", "00 00 00 10 09", "01", "custom8", 179)
row(DU, "Sustain Upper On", "Upper sustain on", "10 0A", "00 00 00 10 0A", "01", "onoff", 179)
row(DU, "Sustain Upper Length", "Upper sustain length", "10 0B", "00 00 00 10 0B", "01", "len1to10", 179)
row(DU, "Impedance Reduction", "Impedance reduction", "10 0C", "00 00 00 10 0C", "01", "onoff", 179)
DL = "Drawbars Lower"
row(DL, "Octave", "Lower drawbars octave", "1B 00", "00 00 00 1B 00", "02", "sint14:-2..2:octaves", 179)
row(DL, "Key Range Low", "Lower lowest key", "1B 01", "00 00 00 1B 01", "01", "note", 179)
row(DL, "Key Range High", "Lower highest key", "1B 02", "00 00 00 1B 02", "01", "note", 179)
row(DL, "Sustain Lower On", "Lower sustain on", "1B 03", "00 00 00 1B 03", "01", "onoff", 179)
row(DL, "Sustain Lower Length", "Lower sustain length", "1B 04", "00 00 00 1B 04", "01", "len1to10", 179)
DP = "Drawbars Pedal"
row(DP, "Octave", "Pedal drawbars octave", "1F 00", "00 00 00 1F 00", "02", "sint14:-2..2:octaves", 179)
row(DP, "Key Range Low", "Pedal lowest key", "1F 01", "00 00 00 1F 01", "01", "note", 179)
row(DP, "Key Range High", "Pedal highest key", "1F 02", "00 00 00 1F 02", "01", "note", 179)
row(DP, "Key Click Mode", "Pedal key click", "1F 03", "00 00 00 1F 03", "01", "enum:Off|U&L", 179)
row(DP, "Custom Sub Drawbars", "Custom pedal registration set", "1F 04", "00 00 00 1F 04", "01", "custom8", 179)
row(DP, "Key Mode", "Pedal key mode", "1F 05", "00 00 00 1F 05", "01", "enum:Mono|Poly", 179)
row(DP, "Sustain Pedal On", "Pedal sustain on", "1F 07", "00 00 00 1F 07", "01", "onoff", 179)
row(DP, "Sustain Pedal Length", "Pedal sustain length", "1F 08", "00 00 00 1F 08", "01", "len1to10", 179)
row(DP, "Decay Pedal Length", "Pedal decay length", "1F 09", "00 00 00 1F 09", "01", "decay_pedal", 179)
row(DP, "Effects", "Pedal through effects", "1F 0A", "00 00 00 1F 0A", "01", "onoff", 179)
PC = "Percussion"
row(PC, "On", "Percussion on", "11 00", "00 00 00 11 00", "01", "onoff", 179)
row(PC, "Harmonic", "Percussion harmonic", "11 01", "00 00 00 11 01", "01", "enum:Second|Third", 179)
row(PC, "Fast Decay", "Percussion decay", "11 02", "00 00 00 11 02", "01", "enum:Slow|Fast", 179)
row(PC, "Volume Soft", "Percussion volume", "11 03", "00 00 00 11 03", "01", "enum:Normal|Soft", 179)
row(PC, "Level at Normal", "Percussion level, normal", "11 04", "00 00 00 11 04", "01", "int:00-7F", 179,
    "0 to 127. The menu shows this as -22.0 to +10.5 dB; the steps in between are not published.")
row(PC, "Level at Soft", "Percussion level, soft", "11 05", "00 00 00 11 05", "01", "int:00-7F", 179,
    "0 to 127. The menu shows this as -22.0 to +10.5 dB; the steps in between are not published.")
PERC_DECAY_NOTE = ("The MIDI table gives 00-18 (0 - 24); the menu shows 1 to 24 and Cont (p. 85), "
                   "the same 25 values. This app shows the menu's names.")
row(PC, "Decay at Slow", "Percussion decay time, slow", "11 06", "00 00 00 11 06", "01", "perc_decay", 179,
    "Higher is a slower decay. Cont holds the percussion as long as the key is held.", notes=PERC_DECAY_NOTE)
row(PC, "Decay at Fast", "Percussion decay time, fast", "11 07", "00 00 00 11 07", "01", "perc_decay", 179,
    "Higher is a slower decay. Cont holds the percussion as long as the key is held.", notes=PERC_DECAY_NOTE)
row(PC, "Drive Level", "Percussion drive", "11 08", "00 00 00 11 08", "01", "int:00-7F", 179)
row(PC, "Touch", "Percussion touch", "11 09", "00 00 00 11 09", "01", "onoff", 179)
row(PC, "1’ Cancel", "Percussion 1 foot cancel", "11 0A", "00 00 00 11 0A", "01", "onoff", 179)
row(PC, "Drawbar Level", "Drawbar level with percussion", "11 0B", "00 00 00 11 0B", "01", "enum:0|Soft", 179)

# Registration, p.180 (SysEx only)
for part, b3, foots in (("Upper", "01", FOOT9), ("Lower", "02", FOOT9), ("Pedal", "03", ["16'", "8'"])):
    for i, f in enumerate(foots):
        row("Registration " + part, f.replace("'", "´"), "%s %s" % (part, FOOT_SPOKEN[f]), "--",
            "00 00 01 %s %02X" % (b3, i), "01", "drawbar", 180,
            "The %s %s drawbar, 0 to 8." % (part, FOOT_SPOKEN[f]))

AN = "Animation Upper & Lower"
row(AN, "Vibrato Upper", "Vibrato Upper", "12 00", "00 00 00 12 00", "01", "onoff", 180)
row(AN, "Vibrato Mode", "Vibrato and chorus mode", "12 01", "00 00 00 12 01", "01", "vibrato_mode", 180,
    "The six positions of the VIBRATO AND CHORUS knob.",
    notes="The manual gives only 00-05 (V1 - C3). This app assumes the knob's order V-1, C-1, V-2, C-2, V-3, C-3, "
          "the order the positions are printed around the knob on p. 58 (and the B-3's). Confirm on the organ.")
row(AN, "Vibrato Type", "Vibrato type", "12 02", "00 00 00 12 02", "01", "enum:Big Box ('57-59)|Small Box ('59 on)|Metal Box ('55-57)", 180,
    "The vibrato delay line: Metal Box (1955-57), Big Silver Box (1957-59), Small Silver Box (1959 on).")
row(AN, "Vibrato Rate (TW)", "Vibrato rate, tone wheel", "12 03", "00 00 00 12 03", "01", "steps:00-7F:5.78 Hz:7.90 Hz", 180,
    "The scanner speed, 5.78 to 7.90 Hz.")
row(AN, "Vibrato Chorus Mix", "Chorus mix", "12 04", "00 00 00 12 04", "01", "chorusmix", 180,
    "Balance of dry and vibrato signal in chorus, D64 to Even to 63V.")
row(AN, "Vibrato Chorus Emph. Level", "Vibrato emphasis level", "12 05", "00 00 00 12 05", "01", "int:00-7F", 180)
row(AN, "Vibrato Rate (Transistor)", "Vibrato rate, transistor organs", "12 06", "00 00 00 12 06", "01", "int:00-7F", 180)
row(AN, "Vibrato Rate (Pipe)", "Tremulant rate, pipe", "12 07", "00 00 00 12 07", "01", "int:00-7F", 180)
row(AN, "Leslie Bypass", "Leslie bypass", "12 08", "00 00 00 12 08", "01", "onoff", 180)
row(AN, "Leslie Stop", "Leslie stop", "12 09", "00 00 00 12 09", "01", "onoff", 180)
row(AN, "Leslie Fast", "Leslie fast", "12 0A", "00 00 00 12 0A", "01", "onoff", 180)
row(AN, "Leslie On Reverb", "Reverb through Leslie", "12 0B", "00 00 00 12 0B", "01", "onoff", 180)
row(AN, "Leslie Input Gain", "Leslie drive gain", "12 0C", "00 00 00 12 0C", "01", "int:00-7F", 180)
row(AN, "Leslie Output Gain", "Leslie output level", "12 0D", "00 00 00 12 0D", "01", "int:00-7F", 180)
row(AN, "Custom Cabinet", "Leslie cabinet", "12 0E", "00 00 00 12 0E", "01", "custom_cabinet", 180,
    notes="The manual gives 00-13 (U1 - F10); this app assumes U1-U10 then F1-F10.")
row(AN, "Vibrato Chorus Emph. Freq.", "Vibrato emphasis frequency", "12 11", "00 00 00 12 11", "01",
    "steps:00-7F:20 Hz:10.21 kHz", 180)
row("Animation Lower", "Vibrato Lower", "Vibrato Lower", "1C 00", "00 00 00 1C 00", "01", "onoff", 180)
M1 = "Multi Effects 1"
row(M1, "On", "Effect 1 on", "13 00", "00 00 00 13 00", "01", "onoff", 180)
row(M1, "Allocate", "Effect 1 part", "13 01", "00 00 00 13 01", "01", "enum:Upper|Lower|Upper+Lower", 180)
row(M1, "Type", "Effect 1 type", "13 02", "00 00 00 13 02", "01", "enum:Tremolo|Wah-Wah|Ring Mod|Compressor", 180)
for i in range(8):
    row(M1, "Param %d" % (i + 1), "Effect 1 parameter %d" % (i + 1), "13 %02X" % (3 + i), "00 00 00 13 %02X" % (3 + i),
        "01", "int:00-03" if i < 2 else "int:00-7F", 180,
        "What this does depends on the effect type (manual p. 88 to 91).")
PA = "Pre-Amplifier"
row(PA, "On", "Preamp on", "14 00", "00 00 00 14 00", "01", "onoff", 180)
row(PA, "Drive Level", "Preamp drive", "14 01", "00 00 00 14 01", "01", "int:00-7F", 180)
row(PA, "Output Level", "Preamp output level", "14 02", "00 00 00 14 02", "01", "int:00-7F", 180)
row(PA, "Type", "Preamp type", "14 03", "00 00 00 14 03", "01", "enum:Tube Amp|Stomp Box|Clip|EP Amp", 180)
row(PA, "Presence", "Preamp presence", "14 04", "00 00 00 14 04", "01", "int:00-7F", 180)
row(PA, "Exp. Control", "Preamp expression order", "14 05", "00 00 00 14 05", "01", "enum:Exp-PreAmp|PreAmp-Exp", 180,
    notes="The menu page lists four choices; the MIDI table lists two.")
row(PA, "Tone Control", "Preamp tone", "14 06", "00 00 00 14 06", "01", "gain9", 180)
row(PA, "Hysteresis", "Preamp hysteresis", "14 07", "00 00 00 14 07", "01", "int:00-7F", 180)
row(PA, "Impedance Reduction", "Preamp impedance reduction", "14 08", "00 00 00 14 08", "01", "int:00-7F", 180)
M2 = "Multi Effects 2"
row(M2, "On", "Effect 2 on", "15 00", "00 00 00 15 00", "01", "onoff", 180)
row(M2, "Type", "Effect 2 type", "15 01", "00 00 00 15 01", "01", "enum:Auto Pan|Phaser|Flanger|Chorus|Delay", 180)
for i in range(8):
    row(M2, "Param %d" % (i + 1), "Effect 2 parameter %d" % (i + 1), "15 %02X" % (2 + i), "00 00 00 15 %02X" % (2 + i),
        "01", "int:00-03" if i < 2 else "int:00-7F", 180,
        "What this does depends on the effect type (manual p. 94 to 96).")
EQ = "Equalizer"
row(EQ, "Bass Freq", "Patch EQ bass frequency", "16 00", "00 00 00 16 00", "01", "steps:00-18:20 Hz:308 Hz", 181)
row(EQ, "Mid Freq", "Patch EQ middle frequency", "16 01", "00 00 00 16 01", "01", "steps:00-0F:250 Hz:3.1 kHz", 181)
row(EQ, "Treble Freq", "Patch EQ treble frequency", "16 02", "00 00 00 16 02", "01", "steps:00-13:3.0 kHz:8.0 kHz", 181)
row(EQ, "Bass Gain", "Patch EQ bass", "16 03", "00 00 00 16 03", "01", "gain9", 181)
row(EQ, "Mid Gain", "Patch EQ middle", "16 04", "00 00 00 16 04", "01", "gain9", 181)
row(EQ, "Treble Gain", "Patch EQ treble", "16 05", "00 00 00 16 05", "01", "gain9", 181)
DR = "Delay/Reverb"
row(DR, "On", "Delay and reverb on", "17 00", "00 00 00 17 00", "01", "onoff", 181)
row(DR, "Structure", "Delay and reverb structure", "17 01", "00 00 00 17 01", "01", "enum:Reverb|Delay|Reverb + Delay", 181)
row(DR, "Delay Pan", "Delay pan", "17 02", "00 00 00 17 02", "01", "enum:Mono|RtoL|LtoR", 181)
row(DR, "Delay Type", "Delay type", "17 03", "00 00 00 17 03", "01", "enum:Digital|Analog", 181)
row(DR, "Delay Mix", "Delay mix", "17 04", "00 00 00 17 04", "01", "int:00-7F", 181)
row(DR, "Delay Time", "Delay time", "17 05", "00 00 00 17 05", "01", "int:00-7F", 181)
row(DR, "Delay Feedback", "Delay feedback", "17 06", "00 00 00 17 06", "01", "int:00-7F", 181)
row(DR, "Reverb Type", "Reverb type", "17 07", "00 00 00 17 07", "01",
    "enum:Room 1|Room 2|Live|Hall 1|Hall 2|Church|Plate|Spring", 181)
row(DR, "Reverb Depth", "Reverb depth", "17 08", "00 00 00 17 08", "01", "int:00-7F", 181)
row(DR, "Reverb Time", "Reverb time", "17 09", "00 00 00 17 09", "01", "int:00-7F", 181)
row(DR, "Reverb Pre LPF", "Reverb pre filter", "17 0A", "00 00 00 17 0A", "01", "int:00-7F", 181)

# --- CUSTOM TONE WHEEL, p.182 (SysEx only) -----------------------------------------
TW = "Temporary Tone Wheels"
row(TW, "Name", "Custom tone wheel name", "--", "10 00 00 00 00", "10", "text16", 182)
row(TW, "Foldback Low", "Foldback low", "--", "10 00 00 00 01", "01", "onoff", 182)
row(TW, "Foldback High", "Foldback high", "--", "10 00 00 00 02", "01", "onoff", 182)
row(TW, "Lowest Note", "Fold back key, low", "--", "10 00 00 00 03", "01", "tw_lowest", 182,
    "The key below which the 16 foot drawbar folds back.",
    notes="The MIDI table labels this TW#01 - #12; the menu (p. 109) shows the key, 1C to 2C, which matches the 13 values.")
row(TW, "Highest Note", "Fold back key, high", "--", "10 00 00 00 04", "01", "tw_highest", 182,
    "The key above which the highest drawbars fold back.")
row(TW, "Leakage Increase Rate", "Leakage increase rate", "--", "10 00 00 00 05", "01", "int:00-7F", 182)
row(TW, "Percussion Total Level", "Percussion total level", "--", "10 00 00 00 06", "02", "db1041", 182)
row(TW, "Cust. TW Total Level Upper & Lower", "Tone wheel total level, Upper and Lower", "--", "10 00 00 00 07", "02", "db1041", 182)
row(TW, "Cust. TW Total Level Pedal", "Tone wheel total level, Pedal", "--", "10 00 00 00 08", "02", "db1041", 182)
row(TW, "Each TW Level", "Tone wheel level", "--", "10 00 00 01 tt", "02", "db1041", 182,
    indices=[dim("Tone wheel", 4, "wheels108")])
for b, mname, nm in (("02", "Wow Flutter Depth", "Wow and flutter depth"), ("03", "Wow Flutter Speed", "Wow and flutter speed"),
                     ("04", "Eccentricity Depth", "Eccentricity depth"), ("05", "Eccentricity Speed", "Eccentricity speed")):
    row(TW, mname, nm, "--", "10 00 00 %s tt" % b, "01", "int:00-7F", 182, indices=[dim("Tone wheel", 4, "wheels108")])
LEAK_PARTS = [(0, "Upper", "manual"), (1, "Lower", "manual"), (2, "Percussion", "perc_leak"), (3, "Pedal", "pedal_pairs")]
for b0, mname, nm in (("11", "Each Leak Level", "leak level"), ("12", "Total Leak Level", "total leak level")):
    for p, pname, fk in LEAK_PARTS:
        row(TW, mname, "%s %s" % (pname, nm), "--", "%s 0%d 0g tt hh" % (b0, p), "02", "db1041", 182, manual_addr="%s 0p 0g tt hh" % b0, help_text=
            "How much of one tone wheel leaks into another, for one footage.",
            indices=[dim("Footage", 2, fk), dim("Tone wheel", 3, "wheels96"), dim("Leaking wheel", 4, "wheels96")])
for p, pname, fk in LEAK_PARTS:
    row(TW, "Matrix Level", "%s matrix level" % pname, "--", "13 0%d 0g 00 nn" % p, "02", "db1041", 182, manual_addr="13 0p 0g 00 nn",
        indices=[dim("Footage", 2, fk), dim("Key", 4, "keys61")])
row(TW, "Impedance", "Impedance", "--", "14 00 00 nn 0g", "02", "db1041", 182,
    indices=[dim("Key", 3, "keys61"), dim("Footage", 4, "manual")],
    notes="The manual does not say which footages g covers here; this app offers the nine manual footages.")
row(TW, "Formant Level", "Formant level", "--", "15 00 00 00 0j", "02", "db1041", 182,
    indices=[dim("Formant", 4, "formants")])
row(TW, "Formant Phase", "Formant phase", "--", "15 00 00 01 0j", "02", "formant_phase", 182,
    indices=[dim("Formant", 4, "formants")])

# --- CUSTOM CONTACT, p.182 --------------------------------------------------------
CT = "Temporary Contact"
row(CT, "Name", "Custom contact name", "--", "20 00 00 00 00", "10", "text16", 182)
CONTACT_PARTS = [(0, "Upper", "manual"), (1, "Lower", "manual"), (2, "Percussion", "perc01"), (3, "Pedal", "manual8")]
for b2, mname, nm, spec in (("00", "Leaf Assign", "contact leaf", "contact_leaf"),
                            ("01", "Delay Time", "contact delay", "steps:00-7F:0.0 ms:725.6 ms")):
    for p, pname, fk in CONTACT_PARTS:
        row(CT, mname, "%s %s" % (pname, nm), "--", "21 0%d %s 0g nn" % (p, b2), "01", spec, 182, manual_addr="21 0p %s 0g nn" % b2,
            indices=[dim("Footage", 3, fk), dim("Key", 4, "keys61")])

# --- CUSTOM PEDAL REG, p.182 ------------------------------------------------------
PR = "Temporary Pedal"
row(PR, "Name", "Custom pedal registration name", "--", "30 00 00 00 00", "10", "text16", 182)
row(PR, "Complex TW LPF", "Complex tone wheel filter", "--", "30 00 00 00 01", "01", "int:00-7F", 182)
row(PR, "Level", "Pedal sub drawbar level", "--", "31 00 00 0g 0k", "01", "pedal_sub_level", 182,
    indices=[dim("Main footage", 3, "pedal2"), dim("Sub footage", 4, "manual8")],
    notes="The manual gives 00-08 (0 - 9). This app shows the raw 0 to 8.")

# --- CUSTOM PIPE, p.183 -----------------------------------------------------------
PP = "Pipes"
row(PP, "Name", "Custom pipe name", "--", "50 00 00 00 00", "10", "text16", 183)
PIPE_PARTS = [(0, "Upper", "manual", None), (1, "Lower", "manual", None),
              (3, "Pedal", "pedal2", "The manual lists part 3 as Pedal but describes 16' and 8' under part 2. "
                                     "This app uses part 3 for Pedal. Confirm on the organ before relying on it.")]
for b4, mname, nm, length, spec in (("00", "Stop Assign", "pipe stop", "02", "pipestop"),
                                    ("01", "Volume", "pipe volume", "02", "db193"),
                                    ("02", "Footage", "pipe footage", "01", "pipe_footage"),
                                    ("03", "Detune", "pipe detune", "02", "cent50"),
                                    ("04", "Tremulant", "pipe tremulant", "01", "onoff"),
                                    ("05", "Chiff", "pipe chiff", "01", "enum:Off|Soft|Mid|Loud"),
                                    ("06", "Cut Off Frequency", "pipe brightness", "02", "cutoff"),
                                    ("07", "Pan - Direction", "pipe pan", "01", "pan"),
                                    ("08", "Pan - Imaging", "pipe stereo imaging", "01",
                                     "enum:Fixed|L-R|R-L|Pyramid|Inverted Pyramid")):
    for p, pname, fk, caveat in PIPE_PARTS:
        extra = {"indices": [dim("Drawbar", 3, fk)], "manual_addr": "51 00 0p 0x %s" % b4}
        if caveat:
            extra["notes"] = caveat
        row(PP, mname, "%s %s" % (pname, nm), "--", "51 00 0%d 0x %s" % (p, b4), length, spec, 183, **extra)

# --- CUSTOM LESLIE, p.183 ---------------------------------------------------------
LS = "Cabinet"
row(LS, "Name", "Leslie cabinet name", "--", "40 00 00 00 00", "10", "text16", 183)
row(LS, "Speaker", "Leslie speaker", "--", "41 00 00 00 00", "01",
    "enum:145 Front|145 Rear|147 Front|147 Rear|122 Front|122 Rear|Cone Type|PR-40", 183)
for rotor, b3, rise in (("Horn", "00", "steps:00-24:0.8 sec:12.5 sec"), ("Drum", "01", "steps:00-23:1.0 sec:12.5 sec")):
    r = rotor.lower()
    row(LS, "Fast Speed " + rotor, "Leslie %s fast speed" % r, "--", "42 00 00 %s 00" % b3, "02", "leslie_fast", 183)
    row(LS, "Slow Speed " + rotor, "Leslie %s slow speed" % r, "--", "42 00 00 %s 01" % b3, "02", "leslie_slow", 183)
    row(LS, "Rise Time " + rotor, "Leslie %s rise time" % r, "--", "42 00 00 %s 02" % b3, "01", rise, 183,
        "Time to speed up to fast.")
    row(LS, "Fall Time " + rotor, "Leslie %s fall time" % r, "--", "42 00 00 %s 03" % b3, "01", rise, 183,
        "Time to slow down from fast.")
    row(LS, "Brake Time " + rotor, "Leslie %s brake time" % r, "--", "42 00 00 %s 04" % b3, "01", rise, 183,
        "Time to stop from fast.")
    row(LS, "Delay Time " + rotor, "Leslie %s delay time" % r, "--", "42 00 00 %s 05" % b3, "01", "leslie_delay", 183,
        "Wait before the speed starts changing.")
    row(LS, "Stop Angle " + rotor, "Leslie %s stop angle" % r, "--", "42 00 00 %s 06" % b3, "02", "stop_angle", 183)
for rotor, b3 in (("Horn", "00"), ("Drum", "01")):
    r = rotor.lower()
    row(LS, "Level " + rotor, "Leslie %s mic level" % r, "--", "43 00 00 %s 00" % b3, "02", "db77", 183,
        notes="The manual gives a length of 02 but writes the data as single bytes (00, 01-4D). "
              "This app sends two bytes, as the length column says.")
    row(LS, "Mic. Type " + rotor, "Leslie %s mic type" % r, "--", "43 00 00 %s 01" % b3, "01", "enum:Condenser|Dynamic", 183)
    row(LS, "Mic. Width " + rotor, "Leslie %s mic width" % r, "--", "43 00 00 %s 02" % b3, "01", "int:00-64", 183,
        notes="The MIDI table says 00-64 (0 - 100 cm); the menu says 0 to 40 cm or Side (p. 121). "
              "They don't agree, so this app shows the raw number, 0 to 100.")
    row(LS, "Mic. Center " + rotor, "Leslie %s mic center" % r, "--", "43 00 00 %s 03" % b3, "01", "mic_center", 183)
    row(LS, "Mic. Distance " + rotor, "Leslie %s mic distance" % r, "--", "43 00 00 %s 04" % b3, "02", "mic_distance", 183,
        notes="Raw 00 1E to 01 48 (30 to 200). The table says 0-170 cm for the horn but 30-200 cm for the drum; the menu "
              "(p. 121) says 0 to 170 cm for both, which is how it is shown here.")
    row(LS, "Stereo Image " + rotor, "Leslie %s stereo image" % r, "--", "43 00 00 %s 05" % b3, "01", "stereo_image", 183)
row(LS, "Level Sub Bass", "Leslie sub bass level", "--", "43 00 00 02 00", "01", "db77", 183)

# --- SYSTEM PARAMETERS, p.184-185 -------------------------------------------------
row("Tune", "Master Tune", "Master tune", "00 00", "00 00 00 00 00", "02", "master_tune", 184,
    "Concert pitch for A, 430 to 450 Hz.")
row("Tune", "Transpose", "Transpose", "00 01", "00 00 00 00 01", "02", "sint14:-6..6:semitones", 184)
ME = "Master Equalizer"
row(ME, "Bass Gain", "Master EQ bass", "01 00", "00 00 00 01 00", "01", "gain9", 184)
row(ME, "Mid Gain", "Master EQ middle", "01 01", "00 00 00 01 01", "01", "gain9", 184)
row(ME, "Treble Gain", "Master EQ treble", "01 02", "00 00 00 01 02", "01", "gain9", 184)
row(ME, "Bass Freq", "Master EQ bass frequency", "01 03", "00 00 00 01 03", "01", "steps:00-18:20 Hz:308 Hz", 184)
row(ME, "Mid Freq", "Master EQ middle frequency", "01 04", "00 00 00 01 04", "01", "steps:00-0F:125 Hz:4 kHz", 184)
row(ME, "Treble Freq", "Master EQ treble frequency", "01 05", "00 00 00 01 05", "01", "steps:00-13:3.0 kHz:8.0 kHz", 184)
row(ME, "Mid Q", "Master EQ middle width", "01 06", "00 00 00 01 06", "01", "int:00-3F", 184)
AU = "Audio"
row(AU, "Use Rotary Out", "Rotary out", "02 00", "00 00 00 02 00", "01", "onoff", 184)
row(AU, "Use Bass Out", "Bass out", "02 01", "00 00 00 02 01", "01", "onoff", 184)
row(AU, "Bass Out Type", "Bass out type", "02 02", "00 00 00 02 02", "01", "enum:Pedal|LPF", 184)
row(AU, "Bass Out C/Off Freq.", "Bass out cutoff", "02 03", "00 00 00 02 03", "01", "int:00-7F", 184)
row(AU, "Bass Out Phase Pol.", "Bass out phase", "02 04", "00 00 00 02 04", "01", "enum:Normal|Inverted", 184)
row(AU, "Ext. Leslie Channel", "External Leslie channels", "02 05", "00 00 00 02 05", "01", "enum:1|3", 184)
row(AU, "With Preamp", "Rotary out preamp", "02 06", "00 00 00 02 06", "01", "enum:Without|With", 184)
FS = "Foot Switches"
for i, mname in enumerate(["Mode 1 - Tip", "Mode 1 - Ring", "Mode 2 - Tip", "Mode 2 - Ring", "Mode EXP-100"]):
    row(FS, mname, "Foot switch " + mname.replace("Mode ", "").replace(" - ", " ").lower().replace("exp-100", "on EXP-100"),
        "03 %02X" % i, "00 00 00 03 %02X" % i, "01", "footswitch", 184,
        notes="The table heads the range 00-28 but lists 29 and 2A (To Adjust A#, B) too.")
EX = "Expression"
row(EX, "Source", "Expression source", "04 00", "00 00 00 04 00", "01", "enum:Pedal|MIDI|Both", 184)
row(EX, "Device", "Expression pedal type", "04 01", "00 00 00 04 01", "01", "enum:EXP-100|Phone", 184)
row(EX, "Polarity", "Expression pedal polarity", "04 02", "00 00 00 04 02", "01", "enum:Norm (H or R)|Rev (Y or K)", 184)
row(EX, "Min. Level Mode", "Expression minimum mode", "04 03", "00 00 00 04 03", "01", "enum:Off|Soft", 184)
row(EX, "Min. Level", "Expression minimum level", "04 04", "00 00 00 04 04", "01", "exp_level", 184)
row(EX, "Min. Limit LF", "Expression low limit, lows", "04 05", "00 00 00 04 05", "01", "exp_level", 184)
row(EX, "Min. Limit HF", "Expression low limit, highs", "04 06", "00 00 00 04 06", "01", "exp_level", 184)
row(EX, "Curve", "Expression curve", "04 08", "00 00 00 04 08", "01", "enum:1 (B-3)|2 (Linear)|3 (Capacitor)", 184)
for i, part in enumerate(["Upper", "Lower", "Pedal"]):
    row("Damper", part, "Damper mode, " + part, "05 %02X" % i, "00 00 00 05 %02X" % i, "01", "enum:Patch|Off (disabled)|On (enabled)", 184)
OT = "Octave / Transpose buttons"
row(OT, "Mode Oct/Xposepose", "Octave and transpose apply", "06 00", "00 00 00 06 00", "01", "enum:Every|Next", 184)
row(OT, "Mode Octave Down", "Octave Down button", "06 01", "00 00 00 06 01", "01", "enum:Octave|Assign", 184)
row(OT, "Mode Octave Up", "Octave Up button", "06 02", "00 00 00 06 02", "01", "enum:Octave|Assign", 184)
row(OT, "Mode Octave Lower", "Octave Lower button", "06 03", "00 00 00 06 03", "01", "enum:Octave|Assign", 184)
KD = "Knobs / Drawbars"
row(KD, "Control Mode", "Knob and drawbar control mode", "07 00", "00 00 00 07 00", "01", "enum:A#/B|Always A#", 184)
row(KD, "Action", "Knob and drawbar action", "07 01", "00 00 00 07 01", "01", "enum:Momentary|Across", 184)
DS = "Display"
row(DS, "Short Cut", "Display shortcut hold", "08 00", "00 00 00 08 00", "01", "enum:0 sec|1 sec|2 sec|No", 184)
row(DS, "Time Out", "Display time out", "08 01", "00 00 00 08 01", "01", "enum:4 sec|8 sec|16 sec|No", 184)
row(DS, "Pop Up", "Display pop up", "08 02", "00 00 00 08 02", "01", "enum:No|0.5 sec|1.0 sec|1.5 sec|2.0 sec", 184)
row(DS, "Brightness", "Display brightness", "08 03", "00 00 00 08 03", "01", "brightness", 184)
row(DS, "Play Mode Drawbars", "Play screen drawbars", "08 04", "00 00 00 08 04", "01", "enum:Horizontal|Vertical", 184)
row(DS, "Play Mode Type", "Play screen type", "08 05", "00 00 00 08 05", "01", "enum:Int. Zones|Assign|Simple|Ext. Zones", 184)
row(DS, "Dimmer", "Display dimmer", "08 07", "00 00 00 08 07", "01", "enum:No|4 sec|8 sec|16 sec", 184)
KB = "Keyboard"
row(KB, "Velocity Offset", "Velocity offset", "09 00", "00 00 00 09 00", "02", "sint14:-15..15", 184)
row(KB, "Organ Sounding Point", "Organ sounding point", "09 01", "00 00 00 09 01", "01", "sounding_point", 184,
    notes="The MIDI table says Patch, 1-7, Velocity, nine names for eight values (00-07). "
          "The menu (p. 137) says Patch, 1-6, Velocity, which fits.")
row(KB, "Preset Key Hold Time", "Preset key hold time", "09 02", "00 00 00 09 02", "01", "hold_ms", 184,
    "How long a Preset Key must be held to recall a patch.",
    notes="The MIDI table says 00-0A (0.0 - 1.0 sec); the menu says 0 to 100 ms (p. 137). This app follows the menu, "
          "in 10 ms steps. The organ's display will settle which is right.")
MC = "MIDI Common"
row(MC, "MIDI In Mode", "MIDI in mode", "--", "00 00 00 0C 00", "01", "enum:Upper|Lower|Sequencer", 184)
row(MC, "Rx VMC Depth", "Virtual multi-contact depth", "--", "00 00 00 0C 01", "01", "int:00-7F", 184)
row(MC, "Local Control", "Local control", "--", "00 00 00 0C 02", "01", "onoff", 184)
row(MC, "TRx Individual Parameters", "Individual parameters", "--", "00 00 00 0C 03", "01", "enum:Off|NRPN|SysEx", 184,
    "How the organ sends and receives single setting changes. SysEx lets this app hear every setting.")
row(MC, "TRx Program Change", "Send and receive program change", "--", "00 00 00 0C 04", "01", "onoff", 184)
row(MC, "TRx Drawbar Regi", "Send and receive drawbars", "--", "00 00 00 0C 05", "01", "onoff", 184)
row(MC, "Tx External Zones", "External zones", "--", "00 00 00 0C 06", "01", "onoff", 184)
row(MC, "Tx EXZ Program Change", "External zone program change", "--", "00 00 00 0C 07", "01", "onoff", 184)
row(MC, "Tx EXZ Control Change", "External zone control change", "--", "00 00 00 0C 08", "01", "onoff", 184)
row(MC, "Octave to EXZ", "Octave to external zones", "--", "00 00 00 0C 09", "01", "onoff", 184)
row("USB MIDI", "TRx Notes", "USB MIDI notes", "--", "00 00 00 0C 0C", "01", "enum:Velocity|Multi-Contact", 184)
CH = "MIDI Channel"
for i, mname in enumerate(["Tx Upper", "Tx Lower", "Tx Pedal", "Rx Upper", "Rx Lower", "Rx Pedal"]):
    row(CH, mname, ("Send channel, " if mname.startswith("Tx") else "Receive channel, ") + mname[3:],
        "--", "00 00 00 0D %02X" % i, "01", "chan16off", 185)
row("Patch Load", "Action", "Patch load", "0A 00", "00 00 00 0A 00", "01", "enum:Instant|Entered", 185,
    "Instant loads a patch as soon as you turn VALUE; Entered waits for ENTER.")
PL = [("Registration", "drawbar registration"), ("Drawbar", "drawbar settings"), ("Percussion", "percussion"),
      ("Animation", "vibrato and Leslie"), ("Effect / EQ", "effects and EQ"), ("Delay / Reverb", "delay and reverb"),
      ("Control", "controllers"), ("Assign", "assign knobs"), ("Internal Zones", "internal zones"),
      ("External Zones", "external zones"), ("Pedal to Lower", "pedal to lower")]
for i, (mname, short) in enumerate(PL):
    row("Patch Load", mname, "loads " + short, "4b %02X" % i, "00 00 00 4b %02X" % i, "01", "onoff", 185,
        "Whether Preset Keys in this bank recall the " + short + ".",
        expand={"b": [(n, BANKS[n]) for n in range(10)]},
        expand_format="Bank {label} {name}", expand_category="Patch load, bank {label}",
        notes="The manual says only 'b = Bank'. This app assumes b runs 0 to 9 for banks C to A.")
row("Favorites", "On", "Favorites on", "0B 04", "00 00 00 0B 04", "01", "onoff", 185,
    "Whether the Preset Keys pick Favorites instead of User patches.")
for b, part in (("50", "Upper"), ("51", "Lower")):
    row("Favorites", "Assign " + part, "Favorite, " + part, b + " ff", "00 00 00 %s ff" % b, "02", "patchnum", 185,
        "Which patch a Favorite Preset Key recalls.", merged_length=(part == "Lower"), indices=[dim("Bank and key", 4, "favorite_keys")])

INDEX_SOURCES = {
    "wheels108": wheels108, "wheels96": wheels96, "keys61": keys61, "favorite_keys": favorite_keys,
    "formants": lambda: [[j, "Formant %d" % (j + 1)] for j in range(8)],
}


def index_options(src):
    if isinstance(src, list):
        return src
    if src in INDEX_SOURCES:
        return INDEX_SOURCES[src]()
    return foot_opts(src)


# --------------------------------------------------------------- sections --
SECTIONS = [
    # (manual category prefix, section, friendly category)
    ("Name", "Patch", "Patch name"),
    ("Internal Zones", "Patch", "Keyboard and zones"),
    ("External Zones", "Patch", "External zones"),
    ("Control Upper", "Patch", "Controllers"), ("Control Lower", "Patch", "Controllers"),
    ("Control Pedal", "Patch", "Controllers"),
    ("Control Assignable", "Patch", "Assign knobs and buttons"),
    ("Drawbars Upper", "Patch", "Organ"), ("Drawbars Lower", "Patch", "Organ"), ("Drawbars Pedal", "Patch", "Pedal"),
    ("Percussion", "Patch", "Percussion"),
    ("Registration", "Patch", "Drawbars"),
    ("Animation", "Patch", "Vibrato and Leslie"),
    ("Multi Effects 1", "Patch", "Effect 1"), ("Pre-Amplifier", "Patch", "Preamp"),
    ("Multi Effects 2", "Patch", "Effect 2"), ("Equalizer", "Patch", "Patch EQ"),
    ("Delay/Reverb", "Patch", "Delay and reverb"),
    ("Temporary Tone Wheels", "Custom", "Custom tone wheels"),
    ("Temporary Contact", "Custom", "Custom contacts"),
    ("Temporary Pedal", "Custom", "Custom pedal registration"),
    ("Pipes", "Custom", "Custom pipes"),
    ("Cabinet", "Custom", "Custom Leslie cabinet"),
    ("Tune", "System", "Tuning"), ("Master Equalizer", "System", "Master EQ"), ("Audio", "System", "Outputs"),
    ("Foot Switches", "System", "Foot switches"), ("Expression", "System", "Expression pedal"),
    ("Damper", "System", "Damper"), ("Octave / Transpose", "System", "Buttons"), ("Knobs / Drawbars", "System", "Buttons"),
    ("Display", "System", "Display"), ("Keyboard", "System", "Keyboard"),
    ("MIDI Common", "System", "MIDI"), ("USB MIDI", "System", "MIDI"), ("MIDI Channel", "System", "MIDI channels"),
    ("Patch Load", "System", "Patch load"), ("Favorites", "System", "Favorites"),
]


def section_for(cat):
    for prefix, section, friendly in SECTIONS:
        if cat.startswith(prefix):
            return section, friendly
    raise ValueError("no section for " + cat)


def slug(s):
    s = s.replace("#", "sharp").replace("'", "").replace("’", "").replace("´", "")
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def parse_addr(addr, subs):
    out = []
    for tok in addr.split():
        for k, v in subs.items():
            tok = tok.replace(k, "%X" % v)
        if tok in PLACEHOLDERS:
            out.append(0)  # index placeholder ("ff" must not be read as the byte FF)
        elif re.fullmatch(r"[0-9A-Fa-f]{2}", tok):
            out.append(int(tok, 16))
        else:
            raise ValueError("bad address token %r in %r" % (tok, addr))
    assert len(out) == 5, addr
    assert all(b < 0x80 for b in out), ("address bytes must be 7-bit", addr)
    return out


PLACEHOLDERS = {"tt", "hh", "nn", "ff", "0g", "0k", "0j", "0x", "0p"}


def build():
    params = []
    ids = set()
    for r in ROWS:
        extra = dict(r["extra"])
        expand = extra.pop("expand", None)
        efmt = extra.pop("expand_format", None)
        ecat = extra.pop("expand_category", None)
        extra.pop("manual_addr", None)
        extra.pop("merged_length", None)
        variants = [({}, r["name"], None)]
        if expand:
            (key, vals), = expand.items()
            variants = [({key: v}, efmt.format(label=lab, name=r["name"]), ecat.format(label=lab)) for v, lab in vals]
        for subs, name, subcat in variants:
            section, friendly = section_for(r["cat"])
            addr = parse_addr(r["addr"], subs)
            nrpn = None
            if r["nrpn"] != "--":
                n = parse_addr("00 00 00 " + r["nrpn"], subs)
                nrpn = [n[3], n[4]]
                # Every NRPN in the manual equals the last two SysEx address bytes.
                assert addr[:3] == [0, 0, 0] and nrpn == addr[3:], (r, addr, nrpn)
            length = int(r["length"], 16)
            value = parse_value(r["value"])
            if value["type"] == "enum":
                value["min"] = min(o[0] for o in value["options"])
                value["max"] = max(o[0] for o in value["options"])
            if value["type"] == "text":
                assert length == 16
            else:
                assert value["max"] < (128 if length == 1 else 16384), (r["mname"], value)
            indices = []
            for d in extra.pop("indices", []):
                indices.append({"name": d["name"], "position": d["position"], "options": index_options(d["options"])})
            pid = "%s.%s.%s" % (section.lower(), slug(subcat or friendly), slug(name))
            n = 2
            base = pid
            while pid in ids:
                pid = "%s-%d" % (base, n)
                n += 1
            ids.add(pid)
            p = {
                "id": pid,
                "section": section,
                "category": subcat or friendly,
                "manualCategory": r["cat"],
                "manualName": r["mname"],
                "name": name[0].upper() + name[1:],
                "address": addr,
                "nrpn": nrpn,
                "length": length,
                "value": value,
                "page": r["page"],
                "help": r["help"],
            }
            if indices:
                p["indices"] = indices
            if extra.get("notes"):
                p["notes"] = extra["notes"]
            if extra.get("xk7only"):
                p["xk7Only"] = True
            params.append(p)
    # No two parameters may share an address (index positions are compared by pattern).
    seen = {}
    for p in params:
        key = tuple(p["address"]) + tuple(sorted(d["position"] for d in p.get("indices", [])))
        assert key not in seen, ("duplicate address", p["id"], seen.get(key))
        seen[key] = p["id"]
    return params


def main():
    params = build()
    doc = {
        "source": "Hammond XK-7 / XK-7D Owner's Manual V1.10, MIDI INFORMATION pp. 176-185",
        "generator": "tools/generate_parameters.py",
        "count": len(params),
        "parameters": params,
    }
    # One parameter per line keeps diffs readable and the file small.
    with open(OUT, "w") as f:
        f.write("{\n")
        for k in ("source", "generator", "count"):
            f.write(" %s: %s,\n" % (json.dumps(k), json.dumps(doc[k])))
        f.write(' "parameters": [\n')
        f.write(",\n".join("  " + json.dumps(p, ensure_ascii=False, separators=(",", ":")) for p in params))
        f.write("\n ]\n}\n")
    fam = sum(1 for p in params if p.get("indices"))
    print("wrote %d parameters (%d with index pickers) to %s" % (len(params), fam, os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
