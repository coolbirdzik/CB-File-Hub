import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video-opening settings have complete localized copy', () {
    final localizations = <AppLocalizations>[
      EnglishLocalizations(),
      VietnameseLocalizations(),
    ];

    for (final l10n in localizations) {
      expect(l10n.useSystemDefaultForVideo, isNotEmpty);
      expect(l10n.useSystemDefaultForVideoDescription, isNotEmpty);
      expect(l10n.useSystemDefaultForVideoEnabled, isNotEmpty);
      expect(l10n.useSystemDefaultForVideoDisabled, isNotEmpty);
      expect(l10n.openVideoInNewWindow, isNotEmpty);
      expect(l10n.openVideoInNewWindowDescription, isNotEmpty);
      expect(l10n.openVideoInNewWindowEnabled, isNotEmpty);
      expect(l10n.openVideoInNewWindowDisabled, isNotEmpty);
    }

    expect(
      EnglishLocalizations().useSystemDefaultForVideo,
      isNot(VietnameseLocalizations().useSystemDefaultForVideo),
    );
    expect(
      EnglishLocalizations().openVideoInNewWindow,
      isNot(VietnameseLocalizations().openVideoInNewWindow),
    );
  });

  test('file thumbnail fit setting has complete localized copy', () {
    final localizations = <AppLocalizations>[
      EnglishLocalizations(),
      VietnameseLocalizations(),
    ];

    for (final l10n in localizations) {
      expect(l10n.fileThumbnailFit, isNotEmpty);
      expect(l10n.fileThumbnailFitDescription, isNotEmpty);
      expect(l10n.thumbnailFitCover, isNotEmpty);
      expect(l10n.thumbnailFitContain, isNotEmpty);
    }

    expect(
      EnglishLocalizations().fileThumbnailFit,
      isNot(VietnameseLocalizations().fileThumbnailFit),
    );
  });
}
