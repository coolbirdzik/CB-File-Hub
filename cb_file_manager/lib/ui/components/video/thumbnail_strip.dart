import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/gestures.dart'; // Thêm import cho gesture detector

class ThumbnailStrip extends StatefulWidget {
  /// Danh sách tất cả các ảnh
  final List<File> images;

  /// Chỉ số ảnh đang được hiển thị
  final int currentIndex;

  /// Callback khi nhấp vào thumbnail
  final Function(int) onThumbnailTap;

  /// Kích thước của thumbnail
  final double thumbnailSize;

  /// Khoảng cách giữa các thumbnail
  final double spacing;

  const ThumbnailStrip({
    Key? key,
    required this.images,
    required this.currentIndex,
    required this.onThumbnailTap,
    this.thumbnailSize = 54.0,
    this.spacing = 4.0,
  }) : super(key: key);

  @override
  State<ThumbnailStrip> createState() => _ThumbnailStripState();
}

class _ThumbnailStripState extends State<ThumbnailStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Đặt lịch để cuộn đến ảnh hiện tại sau khi build hoàn tất
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedItem();
    });
  }

  @override
  void didUpdateWidget(ThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nếu index thay đổi, cuộn đến vị trí mới
    if (oldWidget.currentIndex != widget.currentIndex) {
      // Thêm một độ trễ nhỏ để đảm bảo UI đã cập nhật
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _scrollToSelectedItem();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Cuộn thanh thumbnail để hiển thị ảnh được chọn ở vị trí trung tâm
  void _scrollToSelectedItem() {
    if (!_scrollController.hasClients || widget.images.isEmpty) return;

    final double itemWidth = widget.thumbnailSize + (widget.spacing * 2);
    final double screenWidth = MediaQuery.of(context).size.width;

    // Tính vị trí mục tiêu: đặt thumbnail hiện tại ở giữa màn hình
    final double targetPosition =
        (widget.currentIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);

    // Giới hạn vị trí nằm trong phạm vi hợp lệ
    final double maxScroll = _scrollController.position.maxScrollExtent;
    final double scrollTo = targetPosition.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      scrollTo,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        // Xử lý sự kiện cuộn chuột
        if (event is PointerScrollEvent) {
          if (!_scrollController.hasClients) return;

          // Cuộn với một tốc độ thích hợp
          // scrollDelta.dy là giá trị cuộn theo chiều dọc, nhưng chúng ta dùng cho cuộn ngang
          final double scrollAmount = event.scrollDelta.dy * 5.0;
          final double targetPosition = _scrollController.offset + scrollAmount;

          // Đảm bảo vị trí cuộn nằm trong giới hạn hợp lệ
          final double maxScroll = _scrollController.position.maxScrollExtent;
          final double clampedPosition = targetPosition.clamp(0.0, maxScroll);

          // Cuộn đến vị trí mới
          _scrollController.jumpTo(clampedPosition);
        }
      },
      child: SizedBox(
        height: widget.thumbnailSize + 16, // 16 cho padding ở trên và dưới
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          itemCount: widget.images.length,
          itemBuilder: (context, index) {
            final file = widget.images[index];
            final bool isSelected = index == widget.currentIndex;

            return GestureDetector(
              onTap: () => widget.onThumbnailTap(index),
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: widget.spacing,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    width: 2.0,
                  ),
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2.0),
                  child: SizedBox(
                    width: widget.thumbnailSize,
                    height: widget.thumbnailSize,
                    child: _buildThumbnailImage(file, isSelected),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Xây dựng widget hiển thị hình ảnh thumbnail
  Widget _buildThumbnailImage(File file, bool isSelected) {
    return Stack(
      children: [
        // Tạo màu nền xám tối cho thumbnail
        Container(color: Colors.grey[800]),

        // Ảnh thumbnail chính
        Opacity(
          opacity: isSelected ? 1.0 : 0.7,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            width: widget.thumbnailSize,
            height: widget.thumbnailSize,
            // Đặt chất lượng cao cho thumbnail để hiển thị sắc nét
            filterQuality: FilterQuality.high,
            cacheWidth: (widget.thumbnailSize * 1.5).toInt(),
            // Xử lý lỗi khi không thể tải ảnh
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: widget.thumbnailSize,
                height: widget.thumbnailSize,
                color: Colors.grey[800],
                child: const Icon(
                  PhosphorIconsLight.imageBroken,
                  color: Colors.white70,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
