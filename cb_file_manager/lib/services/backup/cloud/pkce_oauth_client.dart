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
  PkceOAuthClient({
    http.Client? httpClient,
    Future<bool> Function(Uri url)? launchBrowser,
  }) : _http = httpClient ?? http.Client(),
       _launchBrowser = launchBrowser ?? _openExternal;

  final http.Client _http;
  final Future<bool> Function(Uri url) _launchBrowser;

  static Future<bool> _openExternal(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

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

      if (!await _launchBrowser(authUrl)) {
        throw CloudBackupException('Could not open the browser for sign-in');
      }

      final redirect = await _awaitRedirect(server, state);
      // The browser tab stays open until the code is exchanged, so the page
      // reports the real outcome instead of claiming success too early.
      try {
        final tokens = await _exchange(
          tokenEndpoint: tokenEndpoint,
          body: {
            'client_id': clientId,
            if (clientSecret != null && clientSecret.isNotEmpty)
              'client_secret': clientSecret,
            'code': redirect.code,
            'code_verifier': verifier,
            'grant_type': 'authorization_code',
            'redirect_uri': redirectUri,
          },
        );
        await _respond(redirect.request, ok: true);
        return tokens;
      } catch (error) {
        debugPrint('PkceOAuthClient: token exchange failed: $error');
        await _respond(redirect.request, ok: false, detail: '$error');
        rethrow;
      }
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

  /// Waits for the provider's redirect and returns it with the browser
  /// request still open, so [authorize] can answer once it knows the outcome.
  Future<({String code, HttpRequest request})> _awaitRedirect(
    HttpServer server,
    String state,
  ) async {
    final completer = Completer<({String code, HttpRequest request})>();
    final subscription = server.listen((request) async {
      final params = request.uri.queryParameters;
      final error = params['error'];
      final code = params['code'];

      // favicon.ico and similar side requests are not the redirect.
      if (error == null && code == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (completer.isCompleted) {
        await _respond(request, ok: false, detail: 'Sign-in already handled');
        return;
      }
      if (error != null) {
        final description = params['error_description'];
        final reason = description == null ? error : '$error: $description';
        await _respond(request, ok: false, detail: reason);
        completer.completeError(
          CloudBackupException('Authorization was denied ($reason)'),
        );
      } else if (params['state'] != state) {
        const reason =
            'This sign-in page belongs to an earlier attempt. '
            'Start the sign-in again from CB File Hub.';
        await _respond(request, ok: false, detail: reason);
        completer.completeError(CloudBackupException(reason));
      } else {
        completer.complete((code: code!, request: request));
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

  Future<void> _respond(
    HttpRequest request, {
    required bool ok,
    String? detail,
  }) async {
    try {
      request.response
        ..statusCode = ok ? HttpStatus.ok : HttpStatus.badRequest
        ..headers.contentType = ContentType.html
        ..write(_resultPage(ok: ok, detail: detail));
      await request.response.close();
    } catch (error) {
      // The user may already have closed the tab.
      debugPrint('PkceOAuthClient: could not answer the browser: $error');
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
        'Token request failed (${response.statusCode}): '
        '${_describeError(response.body)}',
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

  /// `invalid_client: Unauthorized` rather than the raw JSON body.
  String _describeError(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['error'] is String) {
        final description = json['error_description'];
        return description is String && description.isNotEmpty
            ? '${json['error']}: $description'
            : json['error'] as String;
      }
    } catch (_) {}
    return body;
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

  String _resultPage({required bool ok, String? detail}) {
    final title = ok ? 'CB File Hub is connected' : 'Sign-in failed';
    final message = ok
        ? 'You can close this tab and go back to the app.'
        : 'Reason: ${const HtmlEscape().convert(detail ?? 'unexpected response')}';
    return '''
<!doctype html>
<html><head><meta charset="utf-8"><title>$title</title></head>
<body style="font-family:system-ui,sans-serif;padding:48px;text-align:center">
<h2>$title</h2><p>$message</p></body></html>''';
  }
}
