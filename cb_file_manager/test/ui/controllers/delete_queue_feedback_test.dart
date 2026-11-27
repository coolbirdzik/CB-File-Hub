import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/components/common/operation_progress_overlay.dart';
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/dialogs/delete_confirmation_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';

class _FolderBloc extends Fake implements FolderListBloc {
  final events = <FolderListEvent>[];
  @override
  FolderListState get state => FolderListState('/');
  @override
  bool get isClosed => false;
  @override
  void add(FolderListEvent event) => events.add(event);
}

void main() {
  late OperationProgressController progress;
  late _FolderBloc folder;
  setUp(() {
    progress = OperationProgressController();
    folder = _FolderBloc();
    locator.registerSingleton(progress);
  });
  tearDown(() async {
    await locator.unregister<OperationProgressController>();
    progress.dispose();
  });

  Future<void> openDelete(WidgetTester tester, bool permanent) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeConfig.getLightTheme(),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => FileOperationsHandler.handleDelete(
                context: context,
                folderListBloc: folder,
                selectedFiles: const [r'C:\queue-test.tmp'],
                selectedFolders: const [],
                permanent: permanent,
                onClearSelection: () {},
              ),
              child: const Text('Request delete'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request delete'));
    await tester.pumpAndSettle();
  }

  for (final permanent in [false, true]) {
    testWidgets(
      'confirmation acknowledges queued deletion immediately ($permanent)',
      (tester) async {
        await openDelete(tester, permanent);
        final confirm = find.descendant(
          of: find.byType(DeleteConfirmationDialog),
          matching: find.widgetWithText(TextButton, 'Xóa'),
        );
        await tester.tap(confirm);
        await tester.pump();
        // The fake only records the event: no disk operation has completed.
        expect(folder.events.single, isA<FolderListDeleteItems>());
        expect(
          find.text(
            permanent
                ? 'Đã thêm 1 mục vào hàng đợi xóa vĩnh viễn.'
                : 'Đã thêm 1 mục vào hàng đợi chuyển vào Thùng rác.',
          ),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xem tiến trình'));
        await tester.pumpAndSettle();
        expect(find.byType(StatusCenterPanel), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      },
    );
  }

  testWidgets('cancel does not queue or announce deletion', (tester) async {
    await openDelete(tester, false);
    final dialog = tester.widget<DeleteConfirmationDialog>(
      find.byType(DeleteConfirmationDialog),
    );
    await tester.tap(find.widgetWithText(TextButton, dialog.cancelText));
    await tester.pumpAndSettle();
    expect(folder.events, isEmpty);
    expect(find.text('Xem tiến trình'), findsNothing);
  });
}
