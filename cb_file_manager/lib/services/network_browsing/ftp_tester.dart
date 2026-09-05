import 'dart:io';
import 'ftp_client/index.dart';
import 'package:path/path.dart' as path;

/// Class đơn giản để kiểm tra kết nối FTP trực tiếp
/// Sử dụng custom FTP client implementation
class FTPTester {
  static Future<List<Map<String, dynamic>>> testConnection({
    required String host,
    required String username,
    String? password,
    int port = 21,
  }) async {
    final result = <Map<String, dynamic>>[];

    try {
      // Tạo client FTP
      final ftpClient = FtpClient(
        host: host,
        port: port,
        username: username,
        password: password ?? 'anonymous@',
      );

      // Kết nối
      final connected = await ftpClient.connect();
      if (!connected) {
        throw Exception("Connection failed");
      }

      // Liệt kê nội dung thư mục
      final listing = await ftpClient.listDirectory();

      // Duyệt qua danh sách kết quả
      for (var item in listing) {
        final name = path.basename(item.path);
        final type = item.isDirectory ? "dir" : "file";
        final size = item is File ? (await item.stat()).size : 0;
        final modified = item is File
            ? (await item.stat()).modified
            : DateTime.now();

        // Thêm vào kết quả
        result.add({
          'name': name,
          'type': type,
          'size': size,
          'modified': modified,
        });
      }

      // Ngắt kết nối
      await ftpClient.disconnect();
    } catch (e) {
      result.add({'error': e.toString()});
    }

    return result;
  }
}
