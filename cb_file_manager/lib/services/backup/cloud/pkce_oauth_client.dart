import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'cloud_backup_provider.dart';
import 'oauth_token_store.dart';

/// Authorization-code + PKCE flow with a loopback redirect (RFC 8252).
///
/// The app opens the system browser and listens on `127.0.0.1` for the
/// redirect, so no client secret has to be trusted to the binary and no
/// platform specific URL scheme plumbing is needed.
class PkceOAuthClient {
  PkceOAuthClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Ports tried in order. Providers such as Dropbox require the redirect URI
  /// to match a registered value exactly, hence the fixed first choice.
  static const List<int> _preferredPorts = [53682, 53683, 53684];

  static const Duration _timeout = Duration(minutes: 5);

  Future<OAuthTokens> authorize({
    required Uri authorizationEndpoint,
    required Uri tokenEndpoint,
    required String clientId,
    String? clientSecret,
    required List<String> scopes,
    Map<String, String> extraAuthParams = const {},
    bool allowRandomPort = true,
  }) async {
    final server = await _bindLoopback(allowRandomPort: allowRandomPort);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final verifier = _randomString(64);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      final state = _randomString(24);

      final authUrl = authorizationEndpoint.replace(
        queryParameters: {
          ...authorizationEndpoint.queryParameters,
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': scopes.join(' '),
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
          ...extraAuthParams,
        },
      );

      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw CloudBackupException('Could not open the browser for sign-in');
      }

      final code = await _awaitRedirect(server, state);
      return await _exchange(
        tokenEndpoint: tokenEndpoint,
        body: {
          'client_id': clientId,
          if (clientSecret != null && clientSecret.isNotEmpty)
            'client_secret': clientSecret,
          'code': code,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
        },
      );
    } finally {
      await server.close(force: true);
    }
  }

  Future<OAuthTokens> refresh({
    required Uri tokenEndpoint,
    required String clientId,
    String? clientSecret,
    required String refreshToken,
    List<String> scopes = const [],
  }) async {
    final tokens = await _exchange(
      tokenEndpoint: tokenEndpoint,
      body: {
        'client_id': clientId,
        if (clientSecret != null && clientSecret.isNotEmpty)
          'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
        if (scopes.isNotEmpty) 'scope': scopes.join(' '),
      },
    );
    // Providers usually omit the refresh token on renewal; keep the old one.
    return tokens.refreshToken == null
        ? tokens.copyWith(refreshToken: refreshToken)
        : tokens;
  }

  Future<HttpServer> _bindLoopback({required bool allowRandomPort}) async {
    for (final port in _preferredPorts) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } on SocketException catch (e) {
        debugPrint('PkceOAuthClient: port $port unavailable ($e)');
      }
    }
    if (!allowRandomPort) {
      throw CloudBackupException(
        'Port 53682 is in use; close the app holding it and try again',
      );
    }
    return HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  }

  Future<String> _awaitRedirect(HttpServer server, String state) async {
    final completer = Completer<String>();
    final subscription = server.listen((request) async {
      final params = request.uri.queryParameters;
      final error = params['error'];
      final code = params['code'];
      final ok = error == null && code != null && params['state'] == state;

      request.response
        ..statusCode = ok ? HttpStatus.ok : HttpStatus.badRequest
        ..headers.contentType = ContentType.html
        ..write(_resultPage(ok: ok, error: error));
      await request.response.close();

      if (completer.isCompleted) return;
      if (error != null) {
        completer.completeError(
          CloudBackupException('Authorization was denied ($error)'),
        );
      } else if (code == null || params['state'] != state) {
        completer.completeError(
          CloudBackupException('Authorization response was invalid'),
        );
      } else {
        completer.complete(code);
      }
    });

    try {
      return await completer.future.timeout(
        _timeout,
        onTimeout: () =>
            throw CloudBackupException('Sign-in timed out, please try again'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<OAuthTokens> _exchange({
    required Uri tokenEndpoint,
    required Map<String, String> body,
  }) async {
    final response = await _http.post(
      tokenEndpoint,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudBackupException(
        'Token request failed (${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body);
    if (json is! Map || json['access_token'] is! String) {
      throw CloudBackupException('Token response did not contain a token');
    }
    final expiresIn = json['expires_in'];
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: expiresIn is num
          ? DateTime.now().add(Duration(seconds: expiresIn.toInt()))
          : null,
    );
  }

  String _randomString(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _resultPage({required bool ok, String? error}) {
    final title = ok ? 'CB File Hub is connected' : 'Sign-in failed';
    final detail = ok
        ? 'You can close this tab and go back to the app.'
        : 'Reason: ${error ?? 'unexpected response'}';
    return '''
<!doctype html>
<html><head><meta charset="utf-8"><title>$title</title></head>
<body style="font-family:system-ui,sans-serif;padding:48px;text-align:center">
<h2>$title</h2><p>$detail</p></body></html>''';
  }
}
