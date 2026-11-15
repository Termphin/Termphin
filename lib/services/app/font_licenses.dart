import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Each bundled font's licence file in `assets/fonts/`, with the fonts it
/// covers. The OFL and the MIT licence both ask for their text to travel with
/// the font; listing them here puts it on the app's licences screen next to
/// the packages Flutter lists by itself.
const kFontLicenses = <String, List<String>>{
  'assets/fonts/Epilogue-OFL.txt': ['Epilogue'],
  'assets/fonts/FiraCode-OFL.txt': ['Fira Code'],
  'assets/fonts/Geist-OFL.txt': ['Geist'],
  'assets/fonts/Hack-MIT.txt': ['Hack'],
  'assets/fonts/HubotSans-MIT.txt': ['Hubot Sans'],
  'assets/fonts/Inter-OFL.txt': ['Inter'],
  'assets/fonts/JetBrainsMono-OFL.txt': ['JetBrains Mono'],
  'assets/fonts/NerdFonts-MIT.txt': ['Nerd Fonts'],
  'assets/fonts/NotoSansSymbols2-OFL.txt': ['Noto Sans Symbols 2'],
  'assets/fonts/SourceCodePro-OFL.txt': ['Source Code Pro'],
  'assets/fonts/UbuntuMono-UFL.txt': ['Ubuntu Mono'],
};

/// Adds the fonts' licences to [LicenseRegistry]. Read only when the
/// licences screen asks, so it costs nothing at startup.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: file, value: fonts) in kFontLicenses.entries) {
      yield LicenseEntryWithLineBreaks(
        fonts,
        await rootBundle.loadString(file),
      );
    }
  });
}
