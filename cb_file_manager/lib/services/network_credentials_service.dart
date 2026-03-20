import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/database/network_credentials.dart';
import '../models/database/sqlite_database_provider.dart';

/// Stores and looks up saved network credentials.
class NetworkCredentialsService {
  static final NetworkCredentialsService _instance =
      NetworkCredentialsService._();

  factory NetworkCredentialsService() => _instance;

  final SqliteDatabaseProvider _dbProvider = SqliteDatabaseProvider();
  final List<NetworkCredentials> _credentialsCache = <NetworkCredentials>[];
  Future<void>? _initializing;
  bool _isInitialized = false;

  NetworkCredentialsService._();

  Future<void> init() => initialize();

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    if (_initializing != null) {
      await _initializing;
      return;
    }

    _initializing = _loadCache();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _loadCache() async {
    await _dbProvider.initialize();
    final database = await _dbProvider.getDatabase();
    final rows = await database.query(
      'network_credentials',
      orderBy: 'last_connected DESC, id DESC',
    );

    _credentialsCache
      ..clear()
      ..addAll(rows.map(NetworkCredentials.fromDatabaseMap));
    _isInitialized = true;
  }

  Future<int> saveCredentials({
    required String serviceType,
    required String host,
    required String username,
    required String password,
    int? port,
    String? domain,
    Map<String, dynamic>? additionalOptions,
  }) async {
    await initialize();
    final database = await _dbProvider.getDatabase();

    final credentials = NetworkCredentials(
      serviceType: serviceType,
      host: host,
      username: username,
      password: password,
      port: port,
      domain: domain,
      additionalOptions:
          additionalOptions != null ? jsonEncode(additionalOptions) : null,
      lastConnected: DateTime.now(),
    );

    final existingIndex = _credentialsCache.indexWhere(
      (item) =>
          item.serviceType == serviceType &&
          item.normalizedHost.toLowerCase() ==
              credentials.normalizedHost.toLowerCase() &&
          item.username == username,
    );

    if (existingIndex >= 0) {
      credentials.id = _credentialsCache[existingIndex].id;
    }

    final id = await database.insert(
      'network_credentials',
      credentials.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    credentials.id = id;

    if (existingIndex >= 0) {
      _credentialsCache.removeAt(existingIndex);
    }
    _credentialsCache.insert(0, credentials);

    return id;
  }

  NetworkCredentials? findCredentials({
    required String serviceType,
    required String host,
    String? username,
  }) {
    _checkInitialized();

    final normalizedHost = host
        .replaceAll(RegExp(r'^[a-z]+://'), '')
        .replaceAll(RegExp(r':\d+$'), '')
        .toLowerCase();

    NetworkCredentials? bestMatch;

    for (final credentials in _credentialsCache) {
      if (credentials.serviceType != serviceType) {
        continue;
      }
      if (credentials.normalizedHost.toLowerCase() != normalizedHost) {
        continue;
      }

      if (username != null && username.isNotEmpty) {
        if (credentials.username == username) {
          return credentials;
        }
        continue;
      }

      if (bestMatch == null ||
          credentials.lastConnected.isAfter(bestMatch.lastConnected)) {
        bestMatch = credentials;
      }
    }

    return bestMatch;
  }

  List<NetworkCredentials> getCredentialsByServiceType(String serviceType) {
    _checkInitialized();

    return _credentialsCache
        .where((credentials) => credentials.serviceType == serviceType)
        .toList(growable: false);
  }

  bool deleteCredentials(int id) {
    _checkInitialized();

    final existingLength = _credentialsCache.length;
    _credentialsCache.removeWhere((credentials) => credentials.id == id);
    final removed = _credentialsCache.length != existingLength;
    if (removed) {
      unawaited(_deleteCredentialsFromDatabase(id));
    }
    return removed;
  }

  Future<void> _deleteCredentialsFromDatabase(int id) async {
    try {
      final database = await _dbProvider.getDatabase();
      await database.delete(
        'network_credentials',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    } catch (error) {
      debugPrint('Error deleting credentials: $error');
    }
  }

  void _checkInitialized() {
    if (!_isInitialized) {
      throw StateError(
          'NetworkCredentialsService has not been initialized yet');
    }
  }
}
