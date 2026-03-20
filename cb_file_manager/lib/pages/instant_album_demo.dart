import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;

class InstantAlbumDemo extends StatefulWidget {
  const InstantAlbumDemo({Key? key}) : super(key: key);

  @override
  State<InstantAlbumDemo> createState() => _InstantAlbumDemoState();
}

class _InstantAlbumDemoState extends State<InstantAlbumDemo> {
  final List<FileInfo> _files = [];
  String? _currentDirectory;
  StreamSubscription? _scanSubscription;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instant Album Demo'),
      ),
      body: Column(
        children: [
          // Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _selectDirectory,
                  icon: const Icon(PhosphorIconsLight.folderOpen),
                  label: const Text('Chọn thư mục ảnh'),
                ),
                if (_currentDirectory != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Thư mục: ${path.basename(_currentDirectory!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),

          // Status - chỉ hiển thị số lượng ảnh
          if (_files.isNotEmpty || _currentDirectory != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsLight.images,
                    size: 16,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_files.length} ảnh',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Files grid
          Expanded(
            child: _files.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsLight.imagesSquare,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Chọn thư mục để xem ảnh ngay lập tức'),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8.0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: 1,
                    ),
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      return _buildFileItem(file, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(FileInfo file, int index) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // File thumbnail
          if (file.isImage)
            Image.file(
              File(file.path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[200],
                  child: const Icon(PhosphorIconsLight.imageBroken,
                      color: Colors.grey),
                );
              },
            )
          else
            Container(
              color: Colors.grey[200],
              child: const Icon(PhosphorIconsLight.file, color: Colors.grey),
            ),

          // File name overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7)
                  ],
                ),
              ),
              child: Text(
                file.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // New indicator - hiển thị cho 5 ảnh mới nhất
          if (index >= _files.length - 5)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(PhosphorIconsLight.sparkle,
                    color: Colors.white, size: 12),
              ),
            ),
        ],
      ),
    );
  }

  void _selectDirectory() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    setState(() {
      _currentDirectory = selectedDirectory;
      _files.clear();
    });

    // Start instant scanning - hiển thị ảnh dần dần
    _startInstantScan(selectedDirectory);
  }

  void _startInstantScan(String directoryPath) {
    final dir = Directory(directoryPath);

    _scanSubscription = dir
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => _isImageFile(file.path))
        .listen(
      (file) {
        // Hiển thị ảnh ngay lập tức - tạo FileInfo tối thiểu
        final fileName = path.basename(file.path);
        final fileInfo = FileInfo(
          path: file.path,
          name: fileName,
          size: 0, // Sẽ cập nhật sau
          modifiedTime: DateTime.now(), // Sẽ cập nhật sau
          isImage: true,
        );

        // Thêm vào danh sách ngay lập tức
        setState(() {
          _files.add(fileInfo);
        });

        // Cập nhật thông tin chi tiết trong background (không chặn UI)
        final index = _files.length - 1;
        Future.microtask(() => _updateFileDetails(file, index));
      },
      onDone: () {
        // Scan hoàn thành
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $error')),
          );
        }
      },
    );
  }

  // Cập nhật thông tin file chi tiết trong background
  void _updateFileDetails(File file, int index) async {
    try {
      // Lấy thông tin file chi tiết
      final stat = await file.stat();
      if (mounted && index < _files.length) {
        setState(() {
          _files[index] = FileInfo(
            path: file.path,
            name: path.basename(file.path),
            size: stat.size,
            modifiedTime: stat.modified,
            isImage: true,
          );
        });
      }

      // Thêm vào album trong background (không ảnh hưởng UI)
      _addToAlbumInBackground(file.path);
    } catch (e) {
      // Ignore errors - ảnh vẫn hiển thị được
    }
  }

  // Thêm file vào album trong background (demo - chỉ log)
  void _addToAlbumInBackground(String filePath) async {
    // Simulate adding to album - chạy ngầm không ảnh hưởng UI
    await Future.delayed(const Duration(milliseconds: 1));
    // print('Added to album: ${path.basename(filePath)}');
  }

  bool _isImageFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    const imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'};
    return imageExtensions.contains(extension);
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }
}

class FileInfo {
  final String path;
  final String name;
  final int size;
  final DateTime modifiedTime;
  final bool isImage;

  FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedTime,
    required this.isImage,
  });
}
