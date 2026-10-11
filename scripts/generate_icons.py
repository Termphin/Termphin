#!/usr/bin/env python3
"""Generate every Termphin icon asset from assets/logo.svg.

The vector is the single source of truth. Everything below is derived from it,
so a logo change is one file edit plus one run of this script.

Produces:
  assets/logo.png                        1024 tile, the Flutter asset
  assets/icons/termphin_icon.png          512 tile, legacy launcher icon
  assets/icons/termphin_foreground.png    512 glyph on transparent, adaptive fg
  assets/icons/termphin_background.png    512 gradient, adaptive bg
  assets/icons/termphin_monochrome.png    512 silhouette, adaptive monochrome
  macos/Runner/Assets.xcassets/...        the AppIcon set
  android/.../drawable-*/ic_stat_termphin.png  the notification small icon
  assets/icons/tray.png                   64 tile, the tray icon
  assets/icons/tray_template.png          36 silhouette, the menu bar template

After running this, run `dart run flutter_launcher_icons` to rebuild the
Android resources from the icon files. It only touches `ic_launcher*`, so the
notification icon written here survives.

Needs chromium-browser (SVG rasterising) and ImageMagick. Deliberately no
Pillow: the previous version imported it and the module is not installed here,
so the script could not run at all.
"""

import pathlib
import re
import subprocess
import tempfile

ROOT = next(p for p in pathlib.Path(__file__).resolve().parents if (p / "pubspec.yaml").exists())
LOGO_SVG = ROOT / "assets" / "logo.svg"

# Android masks and animates the outer ring of an adaptive icon, so a glyph
# drawn edge to edge gets its nose clipped by a circular mask. This is the
# fraction of the canvas the artwork is allowed to occupy.
FOREGROUND_SCALE = 0.62

# The notification icon is drawn into a circle the system already pads, so it
# needs far less breathing room of its own than the adaptive foreground.
STATUS_SCALE = 0.9

# Android's canonical notification icon is 24dp.
STATUS_DENSITIES = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}


def render(svg_text, size, out):
    """Rasterise SVG markup to a square PNG via headless Chromium.

    Chromium rather than rsvg-convert or ImageMagick's SVG delegate: the
    delegate shells out to rsvg-convert, which is not installed here, and
    ImageMagick's internal MSVG renderer mangles gradients.
    """
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "wrap.html").write_text(
            "<!doctype html><meta charset='utf-8'>"
            "<style>html,body{margin:0;background:transparent}"
            f"svg{{display:block;width:{size}px;height:{size}px}}</style>" + svg_text
        )
        subprocess.run(
            [
                "chromium-browser", "--headless", "--disable-gpu", "--no-sandbox",
                "--hide-scrollbars", "--default-background-color=00000000",
                "--force-device-scale-factor=1",
                f"--window-size={size},{size}",
                f"--user-data-dir={tmp}",
                "--virtual-time-budget=4000",
                f"--screenshot={out}",
                f"file://{tmp / 'wrap.html'}",
            ],
            check=True,
            capture_output=True,
        )


def variants():
    """The full tile, the glyph alone, and the backdrop alone."""
    full = LOGO_SVG.read_text()
    glyph = re.sub(r'<rect id="tile-bg".*?/>', "", full, flags=re.S)
    if glyph == full:
        raise SystemExit("assets/logo.svg has no #tile-bg rect to strip")
    backdrop = re.sub(r"<path .*?/>", "", full, flags=re.S)
    backdrop = re.sub(r'<rect x=.*?/>', "", backdrop, flags=re.S)
    return full, glyph, backdrop


def silhouette(size):
    """The mark as a flat white shape, the eye punched through it.

    A notification small icon is an alpha mask - the system throws the colours
    away, tints what is left and drops it in a circle - so the gradient body
    and the blue eye would both come back as one featureless blob. The eye has
    to be a hole in the alpha to survive at all.
    """
    full = LOGO_SVG.read_text()
    body = re.search(r'<path d="(.*?)"', full, re.S).group(1)
    eye = re.search(r"<rect x=.*?/>", full, re.S).group(0)
    eye = re.sub(r'fill="[^"]*"', 'fill="black"', eye)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 360 360">'
        f'<mask id="cut" maskUnits="userSpaceOnUse" x="0" y="0" '
        f'width="360" height="360">'
        f'<path d="{body}" fill="white"/>{eye}</mask>'
        f'<rect width="360" height="360" fill="white" mask="url(#cut)"/>'
        f"</svg>"
    )


def padded(glyph_svg, size, scale):
    """The glyph centred on a transparent square at `scale` of the canvas."""
    inner = round(size * scale)
    pad = (size - inner) / 2
    inner_svg = glyph_svg.split(">", 1)[1].rsplit("</svg>", 1)[0]
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}">'
        f'<g transform="translate({pad},{pad}) scale({inner / 360})">'
        f"{inner_svg}</g></svg>"
    )


def magick(*args):
    subprocess.run(["magick", *[str(a) for a in args]], check=True)


def main():
    full, glyph, backdrop = variants()
    written = {}

    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        tile, fg, bg = tmp / "tile.png", tmp / "fg.png", tmp / "bg.png"
        stat, mono = tmp / "stat.png", tmp / "mono.png"
        render(full, 1024, tile)
        render(padded(glyph, 1024, FOREGROUND_SCALE), 1024, fg)
        render(backdrop, 1024, bg)
        render(silhouette(1024), 1024, stat)
        # The themed-icon layer is the same silhouette as the notification
        # icon, but padded like the adaptive foreground rather than trimmed
        # like the status one - a launcher draws it through the same mask as
        # the colour icon, so the glyph has to land in the same place or the
        # themed version sits visibly off-centre beside it.
        render(padded(silhouette(1024), 1024, FOREGROUND_SCALE), 1024, mono)

        def emit(src, dest, size):
            dest = ROOT / dest
            dest.parent.mkdir(parents=True, exist_ok=True)
            magick(src, "-resize", f"{size}x{size}", "-strip", dest)
            written[str(dest.relative_to(ROOT))] = size

        def emit_status(dest, size):
            """Trimmed to the glyph, then centred - the mark is wider than it
            is tall, so scaling the 360 canvas would leave it half the height
            the circle has room for."""
            dest = ROOT / dest
            dest.parent.mkdir(parents=True, exist_ok=True)
            inner = round(size * STATUS_SCALE)
            magick(
                stat, "-trim", "+repage",
                "-resize", f"{inner}x{inner}",
                "-background", "none", "-gravity", "center",
                "-extent", f"{size}x{size}", "-strip", dest,
            )
            written[str(dest.relative_to(ROOT))] = size

        emit(tile, "assets/logo.png", 1024)
        emit(tile, "assets/icons/termphin_icon.png", 512)
        emit(fg, "assets/icons/termphin_foreground.png", 512)
        emit(bg, "assets/icons/termphin_background.png", 512)
        emit(mono, "assets/icons/termphin_monochrome.png", 512)

        for density, size in STATUS_DENSITIES.items():
            emit_status(
                f"android/app/src/main/res/drawable-{density}/ic_stat_termphin.png",
                size,
            )

        for size in (16, 32, 64, 128, 256, 512, 1024):
            emit(tile, f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png", size)

        emit(tile, "assets/icons/tray.png", 64)
        emit_status("assets/icons/tray_template.png", 36)

    for k in sorted(written):
        print(f"{k}  {written[k]}")


if __name__ == "__main__":
    main()
