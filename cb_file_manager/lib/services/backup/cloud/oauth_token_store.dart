import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cloud_backup_provider.dart';

/// OAuth material for one cloud provider.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.account,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final CloudAccount? account;

  /// Treated as expired a minute early so a request never races the clock.
  bool get isExpired =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes: 1)));

  OAuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    CloudAccount? account,
  }) => OAuthTokens(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAt: expiresAt ?? this.expiresAt,
    account: account ?? this.account,
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
    'account': account?.toJson(),
  };

  factory OAuthTokens.fromJson(Map<String, dynamic> json) => OAuthTokens(
    accessToken: json['accessToken'] as String? ?? '',
    refreshToken: json['refreshToken'] as String?,
    expiresAt: json['expiresAt'] == null
        ? null
        : DateTime.tryParse(json['expiresAt'] as String),
    account: json['account'] == null
        ? null
        : CloudAccount.fromJson(Map<String, dynamic>.from(json['account'])),
  );
}

/// Persists cloud tokens in the OS keychain/credential store.
class OAuthTokenStore {
  OAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String providerId) => 'cb_cloud_backup_tokens_$providerId';

  Future<OAuthTokens?> read(String providerId) async {
    try {
      final raw = await _storage.read(key: _key(providerId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OAuthTokens.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('OAuthTokenStore: failed to read $providerId tokens: $e');
      return null;
    }
  }

  Future<void> write(String providerId, OAuthTokens tokens) async {
    await _storage.write(
      key: _key(providerId),
      value: jsonEncode(tokens.toJson()),
    );
  }

  Future<void> clear(String providerId) async {
    await _storage.delete(key: _key(providerId));
  }
}
