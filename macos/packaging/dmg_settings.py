"""The macOS DMG's window, for dmgbuild (macos-dmg.yml packs it).

    dmgbuild -s macos/packaging/dmg_settings.py \
        -D app=dmg/Termphin.app -D background=background.tiff Termphin Termphin.dmg

The app and an Applications link side by side on dmg-background.png (and
its @2x), whose arrow joins the two positions below - move one, redraw the
background. dmgbuild writes the Finder layout
itself, with no Finder running, which a CI runner cannot be relied on for.
"""
import os.path

application = defines.get("app", "dmg/Termphin.app")
name = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
hide_extensions = [name]

icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")
background = defines.get("background", "macos/packaging/dmg-background.png")

window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True

icon_size = 128
text_size = 13
icon_locations = {
    name: (170, 205),
    "Applications": (490, 205),
}
