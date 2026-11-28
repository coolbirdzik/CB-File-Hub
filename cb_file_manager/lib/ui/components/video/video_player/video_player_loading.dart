import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';

/// Error state widget for video player with retry action.
class VideoPlayerErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const VideoPlayerErrorWidget({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            PhosphorIconsLight.warningCircle,
            color: Colors.red,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Error playing media',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context)!.retry),
          ),
        ],
      ),
    );
  }
}

/// Loading state widget for the player using the shared loading text treatment.
class VideoPlayerLoadingWidget extends StatelessWidget {
  final String loadingMessage;
  final String fileName;

  const VideoPlayerLoadingWidget({
    super.key,
    required this.loadingMessage,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CbLoadingText(
          text: loadingMessage,
          style: CbTypography.body,
          highlightColor: Colors.white,
          maxLines: 2,
        ),
        const SizedBox(height: CbSpacing.sm),
        Text(
          fileName,
          style: CbTypography.bodySm.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

/// media_kit-specific placeholder shown while the player is initializing.
class VideoPlayerPlaceholder extends StatelessWidget {
  const VideoPlayerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: CbLoadingText(
        text: AppLocalizations.of(context)?.loadingVideo,
        highlightColor: Colors.white,
      ),
    ),
  );
}
