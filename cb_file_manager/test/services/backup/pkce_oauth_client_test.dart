import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/backup/cloud/cloud_backup_provider.dart';
import 'package:cb_file_manager/services/backup/cloud/oauth_token_store.dart';
import 'package:cb_file_manager/services/backup/cloud/pkce_oauth_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Plays the browser: fetches [path] on the loopback redirect of [authUrl].
Future<({int status, String body})> _browse(
  Uri authUrl, {
  String path = '/',
  Map<String, String>? query,
}) async {
  final redirect = Uri.parse(authUrl.queryParameters['redirect_uri']!);
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      redirect.replace(path: path, queryParameters: query),
    );
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await response.transform(utf8.decoder).join(),
    );
  } finally {
    client.close();
  }
}

void main() {
  final tokenEndpoint = Uri.parse('https://auth.example.com/token');
  final authEndpoint = Uri.parse('https://auth.example.com/authorize');

  group('authorize', () {
    Future<OAuthTokens> signIn(PkceOAuthClient client) => client.authorize(
      authorizationEndpoint: authEndpoint,
      tokenEndpoint: tokenEndpoint,
      clientId: 'client',
      scopes: const ['scope'],
    );

    Map<String, String> callback(Uri url) => {
      'code': 'abc',
      'state': url.queryParameters['state']!,
    };

    test(
      'ignores side requests and reports success after the exchange',
      () async {
        // The server only starts answering once launchBrowser returns, so the
        // requests are fired without awaiting them there.
        late Future<({int status, String body})> favicon;
        late Future<({int status, String body})> page;
        final tokens = await signIn(
          PkceOAuthClient(
            httpClient: MockClient((request) async {
              expect(Uri.splitQueryString(request.body)['code'], 'abc');
              return http.Response(jsonEncode({'access_token': 'token'}), 200);
            }),
            launchBrowser: (url) async {
              expect(url.queryParameters['code_challenge_method'], 'S256');
              favicon = _browse(url, path: '/favicon.ico');
              page = favicon.then((_) => _browse(url, query: callback(url)));
              return true;
            },
          ),
        );

        expect(tokens.accessToken, 'token');
        expect((await favicon).status, HttpStatus.notFound);
        final result = await page;
        expect(result.status, HttpStatus.ok);
        expect(result.body, contains('connected'));
      },
    );

    test('shows the token error in the browser and throws', () async {
      late Future<({int status, String body})> page;
      final attempt = signIn(
        PkceOAuthClient(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': 'invalid_client',
                'error_description': 'Unauthorized',
              }),
              401,
            ),
          ),
          launchBrowser: (url) async {
            page = _browse(url, query: callback(url));
            return true;
          },
        ),
      );

      await expectLater(
        attempt,
        throwsA(
          isA<CloudBackupException>().having(
            (error) => error.message,
            'message',
            contains('invalid_client: Unauthorized'),
          ),
        ),
      );
      final result = await page;
      expect(result.status, HttpStatus.badRequest);
      expect(result.body, contains('invalid_client: Unauthorized'));
    });

    test('rejects a redirect from an earlier attempt', () async {
      late Future<({int status, String body})> page;
      final attempt = signIn(
        PkceOAuthClient(
          httpClient: MockClient((_) async => fail('must not exchange')),
          launchBrowser: (url) async {
            page = _browse(url, query: {'code': 'abc', 'state': 'stale'});
            return true;
          },
        ),
      );

      await expectLater(attempt, throwsA(isA<CloudBackupException>()));
      expect((await page).body, contains('earlier attempt'));
    });
  });

  test(
    'refresh keeps the old refresh token when the provider omits it',
    () async {
      late Map<String, String> sentBody;
      final client = PkceOAuthClient(
        httpClient: MockClient((request) async {
          sentBody = Uri.splitQueryString(request.body);
          return http.Response(
            jsonEncode({'access_token': 'new-access', 'expires_in': 3600}),
            200,
          );
        }),
      );

      final tokens = await client.refresh(
        tokenEndpoint: tokenEndpoint,
        clientId: 'client',
        refreshToken: 'old-refresh',
        scopes: const ['a', 'b'],
      );

      expect(tokens.accessToken, 'new-access');
      expect(tokens.refreshToken, 'old-refresh');
      expect(tokens.expiresAt!.isAfter(DateTime.now()), isTrue);
      expect(sentBody['grant_type'], 'refresh_token');
      expect(sentBody['scope'], 'a b');
      expect(sentBody.containsKey('client_secret'), isFalse);
    },
  );

  test('refresh adopts a rotated refresh token', () async {
    final client = PkceOAuthClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'access_token': 'a', 'refresh_token': 'rotated'}),
          200,
        ),
      ),
    );

    final tokens = await client.refresh(
      tokenEndpoint: tokenEndpoint,
      clientId: 'client',
      clientSecret: 'secret',
      refreshToken: 'old',
    );

    expect(tokens.refreshToken, 'rotated');
    expect(tokens.expiresAt, isNull);
  });

  test('a rejected token request surfaces as CloudBackupException', () async {
    final client = PkceOAuthClient(
      httpClient: MockClient(
        (_) async => http.Response('{"error":"invalid_grant"}', 400),
      ),
    );

    expect(
      client.refresh(
        tokenEndpoint: tokenEndpoint,
        clientId: 'client',
        refreshToken: 'revoked',
      ),
      throwsA(isA<CloudBackupException>()),
    );
  });

  test('a response without access_token is rejected', () async {
    final client = PkceOAuthClient(
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      client.refresh(
        tokenEndpoint: tokenEndpoint,
        clientId: 'client',
        refreshToken: 'r',
      ),
      throwsA(isA<CloudBackupException>()),
    );
  });
}
