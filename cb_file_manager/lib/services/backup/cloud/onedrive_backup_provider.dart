import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'cloud_backup_provider.dart';
import 'cloud_oauth_config.dart';
import 'oauth_cloud_provider.dart';

/// OneDrive backend, through Microsoft Graph.
class OneDriveBackupProvider extends OAuthCloudProvider {
  OneDriveBackupProvider({
    super.tokenStore,
    super.oauthClient,
    super.httpClient,
  });

  static const String _graph = 'https://graph.microsoft.com/v1.0';
  static const String _login = 'https://login.microsoftonline.com/common';

  String get _folder => OAuthCloudProvider.backupFolderName;

  @override
  String get id => 'onedrive';

  @override
  String get displayName => 'OneDrive';

  @override
  IconData get icon => PhosphorIconsLight.cloud;

  @override
  String get clientId => CloudOAuthConfig.microsoftClientId;

  @override
  Uri get authorizationEndpoint => Uri.parse('$_login/oauth2/v2.0/authorize');

  @override
  Uri get tokenEndpoint => Uri.parse('$_login/oauth2/v2.0/token');

  @override
  List<String> get scopes => const [
    'Files.ReadWrite',
    'User.Read',
    // Required for Microsoft to return a refresh token.
    'offline_access',
  ];

  @override
  Map<String, String> get extraAuthParams => const {
    'response_mode': 'query',
    'prompt': 'select_account',
  };

  @override
  Future<CloudAccount> fetchAccount(String accessToken) async {
    final response = await httpClient.get(
      Uri.parse('$_graph/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      return const CloudAccount(displayName: 'OneDrive');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudAccount(
      displayName: (json['displayName'] as String?) ?? '',
      email:
          (json['mail'] as String?) ?? (json['userPrincipalName'] as String?),
    );
  }

  @override
  Future<CloudBackupFile> upload({
    required File file,
    required String name,
  }) async {
    final bytes = await file.readAsBytes();
    final uri = Uri.parse(
      '$_graph/me/drive/root:/${Uri.encodeComponent(_folder)}/'
      '${Uri.encodeComponent(name)}:/content'
      '?%40microsoft.graph.conflictBehavior=rename',
    );
    final response = await sendAuthorized(
      (token) => http.Request('PUT', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/zip',
        })
        ..bodyBytes = bytes,
    );
    ensureSuccess(response, 'upload');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudBackupFile(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? name,
      size: (json['size'] as num?)?.toInt() ?? bytes.length,
      modified: DateTime.tryParse('${json['lastModifiedDateTime'] ?? ''}'),
    );
  }

  @override
  Future<List<CloudBackupFile>> listBackups() async {
    final uri = Uri.parse(
      '$_graph/me/drive/root:/${Uri.encodeComponent(_folder)}:/children'
      '?%24select=id,name,size,lastModifiedDateTime'
      '&%24orderby=lastModifiedDateTime%20desc&%24top=50',
    );
    final response = await sendAuthorized(
      (token) =>
          http.Request('GET', uri)..headers['Authorization'] = 'Bearer $token',
    );
    // The folder is created lazily by the first upload.
    if (response.statusCode == 404) return const [];
    ensureSuccess(response, 'listing backups');

    final items =
        (jsonDecode(response.body) as Map<String, dynamic>)['value'] as List? ??
        const [];
    return items.map((entry) {
      final item = Map<String, dynamic>.from(entry as Map);
      return CloudBackupFile(
        id: item['id'] as String,
        name: (item['name'] as String?) ?? '',
        size: (item['size'] as num?)?.toInt(),
        modified: DateTime.tryParse('${item['lastModifiedDateTime'] ?? ''}'),
      );
    }).toList();
  }

  @override
  Future<File> download(CloudBackupFile remote, String destinationPath) async {
    final response = await sendAuthorized(
      (token) => http.Request(
        'GET',
        Uri.parse('$_graph/me/drive/items/${remote.id}/content'),
      )..headers['Authorization'] = 'Bearer $token',
    );
    ensureSuccess(response, 'download');
    final file = File(destinationPath);
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  @override
  Future<void> delete(CloudBackupFile remote) async {
    final response = await sendAuthorized(
      (token) => http.Request(
        'DELETE',
        Uri.parse('$_graph/me/drive/items/${remote.id}'),
      )..headers['Authorization'] = 'Bearer $token',
    );
    ensureSuccess(response, 'delete');
  }
}
