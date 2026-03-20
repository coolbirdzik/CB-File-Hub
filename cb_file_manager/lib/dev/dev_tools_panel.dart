import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Expandable dev tools panel with various development utilities.
class DevToolsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const DevToolsPanel({Key? key, required this.onClose}) : super(key: key);

  @override
  State<DevToolsPanel> createState() => _DevToolsPanelState();
}

class _DevToolsPanelState extends State<DevToolsPanel> {
  bool _isSeeding = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor =
        isDark ? Colors.grey.shade900 : Colors.grey.shade100;
    final headerColor =
        isDark ? Colors.deepPurple.shade800 : Colors.deepPurple.shade400;
    final textColor = isDark ? Colors.white : Colors.black87;
    final textSecondaryColor = isDark ? Colors.white70 : Colors.black54;
    final surfaceColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);
    final buttonColor =
        isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade600;
    final dangerColor = isDark ? Colors.red.shade400 : Colors.red.shade600;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: backgroundColor,
      child: Container(
        width: 280,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '🛠 Dev Tools',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    child:
                        Icon(Icons.close, color: textSecondaryColor, size: 18),
                  ),
                ],
              ),
            ),
            // Tools list
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSeedTagsTool(),
                    const SizedBox(height: 8),
                    _buildClearTagsTool(),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _status,
                          style: TextStyle(
                              color: textSecondaryColor, fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeedTagsTool() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return _DevToolButton(
      icon: Icons.tag,
      label: 'Seed Tags',
      subtitle: 'Create 100 test tags (long press for custom)',
      isLoading: _isSeeding,
      onTap: () => _seedTags(100),
      onLongPress: () => _showSeedCountDialog(),
      iconColor:
          isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade600,
      textColor: isDark ? Colors.white : Colors.black87,
      textSecondaryColor: isDark ? Colors.white54 : Colors.black54,
      surfaceColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
    );
  }

  Widget _buildClearTagsTool() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return _DevToolButton(
      icon: Icons.delete_sweep,
      label: 'Clear Standalone Tags',
      subtitle: 'Remove dev-seeded standalone tags',
      isLoading: _isSeeding,
      onTap: _clearStandaloneTags,
      iconColor: isDark ? Colors.red.shade400 : Colors.red.shade600,
      textColor: isDark ? Colors.white : Colors.black87,
      textSecondaryColor: isDark ? Colors.white54 : Colors.black54,
      surfaceColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
    );
  }

  Future<void> _showSeedCountDialog() async {
    final controller = TextEditingController(text: '500');
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed Tags'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Number of tags'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text) ?? 500),
            child: const Text('Seed'),
          ),
        ],
      ),
    );
    if (count != null && count > 0) {
      await _seedTags(count);
    }
  }

  Future<void> _seedTags(int count) async {
    setState(() {
      _isSeeding = true;
      _status = 'Seeding $count tags...';
    });

    final categories = [
      'Music',
      'Video',
      'Photo',
      'Work',
      'Personal',
      'Project',
      'Archive',
      'Important',
      'Draft',
      'Final',
    ];
    final adjectives = [
      'Urgent',
      'Review',
      'Pending',
      'Completed',
      'Archived',
      'Backup',
      'Temp',
      'New',
      'Old',
      'Favorite',
    ];
    final suffixes = [
      'Q1',
      'Q2',
      'Q3',
      'Q4',
      '2024',
      '2025',
      '2026',
      'v1',
      'v2',
      'v3',
      'Final',
      'Draft',
      'Backup',
    ];

    try {
      print('[SEED_DIRECT] seed requested count=$count');
      AppLogger.info('[DevTools] Seed tags requested', error: 'count=$count');
      await TagManager.initialize();
      final existingStandaloneTags = await TagManager.getStandaloneTags();
      final startIndex = existingStandaloneTags.length;
      print(
          '[SEED_DIRECT] after init existingStandaloneTags=${existingStandaloneTags.length}');

      // Build all tag names
      final List<String> newTagNames = [];
      for (int i = 0; i < count; i++) {
        final seedIndex = startIndex + i;
        final category = categories[seedIndex % categories.length];
        final adjective = adjectives[seedIndex % adjectives.length];
        final suffix = suffixes[seedIndex % suffixes.length];
        newTagNames.add('$category - $adjective $suffix ${seedIndex + 1}');
      }

      final addedCount =
          await TagManager.addMultipleStandaloneTags(newTagNames);
      print(
          '[SEED_DIRECT] addMultipleStandaloneTags result addedCount=$addedCount lastError=${TagManager.lastStandaloneTagError}');
      AppLogger.info(
        '[DevTools] Seed tags completed',
        error:
            'requested=$count added=$addedCount existingBefore=$startIndex lastError=${TagManager.lastStandaloneTagError}',
      );

      // Verify
      int verifyCount = 0;
      int standaloneCount = 0;
      int sqliteStandaloneCount = 0;
      try {
        final tags = await TagManager.getAllUniqueTags('');
        verifyCount = tags.length;
        standaloneCount = (await TagManager.getStandaloneTags()).length;
        sqliteStandaloneCount =
            (await DatabaseManager.getInstance().getStandaloneTags()).length;
      } catch (_) {}

      if (mounted) {
        setState(
          () => _status = addedCount > 0
              ? '✅ Added $addedCount standalone tags. SQLite: $sqliteStandaloneCount, standalone: $standaloneCount, visible: $verifyCount'
              : '❌ Failed to save dev seed tags. ${TagManager.lastStandaloneTagError ?? "Unknown error"}\n'
                  '${TagManager.standaloneTagDiagnostics}\n'
                  '--- RECENT LOGS ---\n'
                  '${AppLogger.recentLogsTail}',
        );
      }
    } catch (e) {
      print('[SEED_DIRECT] exception=$e');
      if (mounted) {
        setState(() => _status = '❌ Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  Future<void> _clearStandaloneTags() async {
    setState(() {
      _isSeeding = true;
      _status = 'Clearing standalone tags...';
    });

    try {
      await TagManager.initialize();
      final seededTags = await TagManager.getStandaloneTags();
      int cleared = 0;
      for (int i = 0; i < seededTags.length; i++) {
        await TagManager.removeStandaloneTag(seededTags.elementAt(i));
        cleared++;

        if ((i + 1) % 25 == 0 && mounted) {
          setState(
              () => _status = 'Clearing ${i + 1}/${seededTags.length} tags...');
        }
      }

      if (mounted) {
        setState(() => _status = '✅ Cleared $cleared standalone tags');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = '❌ Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }
}

class _DevToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color iconColor;
  final Color textColor;
  final Color textSecondaryColor;
  final Color surfaceColor;

  const _DevToolButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
    this.onLongPress,
    required this.iconColor,
    required this.textColor,
    required this.textSecondaryColor,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        onLongPress: isLoading ? null : onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: textSecondaryColor),
                    )
                  : Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: textSecondaryColor, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
