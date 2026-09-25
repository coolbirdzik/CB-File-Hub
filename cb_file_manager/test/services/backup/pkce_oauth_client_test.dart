import 'dart:convert';

import 'package:cb_file_manager/services/backup/cloud/cloud_backup_provider.dart';
import 'package:cb_file_manager/services/backup/cloud/pkce_oauth_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final tokenEndpoint = Uri.parse('https://auth.example.com/token');

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
