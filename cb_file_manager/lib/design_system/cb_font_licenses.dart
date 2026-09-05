import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;

/// Registers the licences of the fonts bundled in `assets/fonts/`.
///
/// Both Inter and JetBrains Mono are SIL Open Font License 1.1. The OFL is
/// permissive about commercial use and about shipping the font inside an
/// application, but it does require the licence to travel with the font —
/// and shipping the app binary is a redistribution. Registering the text here
/// puts it in Flutter's standard licence page (`showLicensePage`), which is
/// where a user would look for it.
///
/// Call once during startup, after the binding is initialised.
void registerCbFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks(const <String>[
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/fonts/JetBrainsMono-OFL.txt'));
  });
}
