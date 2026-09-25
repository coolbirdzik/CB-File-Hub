import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'cloud_backup_provider.dart';
import 'cloud_oauth_config.dart';
import 'oauth_cloud_provider.dart';

/// Dropbox backend.
///
/// Dropbox addresses files by path rather than by id, so [CloudBackupFile.id]
/// carries the remote path here.
class DropboxBackupProvider extends OAuthCloudProvider {
  DropboxBackupProvider({
    super.tokenStore,
    super.oauthClient,
    super.httpClient,
  });

  static const String _rpcApi = 'https://api.dropboxapi.com';
  static const String _contentApi = 'https://content.dropboxapi.com';

  String get _folderPath => '/${OAuthCloudProvider.backupFolderName}';

  @override
  String get id => 'dropbox';

  @override
  String get displayName => 'Dropbox';

  @override
  IconData get icon => PhosphorIconsLight.dropboxLogo;

  @override
  String get clientId => CloudOAuthConfig.dropboxAppKey;

  @override
  Uri get authorizationEndpoint =>
      Uri.parse('https://www.dropbox.com/oauth2/authorize');

  @override
  Uri get tokenEndpoint => Uri.parse('$_rpcApi/oauth2/token');

  @override
  List<String> get scopes => const [
    'files.content.write',
    'files.content.read',
    'account_info.read',
  ];

  @override
  Map<String, String> get extraAuthParams => const {
    // Short-lived tokens plus a refresh token; without this Dropbox issues a
    // token that dies after four hours and cannot be renewed.
    'token_access_type': 'offline',
  };

  /// Dropbox validates the redirect URI against the registered list verbatim.
  @override
  bool get requiresFixedRedirectPort => true;

  @override
  Future<CloudAccount> fetchAccount(String accessToken) async {
    final response = await httpClient.post(
      Uri.parse('$_rpcApi/2/users/get_current_account'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      return const CloudAccount(displayName: 'Dropbox');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final name = json['name'];
    return CloudAccount(
      displayName: name is Map ? '${name['display_name'] ?? ''}' : '',
      email: json['email'] as String?,
    );
  }

  /// Dropbox passes call arguments in a header, which must stay ASCII.
  String _apiArg(Map<String, dynamic> args) {
    final encoded = jsonEncode(args);
    final buffer = StringBuffer();
    for (final rune in encoded.runes) {
      if (rune > 127) {
        buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  @override
  Future<CloudBackupFile> upload({
    required File file,
    required String name,
  }) async {
    final bytes = await file.readAsBytes();
    final response = await sendAuthorized(
      (token) => http.Request('POST', Uri.parse('$_contentApi/2/files/upload'))
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': _apiArg({
            'path': '$_folderPath/$name',
            'mode': 'add',
            'autorename': true,
            'mute': false,
          }),
        })
        ..bodyBytes = bytes,
    );
    ensureSuccess(response, 'upload');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudBackupFile(
      id: (json['path_display'] as String?) ?? '$_folderPath/$name',
      name: (json['name'] as String?) ?? name,
      size: (json['size'] as num?)?.toInt() ?? bytes.length,
      modified: DateTime.tryParse('${json['server_modified'] ?? ''}'),
    );
  }

  @override
  Future<List<CloudBackupFile>> listBackups() async {
    final response = await sendAuthorized(
      (token) => http.Request('POST', Uri.parse('$_rpcApi/2/files/list_folder'))
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({'path': _folderPath, 'limit': 50}),
    );
    // The folder only appears once the first backup is uploaded.
    if (response.statusCode == 409 &&
        response.body.contains('path/not_found')) {
      return const [];
    }
    ensureSuccess(response, 'listing backups');

    final entries =
        (jsonDecode(response.body) as Map<String, dynamic>)['entries']
            as List? ??
        const [];
    final files = entries
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .where((entry) => entry['.tag'] == 'file')
        .map(
          (entry) => CloudBackupFile(
            id:
                (entry['path_display'] as String?) ??
                (entry['path_lower'] as String? ?? ''),
            name: (entry['name'] as String?) ?? '',
            size: (entry['size'] as num?)?.toInt(),
            modified: DateTime.tryParse('${entry['server_modified'] ?? ''}'),
          ),
        )
        .toList();
    files.sort((a, b) {
      final left = a.modified;
      final right = b.modified;
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    });
    return files;
  }

  @override
  Future<File> download(CloudBackupFile remote, String destinationPath) async {
    final response = await sendAuthorized(
      (token) =>
          http.Request('POST', Uri.parse('$_contentApi/2/files/download'))
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Dropbox-API-Arg': _apiArg({'path': remote.id}),
            }),
    );
    ensureSuccess(response, 'download');
    final file = File(destinationPath);
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  @override
  Future<void> delete(CloudBackupFile remote) async {
    final response = await sendAuthorized(
      (token) => http.Request('POST', Uri.parse('$_rpcApi/2/files/delete_v2'))
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({'path': remote.id}),
    );
    ensureSuccess(response, 'delete');
  }
}
