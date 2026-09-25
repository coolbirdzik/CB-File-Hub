import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'cloud_backup_provider.dart';
import 'cloud_oauth_config.dart';
import 'google_mobile_auth.dart';
import 'oauth_cloud_provider.dart';

/// Google Drive backend.
///
/// Uses the `drive.file` scope, so CB File Hub only ever sees the folder and
/// archives it created itself - the rest of the user's Drive stays private.
class GoogleDriveBackupProvider extends OAuthCloudProvider {
  GoogleDriveBackupProvider({
    super.tokenStore,
    super.oauthClient,
    super.httpClient,
    GoogleMobileAuth? mobileAuth,
  }) : _mobileAuth =
           mobileAuth ??
           (GoogleMobileAuth.isSupportedPlatform ? GoogleMobileAuth() : null);

  /// Set on Android and iOS, where Google no longer accepts the loopback
  /// redirect and the platform SDK owns the tokens instead.
  final GoogleMobileAuth? _mobileAuth;

  static const String _filesApi = 'https://www.googleapis.com/drive/v3/files';
  static const String _uploadApi =
      'https://www.googleapis.com/upload/drive/v3/files';
  static const String _folderMime = 'application/vnd.google-apps.folder';

  String? _cachedFolderId;

  @override
  String get id => 'google_drive';

  @override
  String get displayName => 'Google Drive';

  @override
  IconData get icon => PhosphorIconsLight.googleDriveLogo;

  @override
  String get clientId => CloudOAuthConfig.googleClientId;

  @override
  String? get clientSecret => CloudOAuthConfig.googleClientSecret;

  @override
  Uri get authorizationEndpoint =>
      Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');

  @override
  Uri get tokenEndpoint => Uri.parse('https://oauth2.googleapis.com/token');

  @override
  List<String> get scopes => const [
    'https://www.googleapis.com/auth/drive.file',
    'openid',
    'email',
  ];

  @override
  Map<String, String> get extraAuthParams => const {
    // Without both of these Google hands back no refresh token on re-consent.
    'access_type': 'offline',
    'prompt': 'consent',
  };

  /// On mobile the SDK decides whether sign-in is possible, so the desktop
  /// client id being absent there is irrelevant.
  @override
  bool get isConfigured =>
      _mobileAuth?.isConfigured ?? CloudOAuthConfig.googleClientId.isNotEmpty;

  @override
  Future<CloudAccount> connect() async {
    final mobileAuth = _mobileAuth;
    if (mobileAuth == null) return super.connect();

    if (!mobileAuth.isConfigured) {
      throw CloudBackupException(
        '$displayName is not configured in this build',
      );
    }
    // Only drive.file is requested here: the profile comes from the
    // authentication step, so openid/email need no separate authorization.
    final account = await mobileAuth.signIn(const [
      'https://www.googleapis.com/auth/drive.file',
    ]);
    await rememberAccount(account);
    return account;
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    final mobileAuth = _mobileAuth;
    if (mobileAuth == null) {
      return super.accessToken(forceRefresh: forceRefresh);
    }
    return mobileAuth.accessToken(const [
      'https://www.googleapis.com/auth/drive.file',
    ], forceRefresh: forceRefresh);
  }

  @override
  Future<CloudAccount> fetchAccount(String accessToken) async {
    final response = await httpClient.get(
      Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      return const CloudAccount(displayName: 'Google Drive');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudAccount(
      displayName: (json['name'] as String?) ?? '',
      email: json['email'] as String?,
    );
  }

  @override
  Future<void> disconnect() async {
    _cachedFolderId = null;
    await _mobileAuth?.signOut();
    await super.disconnect();
  }

  Future<String> _backupFolderId() async {
    if (_cachedFolderId != null) return _cachedFolderId!;

    final folderName = OAuthCloudProvider.backupFolderName;
    final query =
        "mimeType='$_folderMime' and trashed=false and name='$folderName'";
    final found = await sendAuthorized(
      (token) => http.Request(
        'GET',
        Uri.parse(
          _filesApi,
        ).replace(queryParameters: {'q': query, 'fields': 'files(id,name)'}),
      )..headers['Authorization'] = 'Bearer $token',
    );
    ensureSuccess(found, 'folder lookup');
    final files =
        (jsonDecode(found.body) as Map<String, dynamic>)['files'] as List?;
    if (files != null && files.isNotEmpty) {
      return _cachedFolderId = (files.first as Map)['id'] as String;
    }

    final created = await sendAuthorized(
      (token) => http.Request('POST', Uri.parse(_filesApi))
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({'name': folderName, 'mimeType': _folderMime}),
    );
    ensureSuccess(created, 'folder creation');
    return _cachedFolderId =
        (jsonDecode(created.body) as Map<String, dynamic>)['id'] as String;
  }

  @override
  Future<CloudBackupFile> upload({
    required File file,
    required String name,
  }) async {
    final folderId = await _backupFolderId();
    final bytes = await file.readAsBytes();

    // Resumable upload: multipart is capped at 5 MB and a tag database can
    // grow past that.
    final session = await sendAuthorized(
      (token) =>
          http.Request(
              'POST',
              Uri.parse(_uploadApi).replace(
                queryParameters: {
                  'uploadType': 'resumable',
                  'fields': 'id,name',
                },
              ),
            )
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
              'X-Upload-Content-Type': 'application/zip',
              'X-Upload-Content-Length': '${bytes.length}',
            })
            ..body = jsonEncode({
              'name': name,
              'parents': [folderId],
            }),
    );
    ensureSuccess(session, 'upload session');
    final location = session.headers['location'];
    if (location == null) {
      throw CloudBackupException('Google Drive did not start the upload');
    }

    final uploaded = await sendAuthorized(
      (token) => http.Request('PUT', Uri.parse(location))
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/zip',
        })
        ..bodyBytes = bytes,
    );
    ensureSuccess(uploaded, 'upload');
    final json = jsonDecode(uploaded.body) as Map<String, dynamic>;
    return CloudBackupFile(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? name,
      size: bytes.length,
      modified: DateTime.now(),
    );
  }

  @override
  Future<List<CloudBackupFile>> listBackups() async {
    final folderId = await _backupFolderId();
    final response = await sendAuthorized(
      (token) => http.Request(
        'GET',
        Uri.parse(_filesApi).replace(
          queryParameters: {
            'q': "'$folderId' in parents and trashed=false",
            'orderBy': 'modifiedTime desc',
            'fields': 'files(id,name,size,modifiedTime)',
            'pageSize': '50',
          },
        ),
      )..headers['Authorization'] = 'Bearer $token',
    );
    ensureSuccess(response, 'listing backups');
    final files =
        (jsonDecode(response.body) as Map<String, dynamic>)['files'] as List? ??
        const [];
    return files.map((entry) {
      final item = Map<String, dynamic>.from(entry as Map);
      return CloudBackupFile(
        id: item['id'] as String,
        name: (item['name'] as String?) ?? '',
        size: int.tryParse('${item['size'] ?? ''}'),
        modified: DateTime.tryParse('${item['modifiedTime'] ?? ''}'),
      );
    }).toList();
  }

  @override
  Future<File> download(CloudBackupFile remote, String destinationPath) async {
    final response = await sendAuthorized(
      (token) => http.Request(
        'GET',
        Uri.parse(
          '$_filesApi/${remote.id}',
        ).replace(queryParameters: {'alt': 'media'}),
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
      (token) =>
          http.Request('DELETE', Uri.parse('$_filesApi/${remote.id}'))
            ..headers['Authorization'] = 'Bearer $token',
    );
    ensureSuccess(response, 'delete');
  }
}
