/// Remove only the combined runner's namespace. Preserve the inner group and
/// test description, used by existing dashboard/Allure suite categorization.
String withoutDesktopSuitePrefix(String name) => name.replaceFirst(
  RegExp(
    r'^(?:app|video_thumbnails|media_kit_playback|ffmpeg_thumbnail|file_drag_drop|breadcrumb_address_bar_overflow|torrent_library|semantics_stability|tooltip_semantics|video_player_chrome_semantics) ',
  ),
  '',
);
