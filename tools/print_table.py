#!/usr/bin/env python3
"""Print the generated table one page at a time, in the manual's own terms, for review against the PDF."""
import json, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = json.load(open(os.path.join(ROOT, "Sources/XK7DCore/Resources/parameters.json")))
page = int(sys.argv[1]) if len(sys.argv) > 1 else None
def rng(p):
    v = p["value"]
    t = v["type"]
    if t == "text": return "text16"
    if t == "enum":
        o = v["options"]
        return "%02X-%02X %s" % (o[0][0], o[-1][0], "|".join(l for _, l in o) if len(o) <= 12 else "%s..%s (%d)" % (o[0][1], o[-1][1], len(o)))
    def enc(x): return ("%02X %02X" % (x >> 7, x & 0x7F)) if p["length"] == 2 else "%02X" % x
    return "%s .. %s  %s" % (enc(v["min"]), enc(v["max"]), ' '.join('%s=%s' % (k, v[k]) for k in ('zero','origin','step','unit','special','low','high','center') if k in v and v[k] not in ('', None)))
for p in d["parameters"]:
    if page and p["page"] != page: continue
    a = " ".join("%02X" % b for b in p["address"])
    if p.get("indices"):
        a = a.split()
        for dm in p["indices"]:
            a[dm["position"]] = "[%s]" % dm["name"][:6]
        a = " ".join(a)
    n = "%02X %02X" % tuple(p["nrpn"]) if p["nrpn"] else "-- --"
    print("%-22s %-28s %s | %-32s %d | %s" % (p["manualCategory"][:22], p["manualName"][:28], n, a, p["length"], rng(p)))
