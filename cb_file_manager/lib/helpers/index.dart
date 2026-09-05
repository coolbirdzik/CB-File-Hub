/// Main exports for helpers package - organized by category
/// This file provides a single entry point for importing all helper classes
library;

// Core utilities
export 'core/filesystem_utils.dart';
export 'core/io_extensions.dart';
export 'core/path_utils.dart';
export 'core/app_path_helper.dart';
export 'core/user_preferences.dart';

// Media & Thumbnails
export 'media/fc_native_video_thumbnail.dart';
export 'media/folder_thumbnail_service.dart';
export 'media/media_kit_audio_helper.dart';
export 'media/thumbnail_background_isolate.dart';
export 'media/thumbnail_helper.dart';
export 'media/thumbnail_queue_manager.dart';
export 'media/video_thumbnail_helper.dart';

// Network & Streaming
export 'network/native_vlc_direct_helper.dart';
export 'network/network_file_cache_service.dart';
export 'network/network_file_helper.dart';
export 'network/network_thumbnail_helper.dart';
export 'network/smb_native_thumbnail_helper.dart';
export 'network/streaming_helper.dart';
export 'network/vlc_direct_smb_helper.dart';
export 'network/win32_smb_helper.dart';

// File Management
export 'files/external_app_helper.dart';
export 'files/file_icon_helper.dart';
export 'files/file_type_helper.dart';
export 'files/folder_sort_manager.dart';
export 'files/trash_manager.dart';
export 'files/windows_app_icon.dart';

// Tag Management
export 'tags/batch_tag_manager.dart';
export 'tags/tag_color_manager.dart';
export 'tags/tag_manager.dart';

// UI & Performance
export 'ui/frame_timing_optimizer.dart';
export 'ui/ui_blocking_prevention.dart';
