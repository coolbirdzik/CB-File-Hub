import 'dart:io';

import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/helpers/media/thumbnail_helper.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;
import 'package:flutter/services.dart';
import '../../components/video/video_player/video_player.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import '../../utils/format_utils.dart';

class FileDetailsScreen extends StatefulWidget {
  final File file;

  /// Tab index to show initially (0 = default details tab)
  final int initialTab;

  const FileDetailsScreen({
    Key? key,
    required this.file,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<FileDetailsScreen> createState() => _FileDetailsScreenState();
}

class _FileDetailsScreenState extends State<FileDetailsScreen> {
  late Future<FileStat> _fileStatFuture;
  bool _videoPlayerReady = false;
  bool _inAndroidPip = false;

  @override
  void initState() {
    super.initState();
    _fileStatFuture = widget.file.stat();
    // Listen PiP changes to hide BaseScreen AppBar when in PiP
    const channel = MethodChannel('cb_file_manager/pip');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        final args = call.arguments;
        bool inPip = false;
        if (args is Map) {
          inPip = args['inPip'] == true;
        }
        if (mounted) {
          setState(() => _inAndroidPip = inPip);
        }
      }
    });

    // Set initial tab if specified
    if (widget.initialTab > 0) {
      // We'll switch to the specified tab after the build is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // For now, just scroll to the Tags section if initialTab = 1
        if (widget.initialTab == 1) {
          // Find a simpler way to scroll to the Tags section
          final scrollController = PrimaryScrollController.of(context);
          // Scroll to the estimated position of the Tags section (value based on UI height)
          scrollController.animateTo(
            500, // Estimated position of the Tags section
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final bool isImage = FileTypeUtils.isImageFile(widget.file.path);
    final bool isVideo = FileTypeUtils.isVideoFile(widget.file.path);
    final bool isAudio = FileTypeUtils.isAudioFile(widget.file.path);

    final theme = Theme.of(context);
    final Color bgColor = theme.colorScheme.surface;
    final Color cardColor = theme.cardColor;
    final Color textColor = theme.colorScheme.onSurface;
    final Color secondaryTextColor = theme.colorScheme.onSurfaceVariant;

    return BaseScreen(
      title: _inAndroidPip ? '' : localizations.properties,
      showAppBar: !_inAndroidPip,
      actions: [
        if (!_inAndroidPip)
          IconButton(
            icon: const Icon(PhosphorIconsLight.arrowSquareOut),
            tooltip: localizations.openWith,
            onPressed: () {
              _showOpenWithDialog();
            },
          ),
        if (!_inAndroidPip)
          IconButton(
            icon: const Icon(PhosphorIconsLight.shareFat),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localizations.operationFailed),
                ),
              );
            },
          ),
      ],
      // When in PiP, avoid extra paddings/margins that could be captured.
      body: Container(
        color: bgColor,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File preview section with hero animation
              if (isImage || isVideo || isAudio)
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                  ),
                  child: Column(
                    children: [
                      if (isImage) _buildImagePreview(),
                      if (isVideo) _buildVideoPreview(),
                      if (isAudio) _buildAudioPreview(),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Basic file info card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeaderSection(),
                        const SizedBox(height: 16),
                        _buildFileDetails(textColor, secondaryTextColor),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Tags section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              PhosphorIconsLight.bookmark,
                              color: textColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              localizations.tags,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Use the common tag management component
                        TagManagementSection(
                          filePath: widget.file.path,
                          showFileTagsHeader: false,
                          onTagsUpdated: () {
                            // Optional callback if needed
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Actions section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(PhosphorIconsLight.arrowSquareOut,
                              color: textColor),
                          title: Text(localizations.openWith,
                              style: TextStyle(color: textColor)),
                          onTap: () => _showOpenWithDialog(),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(PhosphorIconsLight.squaresFour,
                              color: textColor),
                          title: Text(localizations.chooseDefaultApp,
                              style: TextStyle(color: textColor)),
                          onTap: () => _showOpenWithDialog(
                            saveAsDefaultOnSelect: true,
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(PhosphorIconsLight.fileText,
                              color: textColor),
                          title: Text(localizations.createCopy,
                              style: TextStyle(color: textColor)),
                          onTap: () {
                            // Make a copy functionality
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(localizations.operationFailed)),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(PhosphorIconsLight.trash,
                              color: theme.colorScheme.error),
                          title: Text(localizations.deleteFile,
                              style: TextStyle(color: theme.colorScheme.error)),
                          onTap: () {
                            // Delete functionality
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(localizations.operationFailed)),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    final theme = Theme.of(context);
    final Color textColor = theme.colorScheme.onSurface;

    IconData fileIcon;
    Color iconColor;

    // Set icon based on file type using FileTypeUtils
    if (FileTypeUtils.isImageFile(widget.file.path)) {
      fileIcon = PhosphorIconsLight.image;
      iconColor = theme.colorScheme.primary;
    } else if (FileTypeUtils.isVideoFile(widget.file.path)) {
      fileIcon = PhosphorIconsLight.videoCamera;
      iconColor = theme.colorScheme.error;
    } else if (FileTypeUtils.isAudioFile(widget.file.path)) {
      fileIcon = PhosphorIconsLight.musicNotes;
      iconColor = theme.colorScheme.tertiary;
    } else if (FileTypeUtils.isDocumentFile(widget.file.path)) {
      fileIcon = PhosphorIconsLight.fileText;
      iconColor = theme.colorScheme.primary;
    } else if (FileTypeUtils.isSpreadsheetFile(widget.file.path)) {
      fileIcon = PhosphorIconsLight.squaresFour;
      iconColor = theme.colorScheme.tertiary;
    } else {
      fileIcon = PhosphorIconsLight.file;
      iconColor = theme.colorScheme.onSurfaceVariant;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            fileIcon,
            size: 28,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pathlib.basename(widget.file.path),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.file.extension().toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    final localizations = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.black,
      child: Hero(
        tag: widget.file.path,
        child: Image.file(
          widget.file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(PhosphorIconsLight.imageBroken,
                      size: 64, color: Colors.white54),
                  const SizedBox(height: 16),
                  Text(
                    localizations.errorLoadingImage,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    final localizations = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Show thumbnail first
          if (!_videoPlayerReady)
            Hero(
              tag: widget.file.path,
              child: ThumbnailHelper.buildVideoThumbnail(
                videoPath: widget.file.path,
                width: double.infinity,
                height: 300,
                isVisible: true,
                onThumbnailGenerated: (_) {},
                fallbackBuilder: () => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(PhosphorIconsLight.videoCamera,
                          size: 64, color: Colors.white54),
                      const SizedBox(height: 8),
                      Text(
                        localizations.loadingVideo,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Video player with opacity animation based on ready state
          AnimatedOpacity(
            opacity: _videoPlayerReady ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: VideoPlayer.file(
              file: widget.file,
              showControls: true,
              allowFullScreen: true,
              allowMuting: true,
              onInitialized: () {
                setState(() {
                  _videoPlayerReady = true;
                });
              },
              onError: (errorMessage) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('${localizations.operationFailed}: $errorMessage'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPreview() {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIconsLight.musicNotes,
                size: 64, color: theme.colorScheme.tertiary),
          ),
          const SizedBox(height: 16),
          Text(
            pathlib.basename(widget.file.path),
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(PhosphorIconsLight.skipBack,
                    color: Colors.white),
                iconSize: 36,
                onPressed: () {},
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizations.operationFailed),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                  backgroundColor: theme.colorScheme.tertiary,
                ),
                child: const Icon(PhosphorIconsLight.play, size: 32),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(PhosphorIconsLight.skipForward,
                    color: Colors.white),
                iconSize: 36,
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileDetails(Color textColor, Color secondaryTextColor) {
    final localizations = AppLocalizations.of(context)!;
    return FutureBuilder<FileStat>(
      future: _fileStatFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Center(
            child: Text(
              localizations.operationFailed,
              style: TextStyle(color: textColor),
            ),
          );
        }

        final stat = snapshot.data!;
        final fileSize = FormatUtils.formatFileSizeExact(stat.size);
        final formattedDate = stat.modified.toString().split('.')[0];

        return Column(
          children: [
            _buildDetailRow(localizations.fileSize, fileSize,
                PhosphorIconsLight.hardDrives, textColor, secondaryTextColor),
            const Divider(height: 24),
            _buildDetailRow(
                localizations.fileLocation,
                pathlib.dirname(widget.file.path),
                PhosphorIconsLight.folder,
                textColor,
                secondaryTextColor),
            const Divider(height: 24),
            _buildDetailRow(
                localizations.fileCreated,
                stat.changed.toString().split('.')[0],
                PhosphorIconsLight.calendarBlank,
                textColor,
                secondaryTextColor),
            const Divider(height: 24),
            _buildDetailRow(localizations.fileModified, formattedDate,
                PhosphorIconsLight.pencilSimple, textColor, secondaryTextColor),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon,
      Color textColor, Color secondaryTextColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: secondaryTextColor),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                color: textColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showOpenWithDialog({bool saveAsDefaultOnSelect = false}) {
    showDialog(
      context: context,
      builder: (context) => OpenWithDialog(
        filePath: widget.file.path,
        saveAsDefaultOnSelect: saveAsDefaultOnSelect,
      ),
    );
  }
}
