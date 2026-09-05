import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/ui/widgets/resizable_dialog.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/helpers/files/windows_app_icon.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'dart:async';

import 'package:cb_file_manager/ui/utils/video_playback_launcher.dart';
import 'package:cb_file_manager/ui/controllers/archive_navigation.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';

class OpenWithDialog extends StatefulWidget {
  final String filePath;
  final bool saveAsDefaultOnSelect;

  const OpenWithDialog({
    super.key,
    required this.filePath,
    this.saveAsDefaultOnSelect = false,
  });

  @override
  State<OpenWithDialog> createState() => _OpenWithDialogState();
}

class _OpenWithDialogState extends State<OpenWithDialog> {
  late Future<List<AppInfo>> _appsFuture;
  late bool _saveAsDefault;
  bool _opening = false;
  AppInfo? _selectedApp;
  AppInfo? _customApp;

  @override
  void initState() {
    super.initState();
    _saveAsDefault = widget.saveAsDefaultOnSelect;
    _appsFuture = ExternalAppHelper.getInstalledAppsForFile(widget.filePath);
  }

  Future<void> _saveVideoDefaultIfNeeded(String appIdentifier) async {
    if (!_saveAsDefault) return;
    if (!FileTypeUtils.isVideoFile(widget.filePath)) return;

    final prefs = UserPreferences.instance;
    await prefs.init();

    if (appIdentifier == '__cb_video_player__') {
      await _selectBuiltInVideoPlayerAsDefault(prefs);
      return;
    }

    if (appIdentifier == 'shell_open') {
      await prefs.clearPreferredVideoPlayerApp();
      await prefs.setUseSystemDefaultForVideo(true);
      return;
    }

    await prefs.setPreferredVideoPlayerApp(appIdentifier);
    await prefs.setUseSystemDefaultForVideo(false);
  }

  Future<void> _selectBuiltInVideoPlayerAsDefault(UserPreferences prefs) async {
    await prefs.clearPreferredVideoPlayerApp();
    await prefs.setUseSystemDefaultForVideo(false);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await prefs.setOpenVideoInNewWindow(true);
    }
  }

  Future<void> _openSelectedApp() async {
    final app = _selectedApp;
    if (app == null || _opening) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final toast = AppToast.capture(context);
    final errorLabel = AppLocalizations.of(context)!.errorTitle;
    setState(() => _opening = true);
    try {
      await _saveVideoDefaultIfNeeded(app.packageName);
      if (!mounted) return;
      if (app.packageName == '__cb_archive_browse__') {
        ArchiveNavigation.openBrowse(context, archiveFilePath: widget.filePath);
        navigator.pop();
        return;
      }
      navigator.pop();
      if (app.packageName == '__cb_video_player__') {
        await VideoPlaybackLauncher.open(
          navigator.context,
          file: File(widget.filePath),
        );
      } else if (app.packageName == 'shell_open') {
        await ExternalAppHelper.openWithSystemDefault(widget.filePath);
      } else {
        await ExternalAppHelper.openFileWithApp(
          widget.filePath,
          app.packageName,
        );
      }
    } catch (_) {
      toast.info(errorLabel);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _chooseAnotherApp() async {
    if (_opening) return;
    if (Platform.isWindows) {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['exe'],
        dialogTitle: AppLocalizations.of(context)!.chooseAnotherApp,
      );
      if (!mounted || picked?.path == null) return;
      final appPath = picked!.path!;
      setState(() {
        _customApp = AppInfo(
          packageName: appPath,
          appName: path.basenameWithoutExtension(appPath),
          icon: const Icon(PhosphorIconsLight.appWindow, size: 32),
        );
        _selectedApp = _customApp;
      });
    } else if (Platform.isAndroid) {
      Navigator.pop(context);
      await ExternalAppHelper.openWithSystemChooser(widget.filePath);
    }
  }

  Future<void> _setVideoSystemDefault() async {
    // Pre-extract context-dependent values before async gap
    final toast = AppToast.capture(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (Platform.isWindows) {
      final exe = Platform.resolvedExecutable;
      final ok = await WindowsAppIcon.setSelfAsDefaultForVideo(exe);
      if (ok) {
        final prefs = UserPreferences.instance;
        await prefs.init();
        await _selectBuiltInVideoPlayerAsDefault(prefs);
      }
      try {
        toast.info(
          ok
              ? 'CB File Hub is now the default for video files.'
              : 'Could not set as default.',
        );
        navigator.pop();
      } catch (_) {}
    } else if (Platform.isAndroid) {
      await ExternalAppHelper.openDefaultAppSettings();
      try {
        toast.info(l10n.setCoolBirdAsDefaultForVideosAndroidHint);
        navigator.pop();
      } catch (_) {}
    }
  }

  Future<void> _setArchiveSystemDefault() async {
    // Pre-extract context-dependent values before
    // any async gap so we don't use BuildContext
    // across await boundaries.
    final toast = AppToast.capture(context);
    final navigator = Navigator.of(context);
    final archivesSuccessL10n = AppLocalizations.of(
      context,
    )!.setCoolBirdAsDefaultForArchivesSuccess;
    final archivesFailedL10n = AppLocalizations.of(
      context,
    )!.setCoolBirdAsDefaultForArchivesFailed;
    final exe = Platform.resolvedExecutable;
    final ok = await WindowsAppIcon.setSelfAsDefaultForArchives(exe);
    try {
      toast.info(ok ? archivesSuccessL10n : archivesFailedL10n);
      navigator.pop();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isVideo = FileTypeUtils.isVideoFile(widget.filePath);
    final canChooseApp = Platform.isWindows || Platform.isAndroid;

    return ResizableDialog(
      prefsKeyPrefix: 'open_with_dialog',
      initialSizeFactor: const Size(0.5, 0.75),
      minSize: const Size(460, 420),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.openWith,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.24,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.file,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: widget.filePath,
                    child: Text(
                      widget.filePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      contentBuilder: (context, dialogSize) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.32,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FutureBuilder<List<AppInfo>>(
                      future: _appsFuture,
                      builder: (context, snapshot) {
                        final apps = snapshot.data ?? <AppInfo>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (snapshot.connectionState ==
                                ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (snapshot.hasError || apps.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(
                                  snapshot.hasError
                                      ? l10n.applicationsLoadError
                                      : l10n.noApplicationsFound,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            else
                              for (final app in apps) ...[
                                _buildAppRow(app),
                                const SizedBox(height: 4),
                              ],
                            if (_customApp != null &&
                                !apps.any(
                                  (app) =>
                                      app.packageName ==
                                      _customApp!.packageName,
                                ))
                              _buildAppRow(_customApp!),
                            if (canChooseApp) ...[
                              const SizedBox(height: 8),
                              _buildActionRow(
                                icon: PhosphorIconsLight.folderOpen,
                                label: l10n.chooseAnotherApp,
                                onPressed: _chooseAnotherApp,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    if ((canChooseApp && isVideo) ||
                        (Platform.isWindows &&
                            FileTypeUtils.isArchiveFile(widget.filePath))) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      _buildActionRow(
                        icon: isVideo
                            ? PhosphorIconsLight.videoCamera
                            : PhosphorIconsLight.archive,
                        label: isVideo
                            ? l10n.setCoolBirdAsDefaultForVideos
                            : l10n.setCoolBirdAsDefaultForArchives,
                        onPressed: isVideo
                            ? _setVideoSystemDefault
                            : _setArchiveSystemDefault,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isVideo) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const ValueKey('open-with-default'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                l10n.useSelectedAppAsVideoDefault,
                style: const TextStyle(fontSize: 14),
              ),
              value: _saveAsDefault,
              onChanged: _opening
                  ? null
                  : (value) => setState(() => _saveAsDefault = value ?? false),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _opening ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(l10n.cancel.toUpperCase()),
        ),
        ElevatedButton(
          key: const ValueKey('open-with-confirm'),
          onPressed: _opening || _selectedApp == null ? null : _openSelectedApp,
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _opening
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.open.toUpperCase()),
        ),
      ],
    );
  }

  Widget _buildAppRow(AppInfo app) {
    final selected = _selectedApp?.packageName == app.packageName;
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('open-with-app-${app.packageName}'),
          borderRadius: BorderRadius.circular(12),
          onTap: _opening ? null : () => setState(() => _selectedApp = app),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                SizedBox(width: 36, height: 36, child: Center(child: app.icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    app.appName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 20,
                  child: selected
                      ? Icon(
                          PhosphorIconsLight.check,
                          size: 20,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _opening ? null : onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          ],
        ),
      ),
    );
  }
}
