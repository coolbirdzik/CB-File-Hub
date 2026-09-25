import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cloud_backup_provider.dart';
import 'oauth_token_store.dart';
import 'pkce_oauth_client.dart';

/// Shared plumbing for the OAuth backed drives: sign-in, token refresh and
/// authorized requests that retry once after a 401.
abstract class OAuthCloudProvider implements CloudBackupProvider {
  OAuthCloudProvider({
    OAuthTokenStore? tokenStore,
    PkceOAuthClient? oauthClient,
    http.Client? httpClient,
  }) : _tokens = tokenStore ?? OAuthTokenStore(),
       _oauth = oauthClient ?? PkceOAuthClient(),
       httpClient = httpClient ?? http.Client();

  final OAuthTokenStore _tokens;
  final PkceOAuthClient _oauth;

  @protected
  final http.Client httpClient;

  /// The folder every archive of this app is written to.
  static const String backupFolderName = 'CB File Hub Backups';

  @override
  String get remoteFolderName => backupFolderName;

  @protected
  String get clientId;

  @protected
  String? get clientSecret => null;

  @protected
  Uri get authorizationEndpoint;

  @protected
  Uri get tokenEndpoint;

  @protected
  List<String> get scopes;

  @protected
  Map<String, String> get extraAuthParams => const {};

  /// Dropbox matches the redirect URI exactly, so it cannot fall back to a
  /// random loopback port the way Google and Microsoft can.
  @protected
  bool get requiresFixedRedirectPort => false;

  /// Reads the profile of the signed-in user for display in the UI.
  @protected
  Future<CloudAccount> fetchAccount(String accessToken);

  @override
  bool get isConfigured => clientId.isNotEmpty;

  @override
  Future<CloudAccount?> currentAccount() async =>
      (await _tokens.read(id))?.account;

  @override
  Future<CloudAccount> connect() async {
    if (!isConfigured) {
      throw CloudBackupException(
        '$displayName is not configured in this build',
      );
    }
    var tokens = await _oauth.authorize(
      authorizationEndpoint: authorizationEndpoint,
      tokenEndpoint: tokenEndpoint,
      clientId: clientId,
      clientSecret: clientSecret,
      scopes: scopes,
      extraAuthParams: extraAuthParams,
      allowRandomPort: !requiresFixedRedirectPort,
    );
    final account = await fetchAccount(tokens.accessToken);
    tokens = tokens.copyWith(account: account);
    await _tokens.write(id, tokens);
    return account;
  }

  /// Remembers who is signed in when the tokens themselves live elsewhere,
  /// as on mobile where the platform SDK owns them.
  @protected
  Future<void> rememberAccount(CloudAccount account) =>
      _tokens.write(id, OAuthTokens(accessToken: '', account: account));

  @override
  Future<void> disconnect() => _tokens.clear(id);

  /// Valid access token, refreshing first when the cached one expired.
  @protected
  Future<String> accessToken({bool forceRefresh = false}) async {
    final stored = await _tokens.read(id);
    if (stored == null) {
      throw CloudBackupException('$displayName is not connected');
    }
    if (!forceRefresh && !stored.isExpired) return stored.accessToken;

    final refreshToken = stored.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw CloudBackupException(
        'The $displayName session expired, please connect again',
      );
    }
    final refreshed = await _oauth.refresh(
      tokenEndpoint: tokenEndpoint,
      clientId: clientId,
      clientSecret: clientSecret,
      refreshToken: refreshToken,
    );
    final merged = refreshed.copyWith(account: stored.account);
    await _tokens.write(id, merged);
    return merged.accessToken;
  }

  /// Sends a request built from a fresh access token, retrying once with a
  /// refreshed token when the service reports the token is no longer valid.
  @protected
  Future<http.Response> sendAuthorized(
    http.BaseRequest Function(String accessToken) build,
  ) async {
    var response = await http.Response.fromStream(
      await httpClient.send(build(await accessToken())),
    );
    if (response.statusCode == 401) {
      debugPrint('$id: access token rejected, refreshing');
      response = await http.Response.fromStream(
        await httpClient.send(build(await accessToken(forceRefresh: true))),
      );
    }
    return response;
  }

  @protected
  void ensureSuccess(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw CloudBackupException(
      '$displayName: $action failed (${response.statusCode}) '
      '${response.body.isEmpty ? '' : response.body}',
    );
  }
}
