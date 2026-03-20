import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ThumbnailStrip extends StatefulWidget {
  final List<File> images;
  final int currentIndex;
  final Function(int) onThumbnailTap;
  final Future<Uint8List?> Function(File) loadAndCacheImage;

  const ThumbnailStrip({
    Key? key,
    required this.images,
    required this.currentIndex,
    required this.onThumbnailTap,
    required this.loadAndCacheImage,
  }) : super(key: key);

  @override
  State<ThumbnailStrip> createState() => _ThumbnailStripState();
}

class _ThumbnailStripState extends State<ThumbnailStrip> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Đảm bảo thumbnail đang chọn luôn hiển thị sau khi widget được tạo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentIndex();
    });
  }

  @override
  void didUpdateWidget(ThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Cập nhật vị trí cuộn khi index thay đổi
    if (oldWidget.currentIndex != widget.currentIndex) {
      _scrollToCurrentIndex();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentIndex() {
    if (widget.images.isEmpty || !_scrollController.hasClients) return;

    // Độ rộng của mỗi thumbnail + lề
    const double thumbnailWidth = 54.0 + 8.0;

    // Vị trí để cuộn đến (đặt thumbnail hiện tại ở giữa)
    final double targetPosition = widget.currentIndex * thumbnailWidth -
        (_scrollController.position.viewportDimension / 2) +
        (thumbnailWidth / 2);

    // Giới hạn vị trí cuộn trong phạm vi hợp lệ
    final double maxScroll = _scrollController.position.maxScrollExtent;
    final double offset = targetPosition.clamp(0.0, maxScroll);

    // Cuộn đến vị trí mục tiêu
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      itemCount: widget.images.length,
      itemBuilder: (context, index) {
        final file = widget.images[index];
        final bool isCurrentImage = index == widget.currentIndex;

        return GestureDetector(
          onTap: () => widget.onThumbnailTap(index),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            decoration: BoxDecoration(
              border: Border.all(
                color: isCurrentImage
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2.0,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: FutureBuilder<Uint8List?>(
              future: widget.loadAndCacheImage(file),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    width: 54,
                    height: 54,
                    color: Theme.of(context).colorScheme.onSurface,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white70,
                        strokeWidth: 2.0,
                      ),
                    ),
                  );
                } else if (snapshot.hasError || !snapshot.hasData) {
                  return Container(
                    width: 54,
                    height: 54,
                    color: Theme.of(context).colorScheme.onSurface,
                    child: const Icon(
                      PhosphorIconsLight.imageBroken,
                      color: Colors.white70,
                    ),
                  );
                } else {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: Opacity(
                      opacity: isCurrentImage ? 1.0 : 0.7,
                      child: Image.memory(
                        snapshot.data!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}
