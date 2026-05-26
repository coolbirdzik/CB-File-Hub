import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../bloc/ai_agent/ai_agent_state.dart';

/// Debug dialog showing the raw API payload last sent to the provider.
///
/// Used by the "View raw payload" button next to the context badge in the
/// AI chat header.
class RawPayloadDialog extends StatelessWidget {
  final AiAgentState state;

  const RawPayloadDialog({Key? key, required this.state}) : super(key: key);

  static Future<void> show(BuildContext context, AiAgentState state) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: RawPayloadDialog(state: state),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = state.lastApiPayload;
    final pretty = payload == null
        ? 'No payload captured yet. Send a message first to see the request.'
        : const JsonEncoder.withIndent('  ').convert(payload);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsLight.code,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Raw API payload',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(PhosphorIconsLight.copy, size: 18),
                tooltip: 'Copy JSON',
                onPressed: payload == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: pretty));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
              ),
              IconButton(
                icon: const Icon(PhosphorIconsLight.x, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (payload != null) ...[
            const SizedBox(height: 8),
            Text(
              '${payload['providerId']} · ${payload['modelName']} · '
              '${payload['stream'] == true ? 'streaming' : 'non-streaming'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: SelectableText(
                    pretty,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
