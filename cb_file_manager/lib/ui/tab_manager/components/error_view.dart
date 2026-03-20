import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';

/// Component to display error messages with appropriate styling and actions
class ErrorView extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onGoBack;
  final bool isNetworkPath;

  const ErrorView({
    Key? key,
    required this.errorMessage,
    required this.onRetry,
    required this.onGoBack,
    this.isNetworkPath = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isNetworkPath
                ? PhosphorIconsLight.wifiX
                : PhosphorIconsLight.warningCircle,
            size: 72,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onGoBack,
                child: Text(isNetworkPath ? l10n.closeConnection : l10n.goBack),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(isNetworkPath ? l10n.tryAgain : l10n.retry),
              ),
            ],
          ),
          if (isNetworkPath) ...[
            const SizedBox(height: 16),
            Text(
              l10n.networkErrorPersistsHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
