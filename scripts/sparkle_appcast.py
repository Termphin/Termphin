#!/usr/bin/env python3
"""Writes the Sparkle appcast for one macOS DMG, signed for its updater.

    sparkle_appcast.py --dmg Termphin.dmg --version 1.17.0 --build 33 \
        --url https://github.com/Termphin/Termphin/releases/download/v1.17.0/Termphin.dmg \
        --out appcast.xml

The DMG is signed with Ed25519 - the private key, a PKCS#8 PEM, comes from
the SPARKLE_ED_PRIVATE_KEY environment variable and never touches the disk -
and the app checks the signature against the public key in its Info.plist
(SUPublicEDKey) before it installs anything. Sparkle compares `version`
(the build number, CFBundleVersion) to tell newer from older.
"""
import argparse
import base64
import os
import sys
from email.utils import formatdate
from xml.sax.saxutils import escape, quoteattr

from cryptography.hazmat.primitives.serialization import load_pem_private_key


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dmg", help="artifact path (alias for --file)")
    parser.add_argument("--file", help="artifact path to sign")
    parser.add_argument("--version", required=True, help="short version, 1.17.0")
    parser.add_argument("--build", required=True, help="build number, CFBundleVersion")
    parser.add_argument("--url", required=True, help="where the artifact is downloaded from")
    parser.add_argument("--os", help="optional sparkle:os attribute (macos, linux, windows)")
    parser.add_argument("--notes", default="https://termphin.dev/changelog")
    parser.add_argument("--min-system", default="10.15")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    artifact = args.file or args.dmg
    if not artifact:
        parser.error("one of --file or --dmg is required")

    pem = os.environ.get("SPARKLE_ED_PRIVATE_KEY", "").strip()
    if not pem:
        print("SPARKLE_ED_PRIVATE_KEY is not set", file=sys.stderr)
        return 1
    key = load_pem_private_key(pem.encode(), password=None)
    with open(artifact, "rb") as f:
        data = f.read()
    signature = base64.b64encode(key.sign(data)).decode()

    min_system_tag = (
        f"\n      <sparkle:minimumSystemVersion>{escape(args.min_system)}</sparkle:minimumSystemVersion>"
        if args.min_system
        else ""
    )
    os_attr = f" sparkle:os={quoteattr(args.os)}" if args.os else ""

    item = f"""    <item>
      <title>{escape("Termphin " + args.version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>{min_system_tag}
      <sparkle:releaseNotesLink>{escape(args.notes)}</sparkle:releaseNotesLink>
      <enclosure url={quoteattr(args.url)} length="{len(data)}" type="application/octet-stream"{os_attr} sparkle:edSignature={quoteattr(signature)}/>
    </item>"""
    feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Termphin</title>
{item}
  </channel>
</rss>
"""
    with open(args.out, "w", encoding="utf-8") as out:
        out.write(feed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
