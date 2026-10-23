import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/details_columns.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ColumnVisibility layout', () {
    test('keeps Name first and appends columns the saved order lacks', () {
      const columns = ColumnVisibility(
        order: [DetailsColumn.size, DetailsColumn.name, DetailsColumn.type],
      );
      final ordered = columns.orderedColumns;
      expect(ordered.take(3), [
        DetailsColumn.name,
        DetailsColumn.size,
        DetailsColumn.type,
      ]);
      expect(ordered.toSet(), DetailsColumn.values.toSet());
      expect(ordered.length, DetailsColumn.values.length);
    });

    test('moveColumn drops a column into the target slot', () {
      const columns = ColumnVisibility();
      // Moving left lands before the target.
      expect(
        columns
            .moveColumn(DetailsColumn.dateModified, DetailsColumn.type)
            .visibleColumns,
        [
          DetailsColumn.name,
          DetailsColumn.dateModified,
          DetailsColumn.type,
          DetailsColumn.size,
        ],
      );
      // Moving right lands after the target.
      expect(
        columns
            .moveColumn(DetailsColumn.type, DetailsColumn.dateModified)
            .visibleColumns,
        [
          DetailsColumn.name,
          DetailsColumn.size,
          DetailsColumn.dateModified,
          DetailsColumn.type,
        ],
      );
      // Name cannot move, and nothing moves in front of it.
      expect(
        columns.moveColumn(DetailsColumn.name, DetailsColumn.size),
        columns,
      );
      expect(
        columns
            .moveColumn(DetailsColumn.size, DetailsColumn.name)
            .visibleColumns
            .take(2),
        [DetailsColumn.name, DetailsColumn.size],
      );
    });

    test('widths clamp, reset and survive a JSON round trip', () {
      final columns = const ColumnVisibility(parentFolder: true)
          .withWidth(DetailsColumn.size, 10)
          .withWidth(DetailsColumn.path, 401.4)
          .moveColumn(DetailsColumn.parentFolder, DetailsColumn.type);
      expect(columns.widthOf(DetailsColumn.size), DetailsColumn.minWidth);
      expect(columns.widthOf(DetailsColumn.path), 401);
      expect(
        columns.withWidth(DetailsColumn.path, null).widthOf(DetailsColumn.path),
        DetailsColumn.path.defaultWidth,
      );

      final restored = ColumnVisibility.fromMap(
        jsonDecode(jsonEncode(columns.toMap())) as Map<String, dynamic>,
      );
      expect(restored, columns);
      expect(restored.resetLayout().order, isEmpty);
      expect(restored.resetLayout().widths, isEmpty);
      expect(restored.resetLayout().parentFolder, isTrue);
    });

    test('Shell property columns toggle, persist and stay Windows-only', () {
      final columns = const ColumnVisibility()
          .withColumn(DetailsColumn.owner, true)
          .withColumn(DetailsColumn.album, true)
          .withColumn(DetailsColumn.album, false);
      expect(columns.isVisible(DetailsColumn.owner), isTrue);
      expect(columns.isVisible(DetailsColumn.album), isFalse);
      final restored = ColumnVisibility.fromMap(
        jsonDecode(jsonEncode(columns.toMap())) as Map<String, dynamic>,
      );
      expect(restored, columns);
      expect(
        restored.visibleColumns.contains(DetailsColumn.owner),
        Platform.isWindows,
      );
      // A flag column name in the list is not a Shell column.
      expect(
        ColumnVisibility.fromMap({
          'shellColumns': ['size', 'title'],
        }).shellColumns,
        {DetailsColumn.title},
      );
    });

    test('reads maps saved before order and widths existed', () {
      final restored = ColumnVisibility.fromMap({
        'size': false,
        'tags': true,
        'order': ['tags', 'noLongerAColumn'],
        'widths': {'tags': 'wide', 'noLongerAColumn': 3},
      });
      expect(restored.size, isFalse);
      expect(restored.visibleColumns.take(2), [
        DetailsColumn.name,
        DetailsColumn.tags,
      ]);
      expect(restored.widths, isEmpty);
    });
  });

  group('DetailsColumnsHeader', () {
    Future<List<ColumnVisibility>> pumpTable(
      WidgetTester tester, {
      SortOption sortOption = SortOption.nameAsc,
      List<SortOption>? sorts,
      ColumnVisibility? initialColumns,
    }) async {
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <ColumnVisibility>[];
      var columns = initialColumns ?? const ColumnVisibility();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => DetailsLayoutHost(
                columns: columns,
                onChanged: (next) => setState(() {
                  saved.add(next);
                  columns = next;
                }),
                child: Column(
                  children: [
                    DetailsColumnsHeader(
                      sortOption: sortOption,
                      onSortOptionSelected: sorts?.add,
                    ),
                    Builder(
                      builder: (context) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kDetailsRowPadding,
                        ),
                        child: DetailsRowLayout(
                          columns: DetailsColumnsScope.maybeOf(
                            context,
                          )!.columns,
                          extraCellBuilder: (_) => const SizedBox.shrink(),
                          cellBuilder: (column) =>
                              DetailsCell.text('cell-${column.name}'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('clicking a header sorts by it and toggles the direction', (
      tester,
    ) async {
      final sorts = <SortOption>[];
      await pumpTable(tester, sortOption: SortOption.sizeAsc, sorts: sorts);
      await tester.tap(find.byKey(const ValueKey('details-header-size')));
      await tester.tap(find.byKey(const ValueKey('details-header-type')));
      expect(sorts, [SortOption.sizeDesc, SortOption.typeAsc]);
    });

    testWidgets(
      'all available metadata headers can toggle both sort directions',
      (tester) async {
        for (final column in DetailsColumn.values.where((c) => c.isAvailable)) {
          final pair = column.sortOptions!;
          if (pair.$1.metadataColumn == null) continue;
          final columns = const ColumnVisibility(
            type: false,
            size: false,
            dateModified: false,
          ).withColumn(column, true);
          final sorts = <SortOption>[];
          await pumpTable(tester, sorts: sorts, initialColumns: columns);
          final header = find.byKey(ValueKey('details-header-${column.name}'));
          await tester.tap(header);
          expect(sorts, [pair.$1], reason: column.name);
          sorts.clear();
          await pumpTable(
            tester,
            sorts: sorts,
            initialColumns: columns,
            sortOption: pair.$1,
          );
          await tester.tap(header);
          expect(sorts, [pair.$2], reason: column.name);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('dragging a header onto another moves the column', (
      tester,
    ) async {
      final saved = await pumpTable(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('details-header-size'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('details-header-type'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved.last.visibleColumns.take(3), [
        DetailsColumn.name,
        DetailsColumn.size,
        DetailsColumn.type,
      ]);
      // Rows follow the header.
      expect(
        tester.getCenter(find.text('cell-size')).dx,
        lessThan(tester.getCenter(find.text('cell-type')).dx),
      );
    });

    testWidgets('dragging a header edge resizes the column', (tester) async {
      final saved = await pumpTable(tester);
      final handle = find.byKey(const ValueKey('details-resize-size'));
      final before = tester.getSize(find.text('cell-size')).width;
      await tester.drag(
        handle,
        const Offset(60, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(saved.last.widthOf(DetailsColumn.size), 160);
      expect(saved.last.order, isEmpty);
      final cell = find.ancestor(
        of: find.text('cell-size'),
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(cell.first).width, 160);
      expect(before, lessThan(160));

      // Double-clicking the edge restores the default width.
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(saved.last.widths, isEmpty);
    });
  });
}
