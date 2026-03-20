part of 'video_player.dart';

class _SmbAuthInfo {
  const _SmbAuthInfo({
    required this.originalUrl,
    required this.urlWithoutUserInfo,
    this.user,
    this.password,
    this.domain,
    this.userName,
  });

  final String originalUrl;
  final String urlWithoutUserInfo;
  final String? user;
  final String? password;
  final String? domain;
  final String? userName;

  bool get hasUserInfo =>
      (user != null && user!.isNotEmpty) ||
      (password != null && password!.isNotEmpty);
}

extension _VlcSmbExt on _VideoPlayerState {
  _SmbAuthInfo _parseSmbAuth(String smbMrl) {
    final uri = Uri.parse(smbMrl);
    final userInfo = uri.userInfo;
    String? user;
    String? password;
    if (userInfo.isNotEmpty) {
      final parts = userInfo.split(':');
      if (parts.isNotEmpty) {
        user = Uri.decodeComponent(parts[0]);
      }
      if (parts.length > 1) {
        password = Uri.decodeComponent(parts[1]);
      }
    }
    String? domain;
    String? userName;
    if (user != null && user.isNotEmpty) {
      final semicolon = user.indexOf(';');
      final backslash = user.indexOf(r'\');
      if (semicolon > 0) {
        domain = user.substring(0, semicolon);
        userName = user.substring(semicolon + 1);
      } else if (backslash > 0) {
        domain = user.substring(0, backslash);
        userName = user.substring(backslash + 1);
      } else {
        userName = user;
      }
    }
    final cleaned = userInfo.isNotEmpty ? _stripUserInfo(smbMrl) : smbMrl;
    return _SmbAuthInfo(
      originalUrl: smbMrl,
      urlWithoutUserInfo: cleaned,
      user: user,
      password: password,
      domain: domain,
      userName: userName,
    );
  }

  String _stripUserInfo(String smbMrl) {
    final schemeIndex = smbMrl.indexOf('://');
    if (schemeIndex == -1) return smbMrl;
    final searchStart = schemeIndex + 3;
    final atIndex = smbMrl.indexOf('@', searchStart);
    if (atIndex == -1) return smbMrl;
    return smbMrl.substring(0, searchStart) + smbMrl.substring(atIndex + 1);
  }

  VlcPlayerController _createSmbVlcController({
    required String smbMrl,
    required bool useUserInfoInUrl,
    required bool autoPlay,
  }) {
    final auth = _parseSmbAuth(smbMrl);
    final baseUrl = useUserInfoInUrl && auth.hasUserInfo
        ? auth.originalUrl
        : auth.urlWithoutUserInfo;
    final smbUser = auth.userName ?? auth.user;

    // Avoid embedding credentials (even username-only) in the SMB URL.
    // libVLC's SMB URL parsing can be sensitive to userinfo (especially when passwords contain '@').
    // We pass credentials via VLC options instead.
    final url = baseUrl;
    const cachingMs = 1000;
    final advancedOptions = <String>[
      '--network-caching=$cachingMs',
      '--file-caching=$cachingMs',
    ];
    final extras = <String>[
      if (!useUserInfoInUrl) ':network-caching=$cachingMs',
      if (!useUserInfoInUrl) ':file-caching=$cachingMs',
      if (!useUserInfoInUrl && smbUser != null && smbUser.isNotEmpty)
        ':smb-user=$smbUser',
      if (!useUserInfoInUrl &&
          auth.password != null &&
          auth.password!.isNotEmpty)
        ':smb-pwd=${auth.password}',
      if (!useUserInfoInUrl && auth.domain != null && auth.domain!.isNotEmpty)
        ':smb-domain=${auth.domain}',
      if (!useUserInfoInUrl && smbUser != null && smbUser.isNotEmpty)
        '--smb-user=$smbUser',
      if (!useUserInfoInUrl &&
          auth.password != null &&
          auth.password!.isNotEmpty)
        '--smb-pwd=${auth.password}',
      if (!useUserInfoInUrl && auth.domain != null && auth.domain!.isNotEmpty)
        '--smb-domain=${auth.domain}',
    ];

    return VlcPlayerController.network(
      url,
      autoInitialize: true,
      hwAcc: _vlcHwAcc,
      autoPlay: autoPlay,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(advancedOptions),
        video: VlcVideoOptions([
          '--android-display-chroma=RV32',
        ]),
        extras: extras,
      ),
    );
  }
}
