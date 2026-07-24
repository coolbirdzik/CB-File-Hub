import 'dart:io';
import 'dart:typed_data';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/app_path_helper.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Opens a modal that lets the user crop [imagePath] before it is used as a
/// thumbnail.
///
/// The cropped result is written as a fresh JPEG into the persistent tag
/// thumbnail directory and its path is returned. Returns `null` if the user
/// cancels, or [imagePath] unchanged if the user chooses to skip cropping.
///
/// This is the app-wide entry point for "crop an image before using it"; it is
/// used by [showThumbnailBrowserDialog] right after a still image or an
/// extracted video frame has been picked.
Future<String?> showImageCropDialog(
  BuildContext context,
  String imagePath, {
  String? title,
  double? aspectRatio,
}) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    return imagePath;
  }

  final bytes = await file.readAsBytes();
  if (!context.mounted) {
    return null;
  }

  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImageCropDialog(
      imageBytes: bytes,
      sourcePath: imagePath,
      title: title,
      aspectRatio: aspectRatio,
    ),
  );
}

class _ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String sourcePath;
  final String? title;
  final double? aspectRatio;

  const _ImageCropDialog({
    required this.imageBytes,
    required this.sourcePath,
    this.title,
    this.aspectRatio,
  });

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  final CropController _controller = CropController();
  bool _isCropping = false;
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _aspectRatio = widget.aspectRatio;
  }

  void _startCrop() {
    if (_isCropping) return;
    setState(() => _isCropping = true);
    _controller.crop();
  }

  Future<void> _handleCropped(CropResult result) async {
    if (result is CropSuccess) {
      await _saveAndReturn(result.croppedImage);
    } else if (result is CropFailure) {
      AppLogger.error('[ImageCrop] Crop failed', error: result.cause);
      if (mounted) {
        setState(() => _isCropping = false);
      }
    }
  }

  Future<void> _saveAndReturn(Uint8List croppedBytes) async {
    try {
      final dir = await AppPathHelper.getTagThumbnailDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = p.join(dir.path, 'thumb_crop_$timestamp.jpg');

      // Re-encode to JPEG for a consistent, compact thumbnail format.
      final decoded = img.decodeImage(croppedBytes);
      final file = File(outputPath);
      if (decoded != null) {
        final jpeg = img.encodeJpg(decoded, quality: 95);
        await file.writeAsBytes(jpeg);
      } else {
        await file.writeAsBytes(croppedBytes);
      }

      if (await file.exists() && await file.length() > 0 && mounted) {
        Navigator.of(context).pop(outputPath);
      } else if (mounted) {
        setState(() => _isCropping = false);
      }
    } catch (e) {
      AppLogger.error('[ImageCrop] Failed to save cropped image', error: e);
      if (mounted) {
        setState(() => _isCropping = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.7).clamp(360.0, 900.0);
    final cropHeight = (screenSize.height * 0.6).clamp(280.0, 620.0);

    return Dialog(
      child: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.crop,
                      size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title ?? l10n.cropImage,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsLight.x, size: 20),
                    onPressed: _isCropping
                        ? null
                        : () => Navigator.of(context).pop(null),
                    tooltip: l10n.cancel,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Crop area
            SizedBox(
              height: cropHeight,
              child: Crop(
                image: widget.imageBytes,
                controller: _controller,
                aspectRatio: _aspectRatio,
                baseColor: theme.colorScheme.surfaceContainerHighest,
                maskColor: Colors.black.withValues(alpha: 0.5),
                cornerDotBuilder: (size, edgeAlignment) =>
                    DotControl(color: theme.colorScheme.primary),
                progressIndicator: const CircularProgressIndicator(),
                onCropped: _handleCropped,
              ),
            ),

            const Divider(height: 1),

            // Aspect ratio presets
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          PhosphorIconsLight.info,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.tagGridCropRecommendation,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ratioChip(l10n.aspectFree, null),
                      _ratioChip('1:1', 1),
                      _ratioChip('4:3', 4 / 3),
                      _ratioChip(l10n.tagGridAspectPreset, 16 / 9),
                      _ratioChip('3:4', 3 / 4),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isCropping
                        ? null
                        : () => Navigator.of(context).pop(null),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isCropping
                        ? null
                        : () => Navigator.of(context).pop(widget.sourcePath),
                    child: Text(l10n.useOriginal),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isCropping ? null : _startCrop,
                    icon: _isCropping
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(PhosphorIconsLight.check, size: 18),
                    label: Text(l10n.applyCrop),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratioChip(String label, double? ratio) {
    final selected = _aspectRatio == ratio;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _isCropping
          ? null
          : (_) {
              setState(() {
                _aspectRatio = ratio;
                _controller.aspectRatio = ratio;
              });
            },
    );
  }
}
