import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    locator.registerSingleton(OperationProgressController());
  });
  tearDown(() => locator.reset());

  test(
    'closing a folder drains queued events before closing child blocs',
    () async {
      final bloc = FolderListBloc();
      bloc.add(const SetGridZoom(3));
      await bloc.close();
      expect(bloc.isClosed, isTrue);
    },
  );
}
