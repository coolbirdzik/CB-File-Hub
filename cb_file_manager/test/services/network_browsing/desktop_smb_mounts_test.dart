import 'package:cb_file_manager/services/network_browsing/desktop_smb_mounts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS uses the mounted volume and preserves literal filenames', () {
    final mounts = DesktopSmbMount.parseMacMounts('''
//alice@NAS/Shared%20Media on /Volumes/Shared Media on NAS (smbfs, nodev, mounted by alice)
/dev/disk3s1 on /Volumes/Local Media (apfs, local)
''');
    final mount = mounts.single;
    expect(mount.uri.toString(), 'smb://nas/Shared%20Media');
    expect(mount.directory, '/Volumes/Shared Media on NAS');

    final path = DesktopSmbMount.pathFor(
      Uri.parse('smb://NAS:445/shared%20media/4K/Movie%20%23%2520.mkv'),
      mounts,
    );
    expect(path, '/Volumes/Shared Media on NAS/4K/Movie #%20.mkv');
  });

  test('Linux selects CIFS and SMB3 from mountinfo', () {
    final mounts = DesktopSmbMount.parseLinuxMounts(r'''
33 20 0:30 / /mnt/NAS\040Media rw,nosuid shared:10 - cifs //nas/Shared\040Media rw,vers=3.1.1
35 20 0:32 / /mnt/other rw - smb3 //other/Videos/4K rw
36 20 0:33 /private /mnt/mismatched rw - cifs //nas/Private rw
37 20 8:17 / /mnt/disk rw - ext4 /dev/sdb1 rw
''');
    expect(mounts.map((mount) => mount.directory), [
      '/mnt/NAS Media',
      '/mnt/other',
    ]);
    expect(
      DesktopSmbMount.pathFor(
        Uri.parse('smb://nas/Shared%20Media/Video.mkv'),
        mounts,
      ),
      '/mnt/NAS Media/Video.mkv',
    );
    expect(
      DesktopSmbMount.pathFor(
        Uri.parse('smb://other/Videos/4K/Video.mkv'),
        mounts,
      ),
      '/mnt/other/Video.mkv',
    );
    expect(
      DesktopSmbMount.pathFor(
        Uri.parse('smb://other/Videos/Video.mkv'),
        mounts,
      ),
      isNull,
    );
  });

  test('Linux GVfs shares preserve escaped fields and the configured port', () {
    const directory =
        '/run/user/1000/gvfs/smb-share:port=1445,server=nas,share=Files%2C%20Home,user=alice';
    final mount = DesktopSmbMount.parseGvfsDirectory(directory)!;
    expect(mount.uri.toString(), 'smb://nas:1445/Files,%20Home');
    expect(
      DesktopSmbMount.pathFor(
        Uri.parse('smb://nas:1445/Files,%20Home/Video.mkv'),
        [mount],
      ),
      '$directory/Video.mkv',
    );
    expect(
      DesktopSmbMount.pathFor(Uri.parse('smb://nas/Files,%20Home/Video.mkv'), [
        mount,
      ]),
      isNull,
    );
    expect(
      DesktopSmbMount.parseGvfsDirectory('/run/user/1000/gvfs/sftp:host=nas'),
      isNull,
    );
  });

  test('only an unambiguous, credential-free file URL may use a mount', () {
    final mounts = DesktopSmbMount.parseMacMounts('''
//alice@nas/Videos on /Volumes/Videos (smbfs)
//bob@nas/Videos on /Volumes/Videos-1 (smbfs)
''');
    final url = Uri.parse('smb://nas/Videos/movie.mp4');
    expect(DesktopSmbMount.pathFor(url, mounts), isNull);
    expect(
      DesktopSmbMount.pathFor(url.replace(userInfo: 'alice:secret'), [
        mounts.first,
      ]),
      isNull,
    );
    expect(
      DesktopSmbMount.pathFor(url.replace(host: 'other-nas'), mounts),
      isNull,
    );
    expect(
      DesktopSmbMount.pathFor(
        Uri.parse('smb://nas/Videos/path%2Foutside.mp4'),
        [mounts.first],
      ),
      isNull,
    );
  });
}
