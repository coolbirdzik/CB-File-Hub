import 'dart:io';

import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cache = DirectoryListingCacheService.instance;

  setUp(cache.clearAll);
  tearDown(cache.clearAll);

  test('removePaths removes moved items while keeping the source cache warm',
      () {
    final separator = Platform.pathSeparator;
    final sourcePath = '${separator}source';
    final keptFile = File('$sourcePath${separator}keep.txt');
    final movedFile = File('$sourcePath${separator}move.txt');
    final movedFolder = Directory('$sourcePath${separator}folder');

    cache.storeListing(
      path: sourcePath,
      files: [keptFile, movedFile],
      folders: [movedFolder],
      stats: const {},
    );

    cache.removePaths([movedFile.path, movedFolder.path]);

    final listing = cache.getListing(sourcePath);
    expect(listing, isNotNull);
    expect(listing!.files.map((file) => file.path), [keptFile.path]);
    expect(listing.folders, isEmpty);
  });

  test('removePaths leaves unrelated cached folders unchanged', () {
    final separator = Platform.pathSeparator;
    final sourcePath = '${separator}source';
    final otherPath = '${separator}other';
    final sourceFile = File('$sourcePath${separator}move.txt');
    final otherFile = File('$otherPath${separator}keep.txt');

    cache.storeListing(
      path: sourcePath,
      files: [sourceFile],
      folders: const [],
      stats: const {},
    );
    cache.storeListing(
      path: otherPath,
      files: [otherFile],
      folders: const [],
      stats: const {},
    );

    cache.removePaths([sourceFile.path]);

    expect(cache.getListing(sourcePath)!.files, isEmpty);
    expect(
      cache.getListing(otherPath)!.files.map((file) => file.path),
      [otherFile.path],
    );
  });
}
