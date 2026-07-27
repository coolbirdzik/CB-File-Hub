import 'dart:typed_data';

import 'package:cb_file_manager/helpers/files/windows_shell_context_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a third-party Shell menu session with nested commands', () {
    final session = WindowsShellMenuSession.fromMap(<Object?, Object?>{
      'sessionId': '42',
      'entries': <Object?>[
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
    expect(session.entries, hasLength(1));
    expect(session.entries.single.label, '7-Zip');
    expect(session.entries.single.children.single.commandId, 17);
    expect(session.entries.single.children.single.label, 'Extract here');
    expect(
      session.entries.single.children.single.iconBytes,
      Uint8List.fromList(<int>[0x42, 0x4D]),
    );
  });
}
