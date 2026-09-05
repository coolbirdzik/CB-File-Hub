import 'package:flutter/material.dart';
import 'skeleton.dart';

/// Unified helper class for skeleton loading across all platforms
/// Provides consistent skeleton UI for files, albums, videos, and thumbnails
/// Automatically adapts to mobile/desktop environments
class SkeletonHelper {
  /// Create a file list skeleton with album design
  /// Automatically wraps in Card on desktop for elevated appearance
  ///
  /// Parameters:
  /// - [itemCount]: Number of skeleton items to show (default: 12)
  /// - [wrapInCardOnDesktop]: Whether to wrap in Card on desktop (default: true)
  static Widget fileList({
    int itemCount = 12,
    bool wrapInCardOnDesktop = true,
  }) {
    return Skeleton(
      type: SkeletonType.albumList,
      itemCount: itemCount,
      isAlbum: true,
      wrapInCardOnDesktop: wrapInCardOnDesktop,
    );
  }

  /// Create a file grid skeleton with album design
  /// Consistent across mobile and desktop platforms
  ///
  /// Parameters:
  /// - [crossAxisCount]: Number of columns in grid (default: 3)
  /// - [itemCount]: Number of skeleton items to show (default: 12)
  static Widget fileGrid({int crossAxisCount = 3, int itemCount = 12}) {
    return Skeleton(
      type: SkeletonType.albumGrid,
      crossAxisCount: crossAxisCount,
      itemCount: itemCount,
      isAlbum: true,
    );
  }

  /// Create an album list skeleton
  /// Automatically wraps in Card on desktop for elevated appearance
  ///
  /// Parameters:
  /// - [itemCount]: Number of skeleton items to show (default: 12)
  /// - [wrapInCardOnDesktop]: Whether to wrap in Card on desktop (default: true)
  static Widget albumList({
    int itemCount = 12,
    bool wrapInCardOnDesktop = true,
  }) {
    return Skeleton(
      type: SkeletonType.albumList,
      itemCount: itemCount,
      isAlbum: true,
      wrapInCardOnDesktop: wrapInCardOnDesktop,
    );
  }

  /// Create an album grid skeleton
  /// Consistent across mobile and desktop platforms
  ///
  /// Parameters:
  /// - [crossAxisCount]: Number of columns in grid (default: 3)
  /// - [itemCount]: Number of skeleton items to show (default: 12)
  static Widget albumGrid({int crossAxisCount = 3, int itemCount = 12}) {
    return Skeleton(
      type: SkeletonType.albumGrid,
      crossAxisCount: crossAxisCount,
      itemCount: itemCount,
      isAlbum: true,
    );
  }

  /// Create a single skeleton box for thumbnails, images, etc.
  /// Perfect for loading states of individual items
  ///
  /// Parameters:
  /// - [width]: Width of the skeleton box
  /// - [height]: Height of the skeleton box
  /// - [borderRadius]: Custom border radius (default: 8px)
  static Widget box({
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    return Skeleton(
      type: SkeletonType.single,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }

  /// Create a video thumbnail skeleton
  /// Optimized for video preview loading states
  ///
  /// Parameters:
  /// - [width]: Width of the video thumbnail
  /// - [height]: Height of the video thumbnail
  /// - [borderRadius]: Custom border radius (default: 8px)
  static Widget videoThumbnail({
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    return Skeleton(
      type: SkeletonType.videoThumbnail,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }

  /// Create a responsive skeleton that adapts to view mode
  /// Automatically switches between grid and list layouts
  /// Wraps in Card on desktop for list view
  ///
  /// Parameters:
  /// - [isGridView]: Whether to show grid or list skeleton
  /// - [isAlbum]: Whether this is for album content (default: false)
  /// - [crossAxisCount]: Number of columns for grid view (default: 3)
  /// - [itemCount]: Number of skeleton items to show (default: 12)
  /// - [wrapInCardOnDesktop]: Whether to wrap list items in Card on desktop (default: true)
  static Widget responsive({
    required bool isGridView,
    bool isAlbum = false,
    int? crossAxisCount,
    int itemCount = 12,
    bool wrapInCardOnDesktop = true,
  }) {
    if (isGridView) {
      return isAlbum
          ? albumGrid(crossAxisCount: crossAxisCount ?? 3, itemCount: itemCount)
          : fileGrid(crossAxisCount: crossAxisCount ?? 3, itemCount: itemCount);
    } else {
      return isAlbum
          ? albumList(
              itemCount: itemCount,
              wrapInCardOnDesktop: wrapInCardOnDesktop,
            )
          : fileList(
              itemCount: itemCount,
              wrapInCardOnDesktop: wrapInCardOnDesktop,
            );
    }
  }

  /// Create a media gallery skeleton (for images/videos)
  /// Adapts to grid or list view mode
  ///
  /// Parameters:
  /// - [isGrid]: Whether to show grid or list layout
  /// - [crossAxisCount]: Number of columns for grid view (default: 3)
  /// - [itemCount]: Number of skeleton items to show (default: 12)
  static Widget mediaGallery({
    required bool isGrid,
    int crossAxisCount = 3,
    int itemCount = 12,
  }) {
    return responsive(
      isGridView: isGrid,
      isAlbum: false,
      crossAxisCount: crossAxisCount,
      itemCount: itemCount,
      wrapInCardOnDesktop: true,
    );
  }

  /// Create a masonry skeleton for Pinterest-style layouts
  /// Shows varying heights for a more dynamic appearance
  ///
  /// Parameters:
  /// - [crossAxisCount]: Number of columns in masonry grid (default: 3)
  /// - [itemCount]: Number of skeleton items to show (default: 12)
  static Widget masonry({int crossAxisCount = 3, int itemCount = 12}) {
    return Skeleton(
      type: SkeletonType.masonry,
      crossAxisCount: crossAxisCount,
      itemCount: itemCount,
    );
  }
}
