import 'dart:io';

import 'package:flutter/material.dart';

/// A backup archive stored on a remote cloud drive.
class CloudBackupFile {
  const CloudBackupFile({
    required this.id,
    required this.name,
    this.size,
    this.modified,
  });

  /// Provider specific handle (Drive/Graph item id, Dropbox path).
  final String id;
  final String name;
  final int? size;
  final DateTime? modified;
}

/// The signed-in account of a cloud provider.
class CloudAccount {
  const CloudAccount({required this.displayName, this.email});

  final String displayName;
  final String? email;

  String get label => email == null || email!.isEmpty
      ? displayName
      : (displayName.isEmpty ? email! : '$displayName ($email)');

  Map<String, dynamic> toJson() => {'displayName': displayName, 'email': email};

  factory CloudAccount.fromJson(Map<String, dynamic> json) => CloudAccount(
    displayName: (json['displayName'] as String?) ?? '',
    email: json['email'] as String?,
  );
}

/// Raised when a cloud call fails in a way worth showing to the user.
class CloudBackupException implements Exception {
  CloudBackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A cloud drive CB File Hub can push backup archives to.
abstract class CloudBackupProvider {
  /// Stable id persisted in preferences (`google_drive`, `dropbox`, ...).
  String get id;

  String get displayName;

  IconData get icon;

  /// False when the build has no OAuth client id compiled in for this
  /// provider, in which case the UI offers it as unavailable.
  bool get isConfigured;

  /// Folder the archives live in, shown in the UI so users can find them.
  String get remoteFolderName;

  /// Account cached from a previous session, or null when not connected.
  Future<CloudAccount?> currentAccount();

  /// Runs the interactive OAuth flow and stores the tokens.
  Future<CloudAccount> connect();

  /// Drops the stored tokens for this provider.
  Future<void> disconnect();

  Future<CloudBackupFile> upload({required File file, required String name});

  /// Newest first.
  Future<List<CloudBackupFile>> listBackups();

  /// Downloads [remote] to [destinationPath] and returns the local file.
  Future<File> download(CloudBackupFile remote, String destinationPath);

  Future<void> delete(CloudBackupFile remote);
}
