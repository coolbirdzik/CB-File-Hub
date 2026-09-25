import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'cloud_backup_provider.dart';
import 'cloud_oauth_config.dart';

/// Google sign-in for Android and iOS.
///
/// The loopback redirect the desktop flow uses is deprecated by Google on
/// mobile (and custom URI schemes are no longer accepted either), so the
/// platform SDK is used instead: Credential Manager on Android, the Google
/// Sign-In SDK on iOS. It hands back short-lived access tokens with no refresh
/// token, so every call asks the SDK for the current token rather than caching
/// one — the SDK is what keeps the session alive.
class GoogleMobileAuth {
  GoogleMobileAuth({GoogleSignIn? signIn})
    : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;

  bool _initialized = false;
  GoogleSignInAccount? _user;
  String? _lastAccessToken;

  /// True on the platforms that must go through the SDK instead of the
  /// loopback flow.
  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Android authenticates against the *web* client id ("server client id"),
  /// without which the SDK cannot start. iOS reads its own client id from
  /// `Info.plist` (`GIDClientID`), so it needs no define here.
  bool get isConfigured =>
      Platform.isIOS || CloudOAuthConfig.googleServerClientId.isNotEmpty;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _signIn.initialize(
      serverClientId: CloudOAuthConfig.googleServerClientId.isEmpty
          ? null
          : CloudOAuthConfig.googleServerClientId,
    );
    _initialized = true;
  }

  /// Interactive sign-in; must be called from a user gesture.
  Future<CloudAccount> signIn(List<String> scopes) async {
    await _ensureInitialized();
    try {
      final user = await _signIn.authenticate(scopeHint: scopes);
      _user = user;
      // Authentication alone grants no API scopes, so ask for them right away
      // and fail the connect if the user declines.
      final authorization = await user.authorizationClient.authorizeScopes(
        scopes,
      );
      _lastAccessToken = authorization.accessToken;
      return _toAccount(user);
    } on GoogleSignInException catch (e) {
      throw CloudBackupException(_describe(e));
    }
  }

  /// A valid access token for [scopes], reusing the SDK's cached one.
  ///
  /// [forceRefresh] discards the token the API just rejected; the SDK caches
  /// tokens and would otherwise hand the same dead one back.
  Future<String> accessToken(
    List<String> scopes, {
    bool forceRefresh = false,
  }) async {
    await _ensureInitialized();
    final user = _user ??= await _restoreUser();
    if (user == null) {
      throw CloudBackupException(
        'Google Drive is not connected on this device',
      );
    }

    final client = user.authorizationClient;
    try {
      if (forceRefresh && _lastAccessToken != null) {
        await client.clearAuthorizationToken(accessToken: _lastAccessToken!);
      }
      final authorization = await client.authorizationForScopes(scopes);
      if (authorization == null) {
        throw CloudBackupException(
          'Google Drive access needs to be granted again',
        );
      }
      _lastAccessToken = authorization.accessToken;
      return authorization.accessToken;
    } on GoogleSignInException catch (e) {
      throw CloudBackupException(_describe(e));
    }
  }

  /// Silent sign-in, so a restart of the app does not force a new consent.
  Future<GoogleSignInAccount?> _restoreUser() async {
    try {
      return await _signIn.attemptLightweightAuthentication();
    } on GoogleSignInException catch (e) {
      debugPrint('GoogleMobileAuth: lightweight authentication failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    _user = null;
    _lastAccessToken = null;
    if (!_initialized) return;
    try {
      await _signIn.disconnect();
    } on GoogleSignInException catch (e) {
      debugPrint('GoogleMobileAuth: disconnect failed: $e');
    }
  }

  CloudAccount _toAccount(GoogleSignInAccount user) =>
      CloudAccount(displayName: user.displayName ?? '', email: user.email);

  String _describe(GoogleSignInException e) => switch (e.code) {
    GoogleSignInExceptionCode.canceled => 'Sign-in was cancelled',
    GoogleSignInExceptionCode.clientConfigurationError =>
      'This build is missing its Google client configuration',
    _ => 'Google sign-in failed: ${e.description ?? e.code.name}',
  };
}
