# Local AI subtitle screenshots

These are **production-widget renders with demo data**, not captures of a live
native player or recordings of model inference. The native computer-use helper
was unavailable during capture. An original procedural sky illustration stands
in for a video frame; the Japanese cue and its English/Vietnamese translations
are authored samples. They illustrate the product UI and make no accuracy or
latency claim. No personal video, file path, audio or transcript is included.

Each language (`en`, `vi`) has three 1600 × 900 PNGs:

- `player.png`: centered app branding, bilingual captions, the single seek
  track with AI tint, and the CC control.
- `progress.png`: the CC menu showing translation, language, processed range,
  cache status, settings and regeneration.
- `models.png`: real subtitle settings widgets with demo model metadata,
  language choices and an isolated SQLite subtitle cache.

The capture reuses `VideoPlayerAppBar`, `SubtitleCaptionOverlay`,
`SubtitleControlButton`, `SubtitleSeekTrackShape`, `SubtitleSettingsPanel` and
the actual cache widget. Only the scene and playback state are fixtures. Model
files are not loaded or downloaded. Preferences are mocked in the test process;
cache data uses a temporary database, deleted at the end.

From `cb_file_manager/`:

```powershell
flutter test --no-pub tool/capture_subtitle_screenshots_test.dart --dart-define=CB_CAPTURE_SCREENSHOTS=true
```

This is an opt-in widget renderer, not a project E2E runner. It loads the app's
bundled fonts and, on Windows, `C:/Windows/Fonts/msgothic.ttc` for Japanese.
Override `CB_SUBTITLE_JAPANESE_FONT` with a suitable local font on other hosts.
The font file itself is not copied or redistributed.

Then, from the repository root:

```powershell
python scripts/make_promo_images.py --feature subtitles --languages en,vi,tr,zh --website-output website/static/media
```

This adds slots `13_*` (player) and `14_*` (models) to the desktop promo sets.
Turkish and Chinese promo copy uses the English UI captures, matching the
existing torrent promo fallback. It also exports localized website previews
and 1200 × 675 share images. Other promo images and Store hero art are untouched.
Store listings are not submitted or changed by these commands.
