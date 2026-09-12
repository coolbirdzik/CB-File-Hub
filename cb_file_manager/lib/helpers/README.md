# Helpers & Utils Directory Structure

Thư mục helpers và utils được tổ chức lại để dễ quản lý và maintain hơn.

## Cấu trúc thư mục

```
helpers/
├── index.dart                  # Main export file
├── core/                      # Core utilities
│   ├── filesystem_utils.dart  # File system operations
│   ├── io_extensions.dart     # IO extensions
│   ├── path_utils.dart        # Path utilities
│   ├── app_path_helper.dart   # App path management
│   └── user_preferences.dart  # User settings
├── media/                     # Media processing & thumbnails
│   ├── fc_native_video_thumbnail.dart
│   ├── folder_thumbnail_service.dart
│   ├── thumbnail_*.dart
│   └── video_thumbnail_helper.dart
├── network/                   # Network & streaming
│   ├── streaming_helper.dart
│   ├── network_*.dart
│   ├── *smb*playback_helper.dart
│   └── win32_smb_helper.dart
├── files/                     # File management
│   ├── file_*.dart
│   ├── external_app_helper.dart
│   ├── folder_sort_manager.dart
│   └── trash_manager.dart
├── tags/                      # Tag management
│   ├── tag_manager.dart
│   ├── tag_color_manager.dart
│   └── batch_tag_manager.dart
└── ui/                        # UI & performance
    ├── frame_timing_optimizer.dart
    └── ui_blocking_prevention.dart

utils/
└── app_logger.dart            # Centralized logging framework
```

## Cách sử dụng

### Import toàn bộ helpers:

```dart
import 'package:cb_file_manager/helpers/index.dart';
```

### Import theo category:

```dart
// Core utilities
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';

// Media helpers
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';

// Network helpers
import 'package:cb_file_manager/helpers/network/streaming_helper.dart';
```

### Logging (Utils):

**QUAN TRỌNG**: Không bao giờ sử dụng `print()` trong production code. Luôn sử dụng logging framework:

```dart
import 'package:cb_file_manager/utils/app_logger.dart';

// Các mức độ log
AppLogger.debug('Chi tiết debug');
AppLogger.info('Thông tin chung');
AppLogger.warning('Cảnh báo');
AppLogger.error('Lỗi xảy ra', error: exception, stackTrace: stackTrace);
AppLogger.fatal('Lỗi nghiêm trọng');
```

**Lợi ích:**
- Structured logging với timestamps và màu sắc
- Các mức độ log để lọc (debug, info, warning, error, fatal)
- Tự động theo dõi method call traces
- Stack traces cho errors
- Sẵn sàng cho production với error context đầy đủ

## Thay đổi từ cấu trúc cũ

- **25+ files** trong root -> **6 thư mục** được tổ chức theo chức năng
- Dễ dàng tìm kiếm và maintain code
- Import paths rõ ràng hơn
- Có thể mở rộng từng category độc lập

## Migration Guide

Khi cập nhật import paths, thay:

```dart
// Cũ
import 'package:cb_file_manager/helpers/streaming_helper.dart';

// Mới
import 'package:cb_file_manager/helpers/network/streaming_helper.dart';
// hoặc
import 'package:cb_file_manager/helpers/index.dart';
```
