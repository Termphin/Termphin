# phosphor_flutter (vendored fork)

Local fork of [`phosphor_flutter`](https://pub.dev/packages/phosphor_flutter) 2.1.0.

## Why this exists

Flutter 3.44 made `IconData` a `final class`. Upstream 2.1.0 (the latest published
version, and apparently unmaintained) declares `class PhosphorIconData extends IconData`,
so the app no longer compiles against it:

```
phosphor_icon_data.dart:5:32: Error: The class 'IconData' can't be extended
outside of its library because it's a final class.
```

## What changed

* `PhosphorIconData` / `PhosphorFlatIconData` / `PhosphorDuotoneIconData` are gone.
  Every icon constant is now a plain `const IconData(...)` with the same code point,
  font family, font package and `matchTextDirection: true` as before.
* The `PhosphorIcon` widget (which only existed to layer duotone icons) is gone —
  use the regular `Icon` widget.
* Only the **Fill** and **Regular** styles are vendored, since those are the only
  ones the app uses. Thin / Light / Bold / Duotone, the combined `PhosphorIcons`
  accessor and their fonts were dropped to keep the repo small.

## Adding another style

Copy `lib/src/phosphor_icons_<style>.dart` and `lib/fonts/Phosphor-<Style>.ttf` from
the pub cache copy of 2.1.0, then apply the same rewrite:

```
sed -e "s/PhosphorFlatIconData(\(0x[0-9a-f]*\), '\([A-Za-z]*\)')/IconData(\1, fontFamily: 'Phosphor\2', fontPackage: 'phosphor_flutter', matchTextDirection: true)/g" \
    -e "/import 'package:phosphor_flutter\/src\/phosphor_icon_data.dart';/d"
```

Then register the font family in this package's `pubspec.yaml` and export the file
from `lib/phosphor_flutter.dart`.

Upstream is MIT licensed; see `LICENSE`.
