## Filesystem & Media Access

- **Filesystem API**: `helpers/core/filesystem_utils.dart` centralizes directory listing, search, and recursive scanning; includes mobile-specific fallbacks for empty gallery paths.
- **Album Pipeline**: `services/album_*` family uses isolates and background scanners to build smart/featured albums.
- **Streaming**: `services/streaming_service_manager.dart` coordinates `StreamingService` implementations (media_kit-backed) and ensures `MediaKitAudioHelper` is configured for Windows.
- **PiP Windows**: `ui/components/video/pip_window/desktop_pip_window.dart` and `services/pip_window_service.dart` support desktop picture-in-picture playback.

### Hybrid Thumbnail Generation

The application employs a hybrid strategy for generating video thumbnails to maximize performance across platforms:

1.  **Windows (Native C++ Plugin)**:
    - **Implementation**: `windows/runner/fc_native_video_thumbnail_plugin.cpp`
    - **Mechanism**: Leverages Windows Native APIs (`IShellItemImageFactory`, `MediaFoundation`) directly via C++.
    - **Performance**: Extremely fast and efficient as it bypasses Dart-side processing and utilizes OS-level decoders.
    - **Dart Wrapper**: `helpers/media/fc_native_video_thumbnail.dart` acts as the bridge to the native plugin.

2.  **Other Platforms (Android/iOS/Linux/macOS)**:
    - **Implementation**: Uses the `video_thumbnail` package from pub.dev.
    - **Mechanism**: Relies on the package's implementation (often ffmpeg-based or platform-specific APIs) to generate thumbnails.
    - **Fallback**: Serves as the standard solution where the custom Windows native plugin is not applicable.

3.  **Orchestration**:
    - **Controller**: `helpers/media/video_thumbnail_helper.dart`
    - **Logic**: Detects the operating system and routes the thumbnail generation request to either the native Windows plugin or the `video_thumbnail` package. This ensures the best possible experience on Windows while maintaining cross-platform compatibility.

_Last reviewed: 2026-03-07_
