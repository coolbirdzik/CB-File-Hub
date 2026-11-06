import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/desktop_new_file_service.dart';
import 'package:cb_file_manager/services/file_template_service.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/dialogs/create_file_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/components/folder_context_menu.dart';
import 'package:cb_file_manager/ui/widgets/inline_rename_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _RecordingFolderBloc extends Cubit<FolderListState>
    implements FolderListBloc {
  _RecordingFolderBloc() : super(FolderListState('/'));

  final events = <FolderListEvent>[];

  @override
  void add(FolderListEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('new folders skip both existing files and folders', () async {
    final root = await Directory.systemTemp.createTemp('cb-inline-create-');
    addTearDown(() => root.delete(recursive: true));
    await Directory(p.join(root.path, 'New folder')).create();
    await File(p.join(root.path, 'New folder (2)')).writeAsString('keep');

    final created = await DesktopNewFileService.instance.createFolder(
      root.path,
      'New folder',
    );

    expect(p.basename(created), 'New folder (3)');
    expect(await Directory(created).exists(), isTrue);
    expect(
      await File(p.join(root.path, 'New folder (2)')).readAsString(),
      'keep',
    );
  });

  for (final action in ['enter', 'escape', 'blur']) {
    testWidgets('new folder edits its item name with $action', (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('cb-inline-create-'),
      ))!;
      final controller = InlineRenameController();
      final bloc = _RecordingFolderBloc();
      addTearDown(() async {
        controller.dispose();
        await bloc.close();
        await root.delete(recursive: true);
      });
      late BuildContext itemContext;
      await tester.pumpWidget(
        _host(
          bloc: bloc,
          child: Builder(
            builder: (context) {
              itemContext = context;
              return ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Column(
                  children: [
                    if (controller.isRenaming)
                      SizedBox(
                        width: 200,
                        child: InlineRenameField(
                          controller: controller,
                          onCommit: () async =>
                              controller.commitRename(context),
                          onCancel: controller.cancelRename,
                        ),
                      ),
                    const TextField(key: ValueKey('outside')),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      String? createdPath;
      await tester.runAsync(
        () => FolderContextMenu.createNewFolder(
          context: itemContext,
          currentPath: root.path,
          onCreateFolder: (_) async =>
              fail('desktop must not prompt for a name'),
          onAfterFileCreated: (created) {
            createdPath = created;
            controller.startRename(created, commitOnBlur: true);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(controller.focusNode!.hasFocus, isTrue);
      expect(
        controller.textController!.selection.textInside(
          controller.textController!.text,
        ),
        controller.textController!.text,
      );
      await tester.enterText(find.byType(TextField).first, 'My folder');

      if (action == 'blur') {
        await tester.tap(find.byKey(const ValueKey('outside')));
      } else {
        await tester.sendKeyEvent(
          action == 'enter'
              ? LogicalKeyboardKey.enter
              : LogicalKeyboardKey.escape,
        );
      }
      await tester.pumpAndSettle();
      expect(controller.isRenaming, isFalse);
      final renames = bloc.events.whereType<RenameFileOrFolder>();
      if (action == 'escape') {
        expect(renames, isEmpty);
      } else {
        expect(renames.single.entity, isA<Directory>());
        expect(renames.single.entity.path, createdPath);
        expect(renames.single.newName, 'My folder');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop file type menu creates a file without a dialog', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('cb-inline-file-'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    await tester.runAsync(FileTemplateService.instance.init);
    final created = Completer<String>();
    await tester.pumpWidget(
      _host(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              CreateFileDialog.show(
                context,
                directoryPath: root.path,
                onAfterFileCreated: created.complete,
              ),
            ),
            child: const Text('Create file'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create file'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    final textFile = find.byKey(
      const ValueKey('context-menu-action-new_template:.txt'),
    );
    await tester.ensureVisible(textFile);
    await tester.tap(textFile);
    await tester.pumpAndSettle();
    // File creation awaits several OS operations; drain the widget zone
    // between real I/O completions rather than waiting on a fake-zone future.
    for (var attempt = 0; attempt < 50 && !created.isCompleted; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(created.isCompleted, isTrue);
    final createdPath = await created.future;
    expect(p.extension(createdPath), '.txt');
    expect(await tester.runAsync(() => File(createdPath).exists()), isTrue);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('starting another item keeps the new rename session alive', (
    tester,
  ) async {
    final controller = InlineRenameController();
    addTearDown(controller.dispose);
    controller.startRename(p.join('folder', 'first'));
    await tester.pumpWidget(
      _host(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.isRenaming
              ? SizedBox(
                  width: 200,
                  child: InlineRenameField(
                    controller: controller,
                    onCommit: () async => fail('stale blur must not commit'),
                    onCancel: controller.cancelRename,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.startRename(p.join('folder', 'second'), commitOnBlur: true);
    await tester.pumpAndSettle();
    expect(controller.renamingPath, p.join('folder', 'second'));
    expect(controller.textController!.text, 'second');
    expect(controller.commitOnBlur, isTrue);
  });
}

Widget _host({required Widget child, FolderListBloc? bloc}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en'), Locale('vi')],
  home: Scaffold(
    body: bloc == null
        ? child
        : BlocProvider<FolderListBloc>.value(value: bloc, child: child),
  ),
);
