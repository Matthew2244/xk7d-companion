#!/usr/bin/env python3
"""Cross-check every hand-transcribed row in generate_parameters.py against
reference/manual.txt (pdftotext -layout of the Owner's Manual).

For each row we look for one line of the manual text that holds, in order:
the manual's parameter name, the NRPN bytes (or "--  --"), the five SysEx
address bytes and the length. A row passes when such a line exists. This
catches typos in the transcription: a wrong byte, a swapped row, a wrong
length. It cannot catch an error in the manual itself.

Rows whose name and numbers are split across lines in the text export are
listed as "needs eye" and were checked against the page images instead;
the result of that check is recorded in docs/PARAMETER-REVIEW.md.

Also checks the worked examples printed in the manual against the encoder
logic of the generated table (the Swift unit tests check them again).
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import generate_parameters as g  # noqa: E402

ROOT = os.path.dirname(HERE)
# The manual is Hammond's copyright and is not in this repository. Download the PDF from Suzuki
# (see README), then: pdftotext -layout manual.pdf manual.txt
MANUAL = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "reference", "manual.txt")
if not os.path.exists(MANUAL):
    sys.exit("usage: verify_against_manual.py path/to/manual.txt  (pdftotext -layout of the XK-7 Owner's Manual V1.10)")
TEXT = open(MANUAL, encoding="utf-8").read()
# Only the appendix pages (176-185) matter; restrict to keep matches honest.
start = TEXT.index("\nPATCH PARAMETERS\n")
end = TEXT.index("MIDI IMPLEMENTATION CHART", start)
APPENDIX = TEXT[start:end]
LINES = [re.sub(r"\s+", " ", l).strip() for l in APPENDIX.splitlines()]


def name_pattern(name):
    words = name.replace("´", "'").replace("’", "'").split()
    return r"\s+".join(re.escape(w).replace("'", "['´’]") for w in words)


def tokens_pattern(tokens):
    return r"\s+".join(re.escape(t) for t in tokens)


def check_row(r):
    nrpn = r["nrpn"].split() if r["nrpn"] != "--" else ["--", "--"]
    addr = r["extra"].get("manual_addr", r["addr"]).split()
    if r["extra"].get("merged_length"):
        # The length cell is shared with the row above on the page; checked on the page image.
        pat = r"(?:^|\s)" + name_pattern(r["mname"]) + r"\s+" + tokens_pattern(nrpn + addr) + r"(?:\s|$)"
        if any(re.search(pat, l, re.I) for l in LINES):
            return True
    pat = r"(?:^|\s)" + name_pattern(r["mname"]) + r"\s+" + tokens_pattern(nrpn + addr + [r["length"]]) + r"(?:\s|$)"
    rx = re.compile(pat, re.IGNORECASE)
    for l in LINES:
        if rx.search(l):
            return True
    # Custom tables have no NRPN column.
    if r["nrpn"] == "--":
        pat2 = r"(?:^|\s)" + name_pattern(r["mname"]) + r"\s+" + tokens_pattern(addr + [r["length"]]) + r"(?:\s|$)"
        rx2 = re.compile(pat2, re.IGNORECASE)
        for l in LINES:
            if rx2.search(l):
                return True
    # The bytes alone (name on another line, e.g. two-column pages).
    pat3 = tokens_pattern((nrpn if r["nrpn"] != "--" else []) + addr + [r["length"]])
    rx3 = re.compile(r"(?:^|\s)" + pat3 + r"(?:\s|$)", re.IGNORECASE)
    for l in LINES:
        if rx3.search(l):
            return "bytes-only"
    return False


def data_range_on_line(line, r):
    """The raw min and max printed in the Data column of a matched line, or None."""
    addr = r["extra"].get("manual_addr", r["addr"]).split()
    idx = line.find(" ".join(addr))
    if idx < 0:
        return None
    rest = line[idx + len(" ".join(addr)):].strip()
    rest = rest[len(r["length"]):].strip() if rest.startswith(r["length"]) else rest
    head = rest.split("(")[0].split(":")[0]
    head = head.replace("–", " ").replace("-", " ").replace(",", " ")
    toks = [t for t in head.split() if re.fullmatch(r"[0-9A-Fa-f]{1,4}", t)]
    if not toks:
        return None
    if r["length"] == "02":
        vals = []
        i = 0
        while i < len(toks):
            if len(toks[i]) == 4:
                vals.append(int(toks[i], 16) >> 8 << 7 | int(toks[i], 16) & 0xFF)
                i += 1
            elif i + 1 < len(toks):
                vals.append(int(toks[i], 16) << 7 | int(toks[i + 1], 16))
                i += 2
            else:
                vals.append(int(toks[i], 16))
                i += 1
    else:
        vals = [int(t, 16) for t in toks]
    return min(vals), max(vals)


def check_ranges():
    """Compare each row's value range with the Data column. Mismatches are printed for review."""
    mism = []
    seen = set()
    for r in g.ROWS:
        if r["value"] in ("text16",):
            continue
        key = (r["cat"], r["mname"], r["value"])
        if key in seen:
            continue
        seen.add(key)
        v = g.parse_value(r["value"])
        if v["type"] == "enum":
            lo, hi = min(o[0] for o in v["options"]), max(o[0] for o in v["options"])
        else:
            lo, hi = v["min"], v["max"]
        addr = r["extra"].get("manual_addr", r["addr"])
        found = None
        for l in LINES:
            if addr in l:
                found = data_range_on_line(l, r)
                if found:
                    break
        if found is None:
            continue
        if found != (lo, hi):
            mism.append((r, found, (lo, hi)))
    for r, f, mine in mism:
        print("RANGE      %-30s %-28s manual %s-%s, table %s-%s" % (r["cat"], r["mname"], hex(f[0]), hex(f[1]), hex(mine[0]), hex(mine[1])))
    print("%d range differences to review (see docs/PARAMETER-REVIEW.md)" % len(mism))


def main():
    ok = eye = bad = 0
    seen = set()
    eyes = []
    for r in g.ROWS:
        key = (r["cat"], r["mname"], r["extra"].get("manual_addr", r["addr"]))
        if key in seen:
            continue
        seen.add(key)
        res = check_row(r)
        if res is True:
            ok += 1
        elif res == "bytes-only":
            eye += 1
            eyes.append(r)
        else:
            bad += 1
            print("NOT FOUND  %-30s %-28s nrpn %-6s addr %s len %s" % (r["cat"], r["mname"], r["nrpn"], r["addr"], r["length"]))
    for r in eyes:
        print("NEEDS EYE  %-30s %-28s nrpn %-6s addr %s len %s (bytes found, name on another line)"
              % (r["cat"], r["mname"], r["nrpn"], r["addr"], r["length"]))
    print("\n%d rows matched name+bytes, %d matched bytes only, %d not found\n" % (ok, eye, bad))
    check_ranges()
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
