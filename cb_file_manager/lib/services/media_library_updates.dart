import 'package:flutter/foundation.dart';

/// Invalidates Home previews across tabs after library metadata changes.
class MediaLibraryUpdates {
  static final revision = ValueNotifier<int>(0);

  static void notifyChanged() => revision.value++;
}
