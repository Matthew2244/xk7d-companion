"""Write a Sparkle update list (appcast) for one release.

    python3 tools/appcast.py FILE VERSION URL [--notes NOTES.md] [--windows] > appcast.xml

FILE is the Mac zip (Sparkle) or, with --windows, the Windows installer (WinSparkle). It is signed
with XK-7D Companion's EdDSA key through scripts/sparkle-sign.sh; every installed copy checks that
signature against its built-in public key before installing anything. NOTES.md is the release notes
in the plain Markdown the release page uses (paragraphs and "- " lists).
"""
import argparse
import html
import os
import re
import subprocess
import sys
from email.utils import formatdate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_MACOS = "14.0"
# WinSparkle runs the installer quietly; /relaunch=1 opens the app again afterwards (see the .iss).
WINDOWS_ARGS = "/SILENT /SP- /SUPPRESSMSGBOXES /NORESTART /relaunch=1"


def notes_html(md: str) -> str:
    out = []
    for block in re.split(r"\n\s*\n", md.strip()):
        lines = [ln.strip() for ln in block.splitlines() if ln.strip()]
        if not lines:
            continue
        if all(ln.startswith("- ") for ln in lines):
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % html.escape(ln[2:]) for ln in lines))
        else:
            out.append("<p>%s</p>" % html.escape(" ".join(lines)))
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", "\n".join(out))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("file")
    p.add_argument("version")
    p.add_argument("url")
    p.add_argument("--notes")
    p.add_argument("--windows", action="store_true")
    a = p.parse_args()
    sig = subprocess.run([os.path.join(ROOT, "scripts", "sparkle-sign.sh"), a.file],
                         capture_output=True, text=True, check=True).stdout.strip()
    if not re.fullmatch(r'sparkle:edSignature="[A-Za-z0-9+/=]+" length="\d+"', sig):
        sys.exit("unexpected signature output: " + sig)
    notes = open(a.notes).read() if a.notes else ""
    extra = (' sparkle:os="windows" sparkle:installerArguments="%s"' % WINDOWS_ARGS) if a.windows else ""
    minsys = "" if a.windows else "\n      <sparkle:minimumSystemVersion>%s</sparkle:minimumSystemVersion>" % MIN_MACOS
    print("""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>XK-7D Companion</title>
    <item>
      <title>Version {v}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{v}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>{minsys}
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{url}" {sig} type="application/octet-stream"{extra}/>
    </item>
  </channel>
</rss>""".format(v=html.escape(a.version), date=formatdate(usegmt=True), minsys=minsys, notes=notes_html(notes),
                 url=html.escape(a.url, quote=True), sig=sig, extra=extra))


if __name__ == "__main__":
    main()
