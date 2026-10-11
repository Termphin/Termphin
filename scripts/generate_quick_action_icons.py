#!/usr/bin/env python3
"""
Generate quick action icon assets for Termphin.

Takes the in-app profile avatar SVGs from assets/icons/profile_avatars/, produces:
  - Android:
    - 84 foreground PNGs (colored icon on transparent background, one per icon+color) ->
      res/drawable/qa_fg_{icon}_{color}.png
    - 84 adaptive-icon XMLs referencing foreground + white background ->
      res/drawable/qa_{icon}_{color}.xml
  - iOS:
    - 12 template imagesets (pure alpha mask glyph, RGB black, universal idiom) ->
      ios/Runner/Assets.xcassets/QuickActions/qa_{icon}.imageset/

Android background is always white; icon is rendered in the profile's accent color.
iOS template images are tinted by the system.

Requirements:
  Pillow cairosvg (automatically provisioned in ~/.cache/termphin_venv if needed)
"""

import io
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# If cairosvg or Pillow are not installed, bootstrap a virtualenv in ~/.cache/termphin_venv
try:
    import cairosvg
    from PIL import Image
except ImportError:
    cache_venv = Path.home() / ".cache" / "termphin_venv"
    venv_py = cache_venv / "bin" / "python3"
    if not venv_py.exists():
        print("Provisioning virtualenv with cairosvg and Pillow...")
        subprocess.run([sys.executable, "-m", "venv", str(cache_venv)], check=True)
        subprocess.run(
            [str(cache_venv / "bin" / "pip"), "install", "cairosvg", "Pillow"],
            check=True,
        )
    os.execv(str(venv_py), [str(venv_py)] + sys.argv)

ICON_SIZE = 96
ICON_FRACTION = 0.52

ICON_MAP = {
    "desktop": "desktop",
    "hardDrives": "hard_drives",
    "cloud": "cloud",
    "database": "database",
    "globe": "globe",
    "house": "house",
    "terminal": "terminal",
    "robot": "robot",
    "lightning": "lightning",
    "shieldCheck": "shield_check",
    "gameController": "game_controller",
    "cpu": "cpu",
}

COLORS = [
    "4da3ff",
    "4ade80",
    "8b5cf6",
    "f59e0b",
    "f87171",
    "06b6d4",
    "f472b6",
]

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SVG_DIR = PROJECT_ROOT / "assets" / "icons" / "profile_avatars"
OUT_DIR = PROJECT_ROOT / "android" / "app" / "src" / "main" / "res" / "drawable"
IOS_OUT_DIR = (
    PROJECT_ROOT / "ios" / "Runner" / "Assets.xcassets" / "QuickActions"
)

ADAPTIVE_XML = """\
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/qa_bg_white" />
    <foreground android:drawable="@drawable/qa_fg_{icon}_{color}" />
</adaptive-icon>
"""

IOS_CONTENTS_JSON = """\
{{
  "images" : [
    {{
      "filename" : "qa_{icon}.png",
      "idiom" : "universal"
    }}
  ],
  "info" : {{
    "author" : "xcode",
    "version" : 1
  }},
  "properties" : {{
    "template-rendering-intent" : "template"
  }}
}}
"""


def colorize_svg(svg_text: str, hex_color: str) -> str:
    return re.sub(r"#fff\b", f"#{hex_color}", svg_text, flags=re.IGNORECASE)


def render_foreground(svg_text: str, hex_color: str) -> Image.Image:
    colored = colorize_svg(svg_text, hex_color)
    render_size = int(ICON_SIZE * ICON_FRACTION)
    png_data = cairosvg.svg2png(
        bytestring=colored.encode("utf-8"),
        output_width=render_size,
        output_height=render_size,
    )
    icon = Image.open(io.BytesIO(png_data)).convert("RGBA")
    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    offset_x = (ICON_SIZE - icon.width) // 2
    offset_y = (ICON_SIZE - icon.height) // 2
    canvas.paste(icon, (offset_x, offset_y), icon)
    return canvas


def render_ios_template(svg_text: str) -> Image.Image:
    render_size = int(ICON_SIZE * ICON_FRACTION)
    png_data = cairosvg.svg2png(
        bytestring=svg_text.encode("utf-8"),
        output_width=render_size,
        output_height=render_size,
    )
    icon = Image.open(io.BytesIO(png_data)).convert("RGBA")
    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    offset_x = (ICON_SIZE - icon.width) // 2
    offset_y = (ICON_SIZE - icon.height) // 2
    canvas.paste(icon, (offset_x, offset_y), icon)
    alpha = canvas.split()[3]
    black = Image.new("L", (ICON_SIZE, ICON_SIZE), 0)
    return Image.merge("RGBA", (black, black, black, alpha))


def generate():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Clean up any legacy or stale qa_ files (e.g. qa_*_3a7bd5.*)
    valid_files = set()
    for icon_id in ICON_MAP:
        for color in COLORS:
            valid_files.add(f"qa_{icon_id.lower()}_{color}.xml")
            valid_files.add(f"qa_fg_{icon_id.lower()}_{color}.png")

    for f in OUT_DIR.glob("qa_*"):
        if f.name not in valid_files:
            print(f"  [RM] Stale {f.name}")
            f.unlink()

    fg_count = 0
    xml_count = 0

    for icon_id, svg_file in ICON_MAP.items():
        svg_path = SVG_DIR / f"{svg_file}.svg"
        if not svg_path.exists():
            raise FileNotFoundError(f"SVG not found: {svg_path}")
        svg_text = svg_path.read_text(encoding="utf-8")

        for color in COLORS:
            fg_name = f"qa_fg_{icon_id.lower()}_{color}"
            fg = render_foreground(svg_text, color)
            fg_path = OUT_DIR / f"{fg_name}.png"
            fg.save(fg_path, "PNG")
            fg_count += 1
            print(f"  [FG {fg_count}] {fg_name}.png")

            xml_name = f"qa_{icon_id.lower()}_{color}"
            xml_path = OUT_DIR / f"{xml_name}.xml"
            xml_path.write_text(
                ADAPTIVE_XML.format(icon=icon_id.lower(), color=color),
                encoding="utf-8",
            )
            xml_count += 1

    # Clean up any stale qa_*.imageset directories in iOS output directory
    IOS_OUT_DIR.mkdir(parents=True, exist_ok=True)
    valid_ios_dirs = {f"qa_{icon_id.lower()}.imageset" for icon_id in ICON_MAP}
    for d in IOS_OUT_DIR.glob("qa_*.imageset"):
        if d.name not in valid_ios_dirs:
            print(f"  [RM] Stale {d.name}")
            if d.is_dir():
                shutil.rmtree(d)
            else:
                d.unlink()

    ios_catalog_contents = IOS_OUT_DIR / "Contents.json"
    if not ios_catalog_contents.exists():
        ios_catalog_contents.write_text(
            '{"info":{"author":"xcode","version":1}}',
            encoding="utf-8",
        )

    ios_count = 0
    for icon_id, svg_file in ICON_MAP.items():
        svg_path = SVG_DIR / f"{svg_file}.svg"
        if not svg_path.exists():
            raise FileNotFoundError(f"SVG not found: {svg_path}")
        svg_text = svg_path.read_text(encoding="utf-8")

        icon_name = icon_id.lower()
        imageset_dir = IOS_OUT_DIR / f"qa_{icon_name}.imageset"
        imageset_dir.mkdir(parents=True, exist_ok=True)

        contents_path = imageset_dir / "Contents.json"
        contents_path.write_text(
            IOS_CONTENTS_JSON.format(icon=icon_name),
            encoding="utf-8",
        )

        png_path = imageset_dir / f"qa_{icon_name}.png"
        template_img = render_ios_template(svg_text)
        template_img.save(png_path, "PNG")
        ios_count += 1
        print(f"  [IOS {ios_count}] qa_{icon_name}.imageset")

    print(
        f"\nDone! {fg_count} foregrounds + {xml_count} adaptive icons"
        f" in {OUT_DIR.relative_to(PROJECT_ROOT)}"
        f", {ios_count} imagesets in {IOS_OUT_DIR.relative_to(PROJECT_ROOT)}"
    )


if __name__ == "__main__":
    generate()
