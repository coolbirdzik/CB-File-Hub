import 'dart:io';

import 'package:cb_file_manager/helpers/files/windows_shell_context_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cb_file_manager/shell_context_menu');

  setUp(() async {
    await WindowsShellContextMenu.clearThirdPartyMenuCache();
  });

  tearDown(() async {
    await WindowsShellContextMenu.clearThirdPartyMenuCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('parses a third-party Shell menu session with nested commands', () {
    final session = WindowsShellMenuSession.fromMap(<Object?, Object?>{
      'sessionId': '42',
      'entries': <Object?>[
        <Object?, Object?>{
          'type': 'submenu',
          'submenuId': 5,
          'label': 'Lazy tools',
          'enabled': true,
        },
        <Object?, Object?>{
          'type': 'submenu',
          'label': '7-Zip',
          'enabled': true,
          'children': <Object?>[
            <Object?, Object?>{
              'type': 'item',
              'commandId': 17,
              'label': 'Extract here',
              'enabled': true,
              'checked': false,
              'iconBytes': Uint8List.fromList(<int>[0x42, 0x4D]),
            },
          ],
        },
      ],
    });

    expect(session.id, '42');
    expect(session.entries, hasLength(2));
    expect(session.entries.first.submenuId, 5);
    expect(session.entries.first.label, 'Lazy tools');
    expect(session.entries.last.label, '7-Zip');
    expect(session.entries.last.children.single.commandId, 17);
    expect(session.entries.last.children.single.label, 'Extract here');
    expect(
      session.entries.last.children.single.iconBytes,
      Uint8List.fromList(<int>[0x42, 0x4D]),
    );
  });

  test(
    'submenu commands inherit app icons without overriding their own icons',
    () {
      final appIcon = Uint8List.fromList([1, 2, 3]);
      final commandIcon = Uint8List.fromList([4, 5, 6]);
      final entry = WindowsShellMenuEntry(
        type: 'submenu',
        iconBytes: appIcon,
        submenuId: 12,
        children: [
          const WindowsShellMenuEntry(type: 'item', commandId: 17),
          WindowsShellMenuEntry(
            type: 'item',
            commandId: 18,
            iconBytes: commandIcon,
          ),
          WindowsShellMenuEntry(
            type: 'submenu',
            submenuId: 19,
            iconBytes: Uint8List(0),
            children: const [
              WindowsShellMenuEntry(type: 'item', commandId: 20),
            ],
          ),
        ],
      ).withInheritedIcon(null);
      expect(entry.children[0].iconBytes, same(appIcon));
      expect(entry.children[1].iconBytes, same(commandIcon));
      expect(entry.children[2].children.single.iconBytes, same(appIcon));
      expect(entry.children[2].children.single.commandId, 20);
      expect(
        const WindowsShellMenuEntry(
          type: 'item',
        ).withInheritedIcon(null).iconBytes,
        isNull,
      );
      // The same fallback applies to separately loaded, lazy native submenus.
      expect(
        const WindowsShellMenuEntry(
          type: 'item',
          commandId: 21,
        ).withInheritedIcon(appIcon).iconBytes,
        same(appIcon),
      );
    },
  );

  test('loads each native submenu once per cached Shell session', () async {
    var submenuLoadCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'loadThirdPartyMenu') {
            return <Object?, Object?>{
              'sessionId': 'lazy-session',
              'entries': <Object?>[
                <Object?, Object?>{
                  'type': 'submenu',
                  'submenuId': 11,
                  'label': 'Tools',
                },
              ],
            };
          }
          if (call.method == 'loadContextMenuSubmenu') {
            submenuLoadCalls++;
            return <Object?>[
              <Object?, Object?>{
                'type': 'item',
                'commandId': 27,
                'label': 'Inspect',
              },
            ];
          }
          return null;
        });

    final session = await WindowsShellContextMenu.loadThirdPartyMenu(
      paths: <String>[r'C:\Temp\Example.txt'],
    );
    final first = await WindowsShellContextMenu.loadThirdPartySubmenu(
      sessionId: session!.id,
      submenuId: session.entries.single.submenuId!,
    );
    final second = await WindowsShellContextMenu.loadThirdPartySubmenu(
      sessionId: session.id,
      submenuId: session.entries.single.submenuId!,
    );

    expect(first.single.label, 'Inspect');
    expect(second.single.commandId, 27);
    expect(submenuLoadCalls, 1);
  }, skip: !Platform.isWindows);

  test('reuses the cached Shell session for the same path selection', () async {
    expect(
      WindowsShellContextMenu.thirdPartyMenuCacheDuration,
      const Duration(minutes: 5),
    );

    var loadCalls = 0;
    var releaseCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'loadThirdPartyMenu':
              loadCalls++;
              return <Object?, Object?>{
                'sessionId': 'session-$loadCalls',
                'entries': <Object?>[
                  <Object?, Object?>{
                    'type': 'item',
                    'commandId': 7,
                    'label': 'Open in tool',
                  },
                ],
              };
            case 'releaseContextMenuSession':
              releaseCalls++;
              return null;
          }
          return null;
        });

    final first = await WindowsShellContextMenu.loadThirdPartyMenu(
      paths: <String>[r'C:\Temp\Example.txt'],
    );
    final second = await WindowsShellContextMenu.loadThirdPartyMenu(
      paths: <String>[r'c:/temp/example.txt'],
    );

    expect(first?.id, 'session-1');
    expect(second?.id, first?.id);
    expect(loadCalls, 1);

    final differentSelection = await WindowsShellContextMenu.loadThirdPartyMenu(
      paths: <String>[r'C:\Temp\Other.txt'],
    );
    expect(differentSelection?.id, 'session-2');
    expect(loadCalls, 2);
    expect(releaseCalls, 1);

    await WindowsShellContextMenu.clearThirdPartyMenuCache();
    expect(releaseCalls, 2);
  }, skip: !Platform.isWindows);

  test(
    'invalidates the cached Shell session after invoking a command',
    () async {
      var loadCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'loadThirdPartyMenu') {
              loadCalls++;
              return <Object?, Object?>{
                'sessionId': 'session-$loadCalls',
                'entries': <Object?>[
                  <Object?, Object?>{
                    'type': 'item',
                    'commandId': 9,
                    'label': 'Scan',
                  },
                ],
              };
            }
            if (call.method == 'invokeContextMenuCommand') {
              return true;
            }
            return null;
          });

      final first = await WindowsShellContextMenu.loadThirdPartyMenu(
        paths: <String>[r'C:\Temp\Example.txt'],
      );
      final invoked = await WindowsShellContextMenu.invokeSessionCommand(
        sessionId: first!.id,
        commandId: 9,
      );
      final second = await WindowsShellContextMenu.loadThirdPartyMenu(
        paths: <String>[r'C:\Temp\Example.txt'],
      );

      expect(invoked, isTrue);
      expect(second?.id, 'session-2');
      expect(loadCalls, 2);
    },
    skip: !Platform.isWindows,
  );
}
