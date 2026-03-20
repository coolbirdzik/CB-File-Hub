import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../utils/route.dart';

/// Widget to display images from streaming URL or file stream.
class StreamingImageViewer extends StatefulWidget {
  final String? streamingUrl;
  final Stream<List<int>>? fileStream;
  final String fileName;
  final VoidCallback? onClose;

  const StreamingImageViewer({
    Key? key,
    this.streamingUrl,
    this.fileStream,
    required this.fileName,
    this.onClose,
  })  : assert(
          streamingUrl != null || fileStream != null,
          'Either streamingUrl or fileStream must be provided',
        ),
        super(key: key);

  /// Constructor for streaming URL
  const StreamingImageViewer.fromUrl({
    Key? key,
    required String streamingUrl,
    required String fileName,
    VoidCallback? onClose,
  }) : this(
          key: key,
          streamingUrl: streamingUrl,
          fileName: fileName,
          onClose: onClose,
        );

  /// Constructor for file stream
  const StreamingImageViewer.fromStream({
    Key? key,
    required Stream<List<int>> fileStream,
    required String fileName,
    VoidCallback? onClose,
  }) : this(
          key: key,
          fileStream: fileStream,
          fileName: fileName,
          onClose: onClose,
        );

  @override
  State<StreamingImageViewer> createState() => _StreamingImageViewerState();
}

class _StreamingImageViewerState extends State<StreamingImageViewer> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _isUrlNotImplemented = false;
  Uint8List? _imageData;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isUrlNotImplemented = false;
      });

      if (widget.streamingUrl != null) {
        await _loadFromUrl();
      } else if (widget.fileStream != null) {
        await _loadFromStream();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isUrlNotImplemented = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFromUrl() async {
    // Implementation for loading from URL would go here
    // For now, just show an error
    setState(() {
      _errorMessage = null;
      _isUrlNotImplemented = true;
      _isLoading = false;
    });
  }

  Future<void> _loadFromStream() async {
    final chunks = <int>[];
    await for (final chunk in widget.fileStream!) {
      chunks.addAll(chunk);
    }

    if (mounted) {
      setState(() {
        _imageData = Uint8List.fromList(chunks);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        title: Text(
          widget.fileName,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsLight.x),
            onPressed:
                widget.onClose ?? () => RouteUtils.safePopDialog(context),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null || _isUrlNotImplemented) {
      final bodyText = _isUrlNotImplemented
          ? l10n.urlLoadingNotImplemented
          : l10n.errorLoadingImageWithError(_errorMessage ?? '');

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(PhosphorIconsLight.warningCircle,
                color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.errorLoadingImage,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                bodyText,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadImage,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (_imageData != null) {
      return Center(
        child: InteractiveViewer(
          child: Image.memory(
            _imageData!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(PhosphorIconsLight.imageBroken,
                        color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      l10n.failedToDisplayImage,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    return Center(
      child: Text(
        l10n.noImageDataAvailable,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}
