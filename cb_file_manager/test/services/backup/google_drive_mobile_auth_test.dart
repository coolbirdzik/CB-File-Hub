import 'package:cb_file_manager/services/backup/cloud/cloud_backup_provider.dart';
import 'package:cb_file_manager/services/backup/cloud/google_drive_backup_provider.dart';
import 'package:cb_file_manager/services/backup/cloud/google_mobile_auth.dart';
import 'package:cb_file_manager/services/backup/cloud/oauth_token_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the platform SDK, which cannot run on the test host.
class _FakeMobileAuth extends GoogleMobileAuth {
  _FakeMobileAuth({this.configured = true});

  final bool configured;
  bool signedOut = false;
  int tokenCalls = 0;
  bool lastForceRefresh = false;
  List<String>? requestedScopes;

  @override
  bool get isConfigured => configured;

  @override
  Future<CloudAccount> signIn(List<String> scopes) async {
    requestedScopes = scopes;
    return const CloudAccount(displayName: 'Tester', email: 'a@example.com');
  }

  @override
  Future<String> accessToken(
    List<String> scopes, {
    bool forceRefresh = false,
  }) async {
    tokenCalls++;
    lastForceRefresh = forceRefresh;
    return 'sdk-token-$tokenCalls';
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

/// In-memory replacement for the keychain backed store.
class _MemoryTokenStore extends OAuthTokenStore {
  final Map<String, OAuthTokens> _entries = {};

  @override
  Future<OAuthTokens?> read(String providerId) async => _entries[providerId];

  @override
  Future<void> write(String providerId, OAuthTokens tokens) async =>
      _entries[providerId] = tokens;

  @override
  Future<void> clear(String providerId) async => _entries.remove(providerId);
}

void main() {
  late _FakeMobileAuth mobileAuth;
  late _MemoryTokenStore store;
  late GoogleDriveBackupProvider provider;

  setUp(() {
    mobileAuth = _FakeMobileAuth();
    store = _MemoryTokenStore();
    provider = GoogleDriveBackupProvider(
      mobileAuth: mobileAuth,
      tokenStore: store,
    );
  });

  test('connect signs in through the SDK and remembers the account', () async {
    final account = await provider.connect();

    expect(account.email, 'a@example.com');
    expect(mobileAuth.requestedScopes, [
      'https://www.googleapis.com/auth/drive.file',
    ]);
    expect((await provider.currentAccount())?.email, 'a@example.com');
  });

  test('access tokens come from the SDK, not the token store', () async {
    await provider.connect();

    expect(await provider.accessToken(), 'sdk-token-1');
    expect(mobileAuth.lastForceRefresh, isFalse);

    expect(await provider.accessToken(forceRefresh: true), 'sdk-token-2');
    expect(mobileAuth.lastForceRefresh, isTrue);
  });

  test('disconnect signs out of the SDK and forgets the account', () async {
    await provider.connect();
    await provider.disconnect();

    expect(mobileAuth.signedOut, isTrue);
    expect(await provider.currentAccount(), isNull);
  });

  test('an unconfigured mobile build reports the provider as unavailable', () {
    final unconfigured = GoogleDriveBackupProvider(
      mobileAuth: _FakeMobileAuth(configured: false),
      tokenStore: _MemoryTokenStore(),
    );

    expect(unconfigured.isConfigured, isFalse);
    expect(unconfigured.connect(), throwsA(isA<CloudBackupException>()));
  });
}
