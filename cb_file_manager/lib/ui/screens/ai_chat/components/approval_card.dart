import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../services/ai/ai_approval.dart';

/// Shared approval card shown above the chat input when the AI agent requests
/// user confirmation before executing a dangerous or file-modifying action.
///
/// Used by both [AiChatScreen] (full-screen tab) and [AiSidePanel].
class ApprovalCard extends StatelessWidget {
  final AiApprovalRequest approval;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const ApprovalCard({
    Key? key,
    required this.approval,
    required this.onApprove,
    required this.onReject,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDangerous = approval.isDangerous;

    final IconData actionIcon;
    final Color accentColor;
    switch (approval.actionType) {
      case ApprovalActionType.execute:
        actionIcon = PhosphorIconsLight.terminal;
        accentColor = const Color(0xFFB45309); // amber-700
        break;
      case ApprovalActionType.createFile:
        actionIcon = PhosphorIconsLight.filePlus;
        accentColor = theme.colorScheme.primary;
        break;
      case ApprovalActionType.modifyFile:
        actionIcon = PhosphorIconsLight.pencilSimple;
        accentColor = const Color(0xFFEA580C); // orange-600
        break;
      case ApprovalActionType.deleteFile:
        actionIcon = PhosphorIconsLight.trash;
        accentColor = theme.colorScheme.error;
        break;
      case ApprovalActionType.cleanJunk:
        actionIcon = PhosphorIconsLight.broom;
        accentColor = const Color(0xFFB45309); // amber-700
        break;
      case ApprovalActionType.generic:
        actionIcon = PhosphorIconsLight.question;
        accentColor =
            isDangerous ? theme.colorScheme.error : theme.colorScheme.primary;
        break;
    }

    final bgColor = isDangerous
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.8)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.7);
    final textColor = isDangerous
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onPrimaryContainer;

    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(actionIcon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  approval.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          if (approval.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              approval.description,
              style: TextStyle(
                fontSize: 12,
                color: textColor.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: accentColor, width: 1.5),
                  ),
                  child: const Text('Reject',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: accentColor,
                  ),
                  child: Text(
                    approval.confirmLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
