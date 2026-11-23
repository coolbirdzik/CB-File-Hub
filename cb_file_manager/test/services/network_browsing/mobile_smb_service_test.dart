import 'package:cb_file_manager/services/network_browsing/mobile_smb_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_smb_native/mobile_smb_native.dart';

void main() {
  test('mobile SMB hides hidden shares only at the server root', () async {
    final originalPlatform = MobileSmbNativePlatform.instance;
    MobileSmbNativePlatform.instance = _SmbPlatform();
    addTearDown(() => MobileSmbNativePlatform.instance = originalPlatform);

    final service = _ConnectedSmbService();
    final shares = await service.listDirectory('#network/SMB/nas/');
    expect(shares.map((share) => share.path), [
      '#network/SMB/nas/D/',
      '#network/SMB/nas/Shared%20Docs/',
    ]);

    final folders = await service.listDirectory('#network/SMB/nas/D/');
    expect(folders.map((folder) => folder.path), [
      '#network/SMB/nas/D/Tax%24/',
    ]);
  });
}

class _ConnectedSmbService extends MobileSMBService {
  @override
  bool get isConnected => true;
}

class _SmbPlatform extends MobileSmbNativePlatform {
  @override
  Future<List<String>> listShares() async => [
    'D',
    r'D$',
    r'E$',
    r'ADMIN$',
    r'IPC$',
    r'Backups$',
    'Shared Docs',
  ];

  @override
  Future<List<SmbFile>> listDirectory(String path) async => const [
    SmbFile(name: r'Tax$', path: r'/D/Tax$', isDirectory: true, size: 0),
  ];
}
