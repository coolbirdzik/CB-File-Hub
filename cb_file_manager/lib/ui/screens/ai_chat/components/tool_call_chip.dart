import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../models/ai/ai_message.dart';

/// Collapsible chip rendering a single [AiToolCall] in the chat stream.
///
/// Collapsed view: small pill with tool name + success/failure icon.
/// Expanded view: shows arguments (JSON) + raw tool output.
class ToolCallChip extends StatefulWidget {
  final AiToolCall toolCall;

  const ToolCallChip({Key? key, required this.toolCall}) : super(key: key);

  @override
  State<ToolCallChip> createState() => _ToolCallChipState();
}

class _ToolCallChipState extends State<ToolCallChip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = widget.toolCall;
    final isSuccess = call.success;
    final accent = isSuccess
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (always visible)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isSuccess
                        ? PhosphorIconsLight.checkCircle
                        : PhosphorIconsLight.xCircle,
                    size: 14,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    PhosphorIconsLight.wrench,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      call.toolName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? PhosphorIconsLight.caretUp
                        : PhosphorIconsLight.caretDown,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // Expanded details
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (call.arguments.isNotEmpty &&
                      call.arguments != '{}') ...[
                    Text(
                      'Arguments',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        _prettifyJson(call.arguments),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (call.result != null && call.result!.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'Result',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            isSuccess ? 'OK' : 'FAILED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 240),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          call.result!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _prettifyJson(String raw) {
    try {
      final decoded = json.decode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }
}
