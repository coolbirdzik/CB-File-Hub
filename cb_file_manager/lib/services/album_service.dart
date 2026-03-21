import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

import '../helpers/core/filesystem_utils.dart';
import '../models/database/sqlite_database_provider.dart';
import '../models/objectbox/album.dart';
import '../models/objectbox/album_config.dart';
import '../models/objectbox/album_file.dart';
import 'album_file_scanner.dart';
import 'background_album_processor.dart';
import 'lazy_album_scanner.dart';

/// Service class for managing albums and their file associations.
class AlbumService {
  static AlbumService? _instance;
  static AlbumService get instance => _instance ??= AlbumService._();

  final SqliteDatabaseProvider _dbProvider = SqliteDatabaseProvider();
  final AlbumFileScanner _scanner = AlbumFileScanner.instance;
  final BackgroundAlbumProcessor _processor = BackgroundAlbumProcessor.instance;
  final LazyAlbumScanner _lazyScanner = LazyAlbumScanner.instance;

  AlbumService._();

  final StreamController<int> _albumUpdatedController =
      StreamController<int>.broadcast();
  Stream<int> get albumUpdatedStream => _albumUpdatedController.stream;

  final StreamController<Map<String, dynamic>> _progressController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  Future<Database> _getDatabase() async {
    await _dbProvider.initialize();
    return _dbProvider.getDatabase();
  }

  Future<void> initialize() async {
    await _processor.startMonitoring();

    try {
      final configs = await getAllAlbumConfigs();
      for (final config in configs) {
        if (config.directoriesList.isNotEmpty) {
          await _processor.addAlbumToMonitoring(
            config.albumId,
            config.directoriesList,
          );
        }
      }
    } catch (error) {
      debugPrint('Error restoring album monitoring: $error');
    }
  }

  Future<List<Album>> getAllAlbums() async {
    try {
      final database = await _getDatabase();
      final rows = await database.query(
        'albums',
        orderBy: 'modified_at DESC, id DESC',
      );
      return rows.map(Album.fromDatabaseMap).toList(growable: false);
    } catch (error) {
      debugPrint('Error getting all albums: $error');
      return <Album>[];
    }
  }

  Future<Album?> getAlbumById(int id) async {
    try {
      final database = await _getDatabase();
      final rows = await database.query(
        'albums',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return Album.fromDatabaseMap(rows.first);
    } catch (error) {
      debugPrint('Error getting album by ID $id: $error');
      return null;
    }
  }

  Future<Album?> createAlbum({
    required String name,
    String? description,
    String? coverImagePath,
    String? colorTheme,
    List<String>? directories,
    AlbumConfig? config,
  }) async {
    try {
      final database = await _getDatabase();
      final existing = await database.query(
        'albums',
        columns: <String>['id'],
        where: 'LOWER(name) = ?',
        whereArgs: <Object?>[name.toLowerCase()],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw Exception('Album with name "$name" already exists');
      }

      final album = Album(
        name: name,
        description: description,
        coverImagePath: coverImagePath,
        colorTheme: colorTheme,
      );

      final albumId = await database.insert('albums', album.toDatabaseMap());
      album.id = albumId;

      if (directories != null && directories.isNotEmpty) {
        final albumConfig = config ?? AlbumConfig(albumId: albumId);
        albumConfig.albumId = albumId;
        albumConfig.directoriesList = directories;
        final configId =
            await database.insert('album_configs', albumConfig.toDatabaseMap());
        albumConfig.id = configId;

        await _processor.addAlbumToMonitoring(albumId, directories);
        _triggerBackgroundScan(album, albumConfig);
      }

      return album;
    } catch (error) {
      debugPrint('Error creating album: $error');
      return null;
    }
  }

  Future<bool> updateAlbum(Album album) async {
    try {
      final database = await _getDatabase();
      album.updateModifiedTime();
      await database.update(
        'albums',
        album.toDatabaseMap(),
        where: 'id = ?',
        whereArgs: <Object?>[album.id],
      );
      return true;
    } catch (error) {
      debugPrint('Error updating album: $error');
      return false;
    }
  }

  Future<bool> deleteAlbum(int albumId) async {
    try {
      final database = await _getDatabase();
      final config = await getAlbumConfig(albumId);

      await database.transaction((txn) async {
        await txn.delete(
          'album_files',
          where: 'album_id = ?',
          whereArgs: <Object?>[albumId],
        );
        await txn.delete(
          'album_configs',
          where: 'album_id = ?',
          whereArgs: <Object?>[albumId],
        );
        await txn.delete(
          'albums',
          where: 'id = ?',
          whereArgs: <Object?>[albumId],
        );
      });

      if (config != null) {
        await _processor.removeAlbumFromMonitoring(config.directoriesList);
      }

      _scanner.clearCache(albumId);
      _lazyScanner.disposeAlbum(albumId);
      return true;
    } catch (error) {
      debugPrint('Error deleting album: $error');
      return false;
    }
  }

  Future<List<AlbumFile>> getAlbumFiles(int albumId) async {
    try {
      final database = await _getDatabase();
      final rows = await database.query(
        'album_files',
        where: 'album_id = ?',
        whereArgs: <Object?>[albumId],
        orderBy: 'order_index ASC, id ASC',
      );
      return rows.map(AlbumFile.fromDatabaseMap).toList(growable: false);
    } catch (error) {
      debugPrint('Error getting album files: $error');
      return <AlbumFile>[];
    }
  }

  Future<bool> addFileToAlbum(
    int albumId,
    String filePath, {
    String? caption,
  }) async {
    try {
      if (!await File(filePath).exists()) {
        throw Exception('File does not exist: $filePath');
      }

      if (await isFileInAlbum(albumId, filePath)) {
        return false;
      }

      final database = await _getDatabase();
      final nextOrderIndex = sqflite.Sqflite.firstIntValue(
            await database.rawQuery(
              'SELECT MAX(order_index) FROM album_files WHERE album_id = ?',
              <Object?>[albumId],
            ),
          ) ??
          -1;

      final albumFile = AlbumFile(
        albumId: albumId,
        filePath: filePath,
        orderIndex: nextOrderIndex + 1,
        caption: caption,
      );

      await database.insert('album_files', albumFile.toDatabaseMap());

      final album = await getAlbumById(albumId);
      if (album != null) {
        await updateAlbum(album);
      }

      return true;
    } catch (error) {
      debugPrint('Error adding file to album: $error');
      return false;
    }
  }

  Future<int> addFilesToAlbum(int albumId, List<String> filePaths) async {
    if (filePaths.isEmpty) return 0;

    final database = await _getDatabase();
    int successCount = 0;

    await database.transaction((txn) async {
      for (final filePath in filePaths) {
        final exists = await _isFileInAlbumTxn(txn, albumId, filePath);
        if (exists) continue;

        FileStat? stat;
        try {
          stat = await File(filePath).stat();
        } catch (_) {
          // File may not exist or be inaccessible
        }
        if (stat == null) continue;

        final nextOrderIndex = sqflite.Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT MAX(order_index) FROM album_files WHERE album_id = ?',
                <Object?>[albumId],
              ),
            ) ??
            -1;

        final albumFile = AlbumFile(
          albumId: albumId,
          filePath: filePath,
          orderIndex: nextOrderIndex + 1,
        );

        await txn.insert('album_files', albumFile.toDatabaseMap());
        successCount++;
      }
    });

    if (successCount > 0) {
      final album = await getAlbumById(albumId);
      if (album != null) {
        await updateAlbum(album);
      }
    }

    return successCount;
  }

  /// Checks if a file is already in an album (within an active transaction).
  Future<bool> _isFileInAlbumTxn(
      DatabaseExecutor txn, int albumId, String filePath) async {
    final count = sqflite.Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) FROM album_files WHERE album_id = ? AND file_path = ?',
            <Object?>[albumId, filePath],
          ),
        ) ??
        0;
    return count > 0;
  }

  Future<int> addFolderToAlbum(
    int albumId,
    String folderPath, {
    bool recursive = true,
  }) async {
    try {
      final imageFiles = await getAllImages(folderPath, recursive: recursive);
      final filePaths = imageFiles.map((file) => file.path).toList();
      return addFilesToAlbum(albumId, filePaths);
    } catch (error) {
      debugPrint('Error adding folder to album: $error');
      return 0;
    }
  }

  Future<Map<String, dynamic>> addFilesFromDirectory(
    int albumId,
    String directoryPath, {
    bool recursive = true,
  }) async {
    try {
      final imageFiles =
          await getAllImages(directoryPath, recursive: recursive);
      final filePaths = imageFiles.map((file) => file.path).toList();
      final addedCount = await addFilesToAlbum(albumId, filePaths);

      return <String, dynamic>{
        'total': filePaths.length,
        'added': addedCount,
        'skipped': filePaths.length - addedCount,
      };
    } catch (error) {
      debugPrint('Error adding files from directory: $error');
      return <String, dynamic>{
        'total': 0,
        'added': 0,
        'skipped': 0,
        'error': error.toString(),
      };
    }
  }

  Future<void> addFilesFromDirectoryInBackground(
    int albumId,
    String directoryPath, {
    bool recursive = true,
  }) async {
    try {
      _progressController.add(<String, dynamic>{
        'albumId': albumId,
        'status': 'scanning',
        'current': 0,
        'total': 0,
      });

      final imageFiles = await compute(_getImageFilesIsolate, <String, dynamic>{
        'directoryPath': directoryPath,
        'recursive': recursive,
      });

      final totalFiles = imageFiles.length;
      if (totalFiles == 0) {
        _progressController.add(<String, dynamic>{
          'albumId': albumId,
          'status': 'completed',
          'current': 0,
          'total': 0,
        });
        return;
      }

      _progressController.add(<String, dynamic>{
        'albumId': albumId,
        'status': 'processing',
        'current': 0,
        'total': totalFiles,
      });

      const batchSize = 5;
      var processedFiles = 0;
      var addedCount = 0;

      for (var index = 0; index < imageFiles.length; index += batchSize) {
        final batch = imageFiles.skip(index).take(batchSize).toList();

        for (final filePath in batch) {
          final added = await addFileToAlbum(albumId, filePath);
          processedFiles++;
          if (added) {
            addedCount++;
          }
        }

        _progressController.add(<String, dynamic>{
          'albumId': albumId,
          'status': 'processing',
          'current': processedFiles,
          'total': totalFiles,
        });

        if (addedCount > 0) {
          _albumUpdatedController.add(albumId);
          addedCount = 0;
        }

        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      _progressController.add(<String, dynamic>{
        'albumId': albumId,
        'status': 'completed',
        'current': totalFiles,
        'total': totalFiles,
      });

      _albumUpdatedController.add(albumId);
    } catch (error) {
      debugPrint('Error (background) adding files from directory: $error');
      _progressController.add(<String, dynamic>{
        'albumId': albumId,
        'status': 'error',
        'error': error.toString(),
      });
    }
  }

  Future<bool> removeFileFromAlbum(int albumId, String filePath) async {
    try {
      final database = await _getDatabase();
      final deleted = await database.delete(
        'album_files',
        where: 'album_id = ? AND file_path = ?',
        whereArgs: <Object?>[albumId, filePath],
      );

      if (deleted == 0) {
        return false;
      }

      final album = await getAlbumById(albumId);
      if (album != null) {
        await updateAlbum(album);
      }

      return true;
    } catch (error) {
      debugPrint('Error removing file from album: $error');
      return false;
    }
  }

  Future<bool> isFileInAlbum(int albumId, String filePath) async {
    try {
      final database = await _getDatabase();
      final count = sqflite.Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT COUNT(*)
              FROM album_files
              WHERE album_id = ? AND file_path = ?
              ''',
              <Object?>[albumId, filePath],
            ),
          ) ??
          0;
      return count > 0;
    } catch (error) {
      debugPrint('Error checking if file is in album: $error');
      return false;
    }
  }

  Future<List<File>> searchImageFiles(
    String searchQuery, {
    String? rootPath,
  }) async {
    try {
      final searchPath = rootPath ?? '/storage/emulated/0';
      final allImages = await getAllImages(searchPath, recursive: true);

      if (searchQuery.trim().isEmpty) {
        return allImages;
      }

      final query = searchQuery.toLowerCase();
      return allImages.where((file) {
        final fileName = path.basename(file.path).toLowerCase();
        final filePath = file.path.toLowerCase();
        return fileName.contains(query) || filePath.contains(query);
      }).toList(growable: false);
    } catch (error) {
      debugPrint('Error searching image files: $error');
      return <File>[];
    }
  }

  static Future<List<String>> _getImageFilesIsolate(
    Map<String, dynamic> params,
  ) async {
    final directoryPath = params['directoryPath'] as String;
    final recursive = params['recursive'] as bool;

    final imageFiles = await getAllImages(directoryPath, recursive: recursive);
    return imageFiles.map((file) => file.path).toList(growable: false);
  }

  Future<AlbumConfig?> getAlbumConfig(int albumId) async {
    try {
      final database = await _getDatabase();
      final rows = await database.query(
        'album_configs',
        where: 'album_id = ?',
        whereArgs: <Object?>[albumId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return AlbumConfig.fromDatabaseMap(rows.first);
    } catch (error) {
      debugPrint('Error getting album config: $error');
      return null;
    }
  }

  Future<List<AlbumConfig>> getAllAlbumConfigs() async {
    try {
      final database = await _getDatabase();
      final rows = await database.query('album_configs');
      return rows.map(AlbumConfig.fromDatabaseMap).toList(growable: false);
    } catch (_) {
      return <AlbumConfig>[];
    }
  }

  Future<void> updateAlbumConfig(AlbumConfig config) async {
    try {
      final database = await _getDatabase();
      if (config.id == 0) {
        final existing = await database.query(
          'album_configs',
          columns: <String>['id'],
          where: 'album_id = ?',
          whereArgs: <Object?>[config.albumId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          config.id = existing.first['id'] as int? ?? 0;
        }
      }

      await database.insert(
        'album_configs',
        config.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _scanner.clearCache(config.albumId);
      await _processor.refreshMonitoring();
    } catch (error) {
      debugPrint('Error updating album config: $error');
    }
  }

  Stream<List<FileInfo>> getLazyAlbumFiles(int albumId) {
    final controller = StreamController<List<FileInfo>>();
    _initLazyStream(albumId, controller);
    return controller.stream;
  }

  Future<void> _initLazyStream(
    int albumId,
    StreamController<List<FileInfo>> controller,
  ) async {
    try {
      final album = await getAlbumById(albumId);
      if (album == null) {
        await controller.close();
        return;
      }

      final config = await getAlbumConfig(albumId);

      if (config != null && config.directoriesList.isNotEmpty) {
        final stream = _lazyScanner.getLazyAlbumFiles(album, config);
        await controller.addStream(stream);
      } else {
        final manualFiles = await getAlbumFiles(albumId);
        final fileInfos = manualFiles.map((file) {
          final localFile = File(file.filePath);
          final stat = localFile.existsSync() ? localFile.statSync() : null;
          return FileInfo(
            path: file.filePath,
            name: path.basename(file.filePath),
            size: stat?.size ?? 0,
            modifiedTime: stat?.modified ?? DateTime.now(),
            isImage: true,
            isVideo: false,
          );
        }).toList(growable: false);

        controller.add(fileInfos);
      }
    } catch (error) {
      debugPrint('Error initializing lazy stream: $error');
      controller.add(<FileInfo>[]);
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  void _triggerBackgroundScan(Album album, AlbumConfig config) {
    Timer(const Duration(milliseconds: 100), () async {
      try {
        final files = await _scanner.scanAlbumFiles(album, config);
        config.updateScanStats(files.length);
        await updateAlbumConfig(config);
      } catch (error) {
        debugPrint('Background scan error for album ${album.name}: $error');
      }
    });
  }

  Future<void> refreshAlbum(int albumId) async {
    _scanner.clearCache(albumId);
    _lazyScanner.refreshAlbum(albumId);
  }

  List<FileInfo> getImmediateFiles(int albumId) {
    return _lazyScanner.getImmediateFiles(albumId);
  }

  bool isAlbumScanning(int albumId) {
    return _lazyScanner.isScanning(albumId);
  }

  Future<double> getAlbumScanProgress(int albumId) async {
    final config = await getAlbumConfig(albumId);
    if (config == null) {
      return 0.0;
    }
    return _lazyScanner.getScanProgress(albumId, config);
  }

  Future<void> dispose() async {
    await _processor.stopMonitoring();
    _scanner.clearAllCache();
    _lazyScanner.dispose();
  }
}
