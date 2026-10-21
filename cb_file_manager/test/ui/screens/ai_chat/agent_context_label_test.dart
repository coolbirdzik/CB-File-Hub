import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/ai/agent_workspace.dart';
import 'package:cb_file_manager/ui/screens/ai_chat/components/agent_context_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final home = p.join('Users', 'an');
  final downloads = p.join(home, 'Downloads');

  test('the workspace is the folder, else home, as the prompt uses it', () {
    for (final (path, kind, working) in [
      (downloads, AgentWorkspaceKind.folder, downloads),
      ('', AgentWorkspaceKind.drives, home),
      ('#drives', AgentWorkspaceKind.drives, home),
      ('#cb-agent-cleaner', AgentWorkspaceKind.cleaner, home),
      ('#gallery', AgentWorkspaceKind.screen, home),
      ('smb://nas/share', AgentWorkspaceKind.network, home),
    ]) {
      final workspace = AgentWorkspace.resolve(path, home: home);
      expect(workspace.kind, kind, reason: path);
      expect(workspace.workingDirectory, working, reason: path);
      expect(workspace.browsingPath, path, reason: path);
    }
  });

  Future<void> pump(WidgetTester tester, String path) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 2000,
            child: AgentContextLabel(currentPath: path, home: home),
          ),
        ),
      ),
    );
    // The app's localizations load asynchronously.
    await tester.pumpAndSettle();
  }

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text)).textSpan!.toPlainText();

  String hint(WidgetTester tester) => tester
      .widget<Tooltip>(find.byKey(const ValueKey('ai-context-label')))
      .message!;

  testWidgets('a folder names where the agent searches', (tester) async {
    await pump(tester, downloads);
    expect(shown(tester), 'Đang làm việc trong Downloads  ·  $downloads');
    expect(hint(tester), contains('thư mục này và các thư mục con'));
    expect(hint(tester), endsWith(downloads));
  });

  testWidgets('a screen names itself and the folder the agent falls back to', (
    tester,
  ) async {
    await pump(tester, '#gallery');
    expect(shown(tester), contains('thư mục mặc định: an'));
    expect(hint(tester), contains('không phải thư mục'));
    expect(hint(tester), contains(home));

    await pump(tester, '#cb-agent-cleaner');
    expect(shown(tester), startsWith('Kết quả quét Dọn dẹp'));

    await pump(tester, 'smb://nas/share');
    expect(shown(tester), startsWith('Thư mục mạng'));
    expect(hint(tester), contains('chưa đọc được thư mục mạng'));

    await pump(tester, '');
    expect(shown(tester), startsWith('Tất cả ổ đĩa'));
  });
}
