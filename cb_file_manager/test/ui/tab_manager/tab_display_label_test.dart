import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('folder tabs show their full current path even with the same name', () {
    final first = TabData(id: '1', name: 'Photos', path: r'C:\Work\Photos');
    final second = TabData(id: '2', name: 'Photos', path: r'D:\Backup\Photos');

    expect(first.displayLabel, r'C:\Work\Photos');
    expect(second.displayLabel, r'D:\Backup\Photos');
    expect(first.copyWith(path: '/home/user').displayLabel, '/home/user');
  });

  test('system and empty-path tabs use their friendly names', () {
    final tab = TabData(id: '1', name: 'Cài đặt', path: '#settings');

    expect(tab.displayLabel, 'Cài đặt');
    expect(tab.copyWith(path: '', name: 'Ổ đĩa').displayLabel, 'Ổ đĩa');
  });

  test('archive and network tabs show readable locations', () {
    final archive = TabData(
      id: '1',
      name: 'Photos',
      path: ArchivePathUtils.build(
        archiveFile: '/backups/june.zip',
        innerPath: 'Photos',
      ),
    );
    final remote = TabData(
      id: '2',
      name: 'Photos',
      path: '#network/FTP/user%3Apassword%40server/Photos/',
    );

    expect(archive.displayLabel, ArchivePathUtils.displayPath(archive.path));
    expect(remote.displayLabel, 'ftp://server/Photos/');
  });
}
