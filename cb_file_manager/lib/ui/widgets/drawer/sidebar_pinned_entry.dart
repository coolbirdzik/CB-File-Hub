import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/filesystem/macos_user_folders_service.dart';

/// Shared labels and icons for the Material and Fluent sidebar renderers.
class SidebarPinnedEntry {
  final String path;
  final String title;
  final IconData icon;

  const SidebarPinnedEntry({
    required this.path,
    required this.title,
    required this.icon,
  });

  factory SidebarPinnedEntry.fromPath(
    String path, {
    required AppLocalizations l10n,
    required List<MacosUserFolder> userFolders,
  }) {
    final folder = userFolders
        .where(
          (folder) => p.posix.normalize(folder.path) == p.posix.normalize(path),
        )
        .firstOrNull;
    final name = _basename(path);
    final (title, icon) = switch (folder?.kind) {
      MacosUserFolderKind.applications => (
        l10n.sidebarApplications,
        PhosphorIconsLight.squaresFour,
      ),
      MacosUserFolderKind.desktop => (
        l10n.sidebarDesktop,
        PhosphorIconsLight.desktop,
      ),
      MacosUserFolderKind.documents => (
        l10n.documentsTab,
        PhosphorIconsLight.fileText,
      ),
      MacosUserFolderKind.downloads => (
        l10n.downloads,
        PhosphorIconsLight.downloadSimple,
      ),
      MacosUserFolderKind.home => (name, PhosphorIconsLight.house),
      MacosUserFolderKind.pictures => (
        l10n.sidebarPictures,
        PhosphorIconsLight.image,
      ),
      MacosUserFolderKind.music => (
        l10n.sidebarMusic,
        PhosphorIconsLight.musicNotes,
      ),
      MacosUserFolderKind.movies => (
        l10n.sidebarMovies,
        PhosphorIconsLight.filmStrip,
      ),
      null => (name, _fallbackIcon(path)),
    };
    return SidebarPinnedEntry(path: path, title: title, icon: icon);
  }

  /// Windows accepts both separators, so pins such as `/work/x` or a path
  /// with a trailing `\` still show their last segment.
  static String _basename(String path) {
    final separators = Platform.isWindows ? RegExp(r'[\\/]') : RegExp('/');
    final parts = path.split(separators).where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  static IconData _fallbackIcon(String path) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: false) ==
              FileSystemEntityType.file
          ? PhosphorIconsLight.file
          : PhosphorIconsLight.folder;
    } on FileSystemException {
      return PhosphorIconsLight.pushPin;
    }
  }
}
