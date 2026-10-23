import 'dart:io';

import 'package:cb_file_manager/helpers/core/file_property_sorter.dart';
import 'package:cb_file_manager/helpers/core/filesystem_sorter.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/details_columns.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every Details property has an ascending and descending sort', () {
    for (final column in DetailsColumn.values) {
      final pair = column.sortOptions;
      expect(pair, isNotNull, reason: column.name);
      expect(pair!.$1.ascending, isTrue);
      expect(pair.$2.ascending, isFalse);
    }
    expect(
      SortOption.pathDesc.index,
      17,
    ); // Existing saved indexes remain valid.
  });

  for (final ascending in [true, false]) {
    test(
      'numeric keys, unknowns and folder grouping, ascending=$ascending',
      () async {
        final items = <FileSystemEntity>[
          File('/a'),
          File('/b'),
          File('/c'),
          Directory('/folder'),
        ];
        final keys = {'/a': 100, '/b': 20, '/c': null, '/folder': null};
        final compare = await FilePropertySorter.prepare(
          items,
          ascending ? SortOption.pageCountAsc : SortOption.pageCountDesc,
          readValue: (entity, _) async => keys[entity.path],
        );
        items.sort(compare);
        expect(
          items.map((e) => e.path),
          ascending
              ? ['/folder', '/b', '/a', '/c']
              : ['/folder', '/a', '/b', '/c'],
        );
      },
    );
  }

  test(
    'sorts canonical dimensions, versions, dates and durations as values',
    () async {
      final cases = <String, (String, String)>{
        'dimensions': ('800,600', '1920,1080'),
        'fileVersion': ('1.2.0', '1.10.0'),
        'dateTaken': ('20', '100'),
        'duration': ('20', '100'),
        'frameRate': ('23976', '60000'),
        'bitRate': ('128000', '1000000'),
      };
      for (final entry in cases.entries) {
        final files = [File('/z-small'), File('/a-large')];
        final compare = await FilePropertySorter.prepare(
          files,
          SortOption.values.byName('${entry.key}Asc'),
          readValue: (file, _) async => FilePropertySorter.decodeShellKey(
            entry.key,
            file.path == '/z-small' ? entry.value.$1 : entry.value.$2,
          ),
        );
        files.sort(compare);
        expect(files.first.path, '/z-small', reason: entry.key);
      }
    },
  );

  test(
    'bounds concurrent reads, deduplicates paths and tolerates missing files',
    () async {
      final files = List.generate(25, (i) => File('/$i'));
      var active = 0, peak = 0, reads = 0;
      final compare = await FilePropertySorter.prepare(
        [...files, ...files],
        SortOption.yearAsc,
        readValue: (file, _) async {
          reads++;
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(Duration.zero);
          active--;
          if (file.path == '/0') throw const FileSystemException('Gone');
          return int.parse(file.path.substring(1));
        },
      );
      files.sort(compare);
      expect(reads, 25);
      expect(peak, lessThanOrEqualTo(8));
      expect(files.last.path, '/0');
    },
  );

  test('superseded property requests stop scheduling more reads', () async {
    var cancelled = false, reads = 0;
    await FilePropertySorter.prepare(
      List.generate(100, (i) => File('/$i')),
      SortOption.titleAsc,
      isCancelled: () => cancelled,
      readValue: (file, _) async {
        reads++;
        cancelled = true;
        return file.path;
      },
    );
    expect(reads, 8);
  });

  test(
    'filesystem sorting reads folder counts rather than sorting their labels',
    () async {
      final root = await Directory.systemTemp.createTemp('cb-property-sort-');
      addTearDown(() => root.delete(recursive: true));
      final two = await Directory(p.join(root.path, 'z-two')).create();
      final ten = await Directory(p.join(root.path, 'a-ten')).create();
      for (var i = 0; i < 10; i++) {
        await File(p.join(ten.path, '$i')).writeAsString('');
        if (i < 2) await File(p.join(two.path, '$i')).writeAsString('');
      }
      final sorted = await FileSystemSorter.sortDirectories([
        ten,
        two,
      ], SortOption.itemCountAsc);
      expect(sorted.map((e) => e.path), [two.path, ten.path]);
    },
  );
}
