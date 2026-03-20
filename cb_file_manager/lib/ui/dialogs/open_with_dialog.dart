import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/helpers/files/windows_app_icon.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/video_player_full_screen.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';

class OpenWithDialog extends StatefulWidget {
  final String filePath;
  final bool saveAsDefaultOnSelect;

  const OpenWithDialog({
    Key? key,
    required this.filePath,
    this.saveAsDefaultOnSelect = false,
  }) : super(key: key);

  @override
  State<OpenWithDialog> createState() => _OpenWithDialogState();
}

class _OpenWithDialogState extends State<OpenWithDialog> {
  late Future<List<AppInfo>> _appsFuture;
  bool _loadingIcons = false;

  @override
  void initState() {
    super.initState();
    _appsFuture = ExternalAppHelper.getInstalledAppsForFile(widget.filePath);
  }

  Future<void> _saveVideoDefaultIfNeeded(String appIdentifier) async {
    if (!widget.saveAsDefaultOnSelect) return;
    if (!FileTypeUtils.isVideoFile(widget.filePath)) return;

    final prefs = UserPreferences.instance;
    await prefs.init();

    if (appIdentifier == '__cb_video_player__') {
      await prefs.clearPreferredVideoPlayerApp();
      await prefs.setUseSystemDefaultForVideo(false);
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    final isNarrow = screen.width < 500;
    final dialogWidth =
        isNarrow ? (screen.width * 0.92).clamp(280.0, 400.0) : 420.0;
    final listMaxH = (screen.height * 0.48).clamp(320.0, 560.0);

    return Dialog(
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIconsLight.arrowSquareOut,
                    color: isDarkMode ? Colors.white70 : Colors.black87),
                const SizedBox(width: 8),
                Text(
                  'Open with',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                if (_loadingIcons) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDarkMode ? Colors.white70 : Colors.blue,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<AppInfo>>(
              future: _appsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Error loading applications',
                        style: TextStyle(
                          color: isDarkMode ? Colors.red[300] : Colors.red,
                        ),
                      ),
                    ),
                  );
                }

                final apps = snapshot.data ?? [];

                if (apps.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'No applications found for this file type',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return Container(
                  constraints: BoxConstraints(maxHeight: listMaxH),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: apps.length,
                          itemBuilder: (context, index) {
                            final app = apps[index];
                            return ListTile(
                              leading: app.icon,
                              title: Text(app.appName),
                              onTap: () async {
                                final rootNavigator =
                                    Navigator.of(context, rootNavigator: true);
                                setState(() {
                                  _loadingIcons = true;
                                });

                                await _saveVideoDefaultIfNeeded(
                                    app.packageName);

                                if (!mounted) return;
                                rootNavigator.pop();

                                if (app.packageName == '__cb_video_player__') {
                                  rootNavigator.push(
                                    MaterialPageRoute(
                                      fullscreenDialog: true,
                                      builder: (_) => VideoPlayerFullScreen(
                                          file: File(widget.filePath)),
                                    ),
                                  );
                                } else if (app.packageName == 'shell_open') {
                                  await ExternalAppHelper.openWithSystemDefault(
                                      widget.filePath);
                                } else {
                                  await ExternalAppHelper.openFileWithApp(
                                      widget.filePath, app.packageName);
                                }

                                if (mounted) {
                                  setState(() {
                                    _loadingIcons = false;
                                  });
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const Divider(),
                      if ((Platform.isWindows || Platform.isAndroid) &&
                          FileTypeUtils.isVideoFile(widget.filePath))
                        ListTile(
                          leading: const Icon(PhosphorIconsLight.videoCamera),
                          title: Text(
                            AppLocalizations.of(context)!
                                .setCoolBirdAsDefaultForVideos,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDarkMode
                                  ? Colors.blue[200]
                                  : Colors.blue[700],
                            ),
                          ),
                          onTap: () async {
                            if (Platform.isWindows) {
                              final exe = Platform.resolvedExecutable;
                              final ok =
                                  await WindowsAppIcon.setSelfAsDefaultForVideo(
                                      exe);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'CB File Hub is now the default for video files.'
                                        : 'Could not set as default.'),
                                  ),
                                );
                                Navigator.pop(context);
                              }
                            } else if (Platform.isAndroid) {
                              await ExternalAppHelper.openDefaultAppSettings();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!
                                        .setCoolBirdAsDefaultForVideosAndroidHint),
                                  ),
                                );
                                Navigator.pop(context);
                              }
                            }
                          },
                        ),
                      if ((Platform.isWindows || Platform.isAndroid) &&
                          FileTypeUtils.isVideoFile(widget.filePath))
                        const Divider(),
                      ListTile(
                        leading: const Icon(PhosphorIconsLight.dotsThree),
                        title: Text(
                            AppLocalizations.of(context)!.chooseAnotherApp),
                        onTap: () async {
                          // Close the dialog
                          Navigator.pop(context);

                          // Use file_picker to select an executable
                          if (Platform.isWindows) {
                            FilePickerResult? result =
                                await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['exe'],
                              dialogTitle:
                                  'Select an application to open this file',
                            );

                            if (result != null &&
                                result.files.single.path != null) {
                              final appPath = result.files.single.path!;
                              await _saveVideoDefaultIfNeeded(appPath);
                              await ExternalAppHelper.openFileWithApp(
                                  widget.filePath, appPath);
                            }
                          } else if (Platform.isAndroid) {
                            // On Android, we can use the system's app chooser
                            await ExternalAppHelper.openWithSystemChooser(
                                widget.filePath);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
