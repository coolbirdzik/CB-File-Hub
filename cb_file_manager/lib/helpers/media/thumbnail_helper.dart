import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'video_thumbnail_helper.dart';

/// Adapter class để đảm bảo tương thích với mã hiện tại
/// Chuyển tiếp tất cả các lệnh tạo thumbnail sang VideoThumbnailHelper
class ThumbnailTaskManager {
  static final ThumbnailTaskManager _instance =
      ThumbnailTaskManager._internal();
  factory ThumbnailTaskManager() => _instance;
  ThumbnailTaskManager._internal();

  // Kích thước mặc định của thumbnail để giảm tải hệ thống
  static const int thumbnailQuality = 70;
  static const int maxThumbnailSize = 200;

  /// Thêm một tác vụ tạo thumbnail vào hàng đợi
  void addTask({
    required String videoPath,
    required Function(String?) onComplete,
    int priority = 0,
  }) async {
    // Sử dụng VideoThumbnailHelper để tạo thumbnail
    final thumbnailPath = await VideoThumbnailHelper.generateThumbnail(
      videoPath,
      isPriority: priority > 0,
    );
    onComplete(thumbnailPath);
  }

  /// Xóa hàng đợi
  void clearQueue() {
    // No-op khi sử dụng VideoThumbnailHelper
  }

  /// Lấy thumbnail từ memory cache nếu có
  static Uint8List? getFromMemoryCache(String videoPath) {
    // Không còn sử dụng memory cache riêng, chỉ tương thích API
    return null;
  }

  /// Tiền tải thumbnail cho danh sách video đầu tiên
  static Future<void> preloadFirstBatch(
    List<String> videoPaths, {
    int count = 20,
  }) async {
    final pathsToPreload = videoPaths.take(count).toList();

    for (final path in pathsToPreload) {
      // Tạo thumbnail không đồng bộ
      unawaited(
        VideoThumbnailHelper.generateThumbnail(path, isPriority: false),
      );
    }

    // Không chờ đợi các tác vụ hoàn thành
    return Future.value();
  }
}

/// Class adapter để duy trì tương thích ngược
class ThumbnailHelper {
  // Cache để lưu trữ các thumbnail đã tạo
  static final Map<String, String> _thumbnailCache = {};

  /// Hàm này luôn trả về true vì không cần FFmpeg nữa
  static Future<bool> ensureFFmpegInstalled([BuildContext? context]) async {
    return true;
  }

  /// Tạo widget hiển thị thumbnail của video
  static Widget buildVideoThumbnail({
    required String videoPath,
    required Function(String?) onThumbnailGenerated,
    required Widget Function() fallbackBuilder,
    double width = 300,
    double height = 300,
    bool isVisible = true,
    bool forceRegenerate = false,
  }) {
    if (!isVisible) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: fallbackBuilder(),
      );
    }

    // Đảm bảo gọi callback khi thumbnail được tạo
    Future.delayed(Duration.zero, () async {
      // Đánh dấu là force regenerate để đảm bảo không dùng thumbnail cũ
      final path = await VideoThumbnailHelper.generateThumbnail(
        videoPath,
        isPriority: true,
        forceRegenerate: forceRegenerate,
        thumbnailSize: width.toInt(),
      );
      onThumbnailGenerated(path);
    });

    // Sử dụng VideoThumbnailHelper để tạo và hiển thị thumbnail
    return VideoThumbnailHelper.buildVideoThumbnail(
      videoPath: videoPath,
      width: width,
      height: height,
      isPriority: true, // Đánh dấu là ưu tiên cao để tạo ngay
      forceRegenerate: forceRegenerate, // Truyền lại tham số force
      fallbackBuilder: fallbackBuilder,
    );
  }

  /// Xóa toàn bộ cache thumbnail
  static Future<void> clearCache() async {
    await VideoThumbnailHelper.clearCache();
    _thumbnailCache.clear();
  }
}

// Lớp đơn giản để giữ tương thích với mã hiện tại
class OptimizedLazyThumbnailWidget extends StatelessWidget {
  final String videoPath;
  final double width;
  final double height;
  final Function(String?) onThumbnailGenerated;
  final Widget Function() fallbackBuilder;
  final bool forceRegenerate;

  const OptimizedLazyThumbnailWidget({
    super.key,
    required this.videoPath,
    required this.width,
    required this.height,
    required this.onThumbnailGenerated,
    required this.fallbackBuilder,
    this.forceRegenerate = false,
  });

  @override
  Widget build(BuildContext context) {
    // Tự động gọi onThumbnailGenerated khi thumbnail được tạo
    Future.delayed(Duration.zero, () async {
      // Đánh dấu là ưu tiên cao và có thể force regenerate để đảm bảo thumbnail được tạo mới
      final path = await VideoThumbnailHelper.generateThumbnail(
        videoPath,
        isPriority: true,
        forceRegenerate: forceRegenerate,
        thumbnailSize: width.toInt(),
      );
      onThumbnailGenerated(path);
    });

    return VideoThumbnailHelper.buildVideoThumbnail(
      videoPath: videoPath,
      width: width,
      height: height,
      isPriority: true, // Đánh dấu là ưu tiên cao để tạo ngay lập tức
      forceRegenerate: forceRegenerate, // Đảm bảo tạo mới nếu cần
      fallbackBuilder: fallbackBuilder,
    );
  }
}
