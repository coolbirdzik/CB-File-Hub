import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

import '../helpers/core/filesystem_utils.dart';
import '../helpers/tags/tag_manager.dart';
import '../models/database/sqlite_database_provider.dart';
import '../models/objectbox/video_library.dart';
import '../models/objectbox/video_library_config.dart';
import '../models/objectbox/video_library_file.dart';

/// Service class for managing video libraries and their file associations.
class VideoLibraryService {
  static final VideoLibraryService _instance = VideoLibraryService._internal();

  factory VideoLibraryService() => _instance;

  VideoLibraryService._internal();

  final SqliteDatabaseProvider _dbProvider = SqliteDatabaseProvider();

  Future<Database> _getDatabase() async {
    await _dbProvider.initialize();
    return _dbProvider.getDatabase();
  }

  Future<void> initialize() async {
    await _getDatabase();
  }

  Future<List<VideoLibrary>> getAllLibraries() async {
    try {
      final database = await _getDatabase();
      final rows = await database.query(
        'video_libraries',
        orderBy: 'modified_at DESC, id DESC',
      );
      return rows.map(VideoLibrary.fromDatabaseMap).toList(growable: false);
    } catch (error) {
      debugPrint('Error getting all video libraries: $error');
      return <VideoLibrary>[];
    }
  }

  Future<VideoLibrary?> getLibraryById(int id) async {
    try {
      final database = await _getDatabase();
      final rows = await database.query(
        'video_libraries',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return VideoLibrary.fromDatabaseMap(rows.first);
    } catch (error) {
      debugPrint('Error getting video library by ID: $error');
      return null;
    }
  }

  Future<VideoLibrary?> createLibrary({
    required String name,
    String? description,
    String? coverImagePath,
    String? colorTheme,
    List<String>? directories,
    VideoLibraryConfig? config,
  }) async {
    try {
      final database = await _getDatabase();
      final existing = await database.query(
        'video_libraries',
        columns: <String>['id'],
        where: 'LOWER(name) = ?',
        whereArgs: <Object?>[name.toLowerCase()],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw Exception('Video library with name "$name" already exists');
      }

      final library = VideoLibrary(
        name: name,
        description: description,
        coverImagePath: coverImagePath,
        colorTheme: colorTheme,
      );
      final libraryId =
          await database.insert('video_libraries', library.toDatabaseMap());
      library.id = libraryId;

      final libraryConfig = config ??
          VideoLibraryConfig(
            videoLibraryId: libraryId,
            directories: directories?.join(',') ?? '',
          );
      libraryConfig.videoLibraryId = libraryId;
      final configId = await database.insert(
        'video_library_configs',
        libraryConfig.toDatabaseMap(),
      );
      libraryConfig.id = configId;

      return library;
    } catch (error) {
      debugPrint('Error creating video library: $error');
      return null;
    }
  }

  Future<bool> updateLibrary(VideoLibrary library) async {
    try {
      final database = await _getDatabase();
      library.updateModifiedTime();
      await database.update(
        'video_libraries',
        library.toDatabaseMap(),
        where: 'id = ?',
        whereArgs: <Object?>[library.id],
      );
      return true;
    } catch (error) {
      debugPrint('Error updating video library: $error');
      return false;
    }
  }

  Future<bool> deleteLibrary(int libraryId) async {
    try {
      final database = await _getDatabase();
      await database.transaction((txn) async {
        await txn.delete(
          'video_library_files',
          where: 'video_library_id = ?',
          whereArgs: <Object?>[libraryId],
        );
        await txn.delete(
          'video_library_configs',
          where: 'video_library_id = ?',
          whereArgs: <Object?>[libraryId],
        );
        await txn.delete(
          'video_libraries',
          where: 'id = ?',
          whereArgs: <Object?>[libraryId],
        );
      });
      return true;
    } catch (error) {
      debugPrint('Error deleting video library: $error');
      return false;
    }
  }

  Future<List<String>> getLibraryFiles(int libraryId) async {
    try {
      final config = await getLibraryConfig(libraryId);
      if (config == null) {
        return <String>[];
      }

      final allFiles = <String>{};

      if (config.directoriesList.isNotEmpty) {
        for (final directoryPath in config.directoriesList) {
          final directory = Directory(directoryPath.trim());
          if (!directory.existsSync()) {
            continue;
          }

          final files = await getAllVideos(
            directoryPath,
            recursive: config.includeSubdirectories,
          );
          allFiles.addAll(files.map((file) => file.path));
        }
      }

      final database = await _getDatabase();
      final rows = await database.query(
        'video_library_files',
        where: 'video_library_id = ?',
        whereArgs: <Object?>[libraryId],
      );
      allFiles.addAll(
        rows.map((row) => row['file_path']).whereType<String>(),
      );

      return allFiles.toList(growable: false);
    } catch (error) {
      debugPrint('Error getting library files: $error');
      return <String>[];
    }
  }

  Future<bool> addFileToLibrary(
    int libraryId,
    String filePath, {
    String? caption,
  }) async {
    try {
      final database = await _getDatabase();
      final existing = await database.query(
        'video_library_files',
        columns: <String>['id'],
        where: 'video_library_id = ? AND file_path = ?',
        whereArgs: <Object?>[libraryId, filePath],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return true;
      }

      final nextOrderIndex = sqflite.Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT MAX(order_index)
              FROM video_library_files
              WHERE video_library_id = ?
              ''',
              <Object?>[libraryId],
            ),
          ) ??
          -1;

      final libraryFile = VideoLibraryFile(
        videoLibraryId: libraryId,
        filePath: filePath,
        caption: caption,
        orderIndex: nextOrderIndex + 1,
      );
      await database.insert(
        'video_library_files',
        libraryFile.toDatabaseMap(),
      );

      final library = await getLibraryById(libraryId);
      if (library != null) {
        await updateLibrary(library);
      }

      return true;
    } catch (error) {
      debugPrint('Error adding file to library: $error');
      return false;
    }
  }

  Future<int> addFilesToLibrary(int libraryId, List<String> filePaths) async {
    if (filePaths.isEmpty) return 0;

    final database = await _getDatabase();
    int successCount = 0;

    await database.transaction((txn) async {
      for (final filePath in filePaths) {
        final existing = await txn.query(
          'video_library_files',
          columns: <String>['id'],
          where: 'video_library_id = ? AND file_path = ?',
          whereArgs: <Object?>[libraryId, filePath],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;

        final nextOrderIndex = sqflite.Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT MAX(order_index) FROM video_library_files WHERE video_library_id = ?',
                <Object?>[libraryId],
              ),
            ) ??
            -1;

        final libraryFile = VideoLibraryFile(
          videoLibraryId: libraryId,
          filePath: filePath,
          orderIndex: nextOrderIndex + 1,
        );
        await txn.insert(
          'video_library_files',
          libraryFile.toDatabaseMap(),
        );
        successCount++;
      }
    });

    if (successCount > 0) {
      final library = await getLibraryById(libraryId);
      if (library != null) {
        await updateLibrary(library);
      }
    }

    return successCount;
  }

  Future<int> addFolderToLibrary(
    int libraryId,
    String folderPath, {
    bool recursive = true,
  }) async {
    try {
      final videos = await getAllVideos(folderPath, recursive: recursive);
      return addFilesToLibrary(
        libraryId,
        videos.map((file) => file.path).toList(growable: false),
      );
    } catch (error) {
      debugPrint('Error adding folder to library: $error');
      return 0;
    }
  }

  Future<bool> removeFileFromLibrary(int libraryId, String filePath) async {
    try {
      final database = await _getDatabase();
      final deleted = await database.delete(
        'video_library_files',
        where: 'video_library_id = ? AND file_path = ?',
        whereArgs: <Object?>[libraryId, filePath],
      );
      if (deleted == 0) {
        return false;
      }

      final library = await getLibraryById(libraryId);
      if (library != null) {
        await updateLibrary(library);
      }

      return true;
    } catch (error) {
      debugPrint('Error removing file from library: $error');
      return false;
    }
  }

  Future<bool> isFileInLibrary(int libraryId, String filePath) async {
    try {
      final database = await _getDatabase();
      final count = sqflite.Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT COUNT(*)
              FROM video_library_files
              WHERE video_library_id = ? AND file_path = ?
              ''',
              <Object?>[libraryId, filePath],
            ),
          ) ??
          0;
      return count > 0;
    } catch (error) {
      debugPrint('Error checking if file in library: $error');
      return false;
    }
  }

  Future<VideoLibraryConfig?> getLibraryConfig(int libraryId) async {
    try {
      final database = await _getDatabase();
      final rows = await database.query(
        'video_library_configs',
        where: 'video_library_id = ?',
        whereArgs: <Object?>[libraryId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return VideoLibraryConfig.fromDatabaseMap(rows.first);
    } catch (error) {
      debugPrint('Error getting library config: $error');
      return null;
    }
  }

  Future<bool> updateLibraryConfig(VideoLibraryConfig config) async {
    try {
      final database = await _getDatabase();
      if (config.id == 0) {
        final existing = await database.query(
          'video_library_configs',
          columns: <String>['id'],
          where: 'video_library_id = ?',
          whereArgs: <Object?>[config.videoLibraryId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          config.id = existing.first['id'] as int? ?? 0;
        }
      }

      await database.insert(
        'video_library_configs',
        config.toDatabaseMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (error) {
      debugPrint('Error updating library config: $error');
      return false;
    }
  }

  Future<bool> addDirectoryToLibrary(
      int libraryId, String directoryPath) async {
    try {
      final config = await getLibraryConfig(libraryId);
      if (config == null) {
        return false;
      }

      final directories = config.directoriesList;
      if (!directories.contains(directoryPath)) {
        directories.add(directoryPath);
        config.directoriesList = directories;
        return updateLibraryConfig(config);
      }
      return true;
    } catch (error) {
      debugPrint('Error adding directory to library: $error');
      return false;
    }
  }

  Future<bool> removeDirectoryFromLibrary(
    int libraryId,
    String directoryPath,
  ) async {
    try {
      final config = await getLibraryConfig(libraryId);
      if (config == null) {
        return false;
      }

      final directories = config.directoriesList;
      directories.remove(directoryPath);
      config.directoriesList = directories;
      return updateLibraryConfig(config);
    } catch (error) {
      debugPrint('Error removing directory from library: $error');
      return false;
    }
  }

  Future<List<String>> getVideosByTag(
    String tag, {
    int? libraryId,
    bool globalSearch = false,
  }) async {
    try {
      List<FileSystemEntity> taggedFiles;

      if (globalSearch || libraryId == null) {
        taggedFiles = await TagManager.findFilesByTagGlobally(tag);
      } else {
        final config = await getLibraryConfig(libraryId);
        if (config == null || config.directoriesList.isEmpty) {
          return <String>[];
        }

        final allTaggedFiles = <FileSystemEntity>{};
        for (final directory in config.directoriesList) {
          final files = await TagManager.findFilesByTag(directory, tag);
          allTaggedFiles.addAll(files);
        }
        taggedFiles = allTaggedFiles.toList(growable: false);
      }

      const videoExtensions = <String>{
        '.mp4',
        '.avi',
        '.mov',
        '.mkv',
        '.webm',
        '.wmv',
        '.flv',
        '.m4v',
        '.mpg',
        '.mpeg',
        '.3gp',
        '.ogv',
      };

      return taggedFiles
          .whereType<File>()
          .where(
            (file) => videoExtensions
                .contains(path.extension(file.path).toLowerCase()),
          )
          .map((file) => file.path)
          .toList(growable: false);
    } catch (error) {
      debugPrint('Error getting videos by tag: $error');
      return <String>[];
    }
  }

  Future<List<String>> searchVideos(
    String query, {
    int? libraryId,
    bool searchTags = true,
  }) async {
    try {
      List<String> allVideos;

      if (libraryId != null) {
        allVideos = await getLibraryFiles(libraryId);
      } else {
        final libraries = await getAllLibraries();
        final allFiles = <String>{};
        for (final library in libraries) {
          final files = await getLibraryFiles(library.id);
          allFiles.addAll(files);
        }
        allVideos = allFiles.toList(growable: false);
      }

      final queryLower = query.toLowerCase();
      final matchingVideos = allVideos
          .where(
            (filePath) =>
                path.basename(filePath).toLowerCase().contains(queryLower),
          )
          .toList(growable: true);

      if (searchTags && query.isNotEmpty) {
        final taggedVideos = await getVideosByTag(
          query,
          libraryId: libraryId,
          globalSearch: libraryId == null,
        );
        matchingVideos.addAll(taggedVideos);
      }

      return matchingVideos.toSet().toList(growable: false);
    } catch (error) {
      debugPrint('Error searching videos: $error');
      return <String>[];
    }
  }

  Future<void> refreshLibrary(int libraryId) async {
    try {
      final config = await getLibraryConfig(libraryId);
      if (config == null) {
        return;
      }

      final files = await getLibraryFiles(libraryId);
      config.updateScanStats(files.length);
      await updateLibraryConfig(config);
    } catch (error) {
      debugPrint('Error refreshing library: $error');
    }
  }

  Future<int> getLibraryVideoCount(int libraryId) async {
    final files = await getLibraryFiles(libraryId);
    return files.length;
  }

  void dispose() {}
}
