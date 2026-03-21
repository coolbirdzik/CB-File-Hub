import 'package:flutter/material.dart';
import 'package:cb_file_manager/services/album_auto_rule_service.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class AutoRulesScreen extends StatefulWidget {
  final int? scopedAlbumId;
  final String? scopedAlbumName;

  const AutoRulesScreen({Key? key, this.scopedAlbumId, this.scopedAlbumName})
      : super(key: key);

  @override
  State<AutoRulesScreen> createState() => _AutoRulesScreenState();
}

class _AutoRulesScreenState extends State<AutoRulesScreen> {
  List<AlbumAutoRule> _rules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    try {
      final rules = await AlbumAutoRuleService.instance.loadRules();
      final filtered = widget.scopedAlbumId == null
          ? rules
          : rules.where((r) => r.albumId == widget.scopedAlbumId).toList();
      if (mounted) {
        setState(() {
          _rules = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rules: $e')),
        );
      }
    }
  }

  Future<void> _showCreateRuleDialog() async {
    Album? fixedAlbum;
    if (widget.scopedAlbumId != null) {
      fixedAlbum =
          await AlbumService.instance.getAlbumById(widget.scopedAlbumId!);
    }

    if (mounted) {
      final result = await showDialog<AlbumAutoRule>(
        context: context,
        builder: (context) => CreateAutoRuleDialog(fixedAlbum: fixedAlbum),
      );

      if (result != null) {
        await AlbumAutoRuleService.instance.addRule(result);
        _loadRules();
      }
    }
  }

  Future<void> _showEditRuleDialog(AlbumAutoRule rule) async {
    final result = await showDialog<AlbumAutoRule>(
      context: context,
      builder: (context) => EditAutoRuleDialog(rule: rule),
    );

    if (result != null) {
      await AlbumAutoRuleService.instance.updateRule(result);
      _loadRules();
    }
  }

  Future<void> _toggleRule(AlbumAutoRule rule) async {
    final updatedRule = AlbumAutoRule(
      id: rule.id,
      name: rule.name,
      albumId: rule.albumId,
      albumName: rule.albumName,
      condition: rule.condition,
      pattern: rule.pattern,
      isActive: !rule.isActive,
      createdAt: rule.createdAt,
      lastTriggered: rule.lastTriggered,
      matchCount: rule.matchCount,
    );

    await AlbumAutoRuleService.instance.updateRule(updatedRule);
    _loadRules();
  }

  Future<void> _deleteRule(AlbumAutoRule rule) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content:
            Text('Are you sure you want to delete the rule "${rule.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AlbumAutoRuleService.instance.deleteRule(rule.id);
      _loadRules();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scopedAlbumId != null
            ? 'Auto Rules — ${widget.scopedAlbumName ?? 'Album'}'
            : 'Auto Album Rules'),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsLight.plus),
            onPressed: _showCreateRuleDialog,
            tooltip: 'Create New Rule',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? _buildEmptyState(theme)
              : _buildRulesList(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsLight.sparkle,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Auto Album Rules',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Automatically organize your photos by creating rules\nthat match filename patterns',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildExampleRules(theme),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _showCreateRuleDialog,
            icon: const Icon(PhosphorIconsLight.plus),
            label: const Text('Create Your First Rule'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleRules(ThemeData theme) {
    final examples = [
      {
        'title': 'Screenshots',
        'description': 'Files containing "screenshot" → Screenshots album',
        'icon': PhosphorIconsLight.screencast,
      },
      {
        'title': 'Camera Photos',
        'description': 'Files starting with "IMG_" → Camera album',
        'icon': PhosphorIconsLight.camera,
      },
      {
        'title': 'Edited Photos',
        'description': 'Files ending with "_edited" → Edited album',
        'icon': PhosphorIconsLight.imageSquare,
      },
    ];

    return Column(
      children: [
        Text(
          'Popular Rule Examples',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ...examples.map((example) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    example['icon'] as IconData,
                    size: 24,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          example['title'] as String,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          example['description'] as String,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildRulesList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rules.length,
      itemBuilder: (context, index) {
        final rule = _rules[index];
        return _buildRuleCard(theme, rule);
      },
    );
  }

  Widget _buildRuleCard(ThemeData theme, AlbumAutoRule rule) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Album: ${rule.albumName}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: rule.isActive,
                  onChanged: (_) => _toggleRule(rule),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditRuleDialog(rule);
                    } else if (value == 'delete') {
                      _deleteRule(rule);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(PhosphorIconsLight.pencilSimple, size: 16),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(PhosphorIconsLight.trash, size: 16),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.funnelSimple,
                        size: 16,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Condition: ${rule.conditionDisplayName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pattern: "${rule.pattern}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatChip(
                  theme,
                  'Matches',
                  rule.matchCount.toString(),
                  PhosphorIconsLight.check,
                ),
                const SizedBox(width: 8),
                if (rule.lastTriggered != null)
                  _buildStatChip(
                    theme,
                    'Last triggered',
                    _formatDate(rule.lastTriggered!),
                    PhosphorIconsLight.clock,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
      ThemeData theme, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class CreateAutoRuleDialog extends StatefulWidget {
  final Album? fixedAlbum;

  const CreateAutoRuleDialog({Key? key, this.fixedAlbum}) : super(key: key);

  @override
  State<CreateAutoRuleDialog> createState() => _CreateAutoRuleDialogState();
}

class _CreateAutoRuleDialogState extends State<CreateAutoRuleDialog> {
  final _nameController = TextEditingController();
  final _patternController = TextEditingController();
  Album? _selectedAlbum;
  RuleCondition _selectedCondition = RuleCondition.contains;
  List<Album> _albums = [];
  bool _isLoading = true;

  final List<Map<String, dynamic>> _templates = [
    {
      'name': 'Screenshots',
      'condition': RuleCondition.contains,
      'pattern': 'screenshot',
      'description': 'Match files containing "screenshot" in filename',
      'examples': ['Screenshot_20241127.png', 'screenshot-2024.jpg'],
    },
    {
      'name': 'Camera Photos',
      'condition': RuleCondition.startsWith,
      'pattern': 'IMG_',
      'description': 'Match files starting with "IMG_"',
      'examples': ['IMG_1234.jpg', 'IMG_5678.png'],
    },
    {
      'name': 'Edited Photos',
      'condition': RuleCondition.endsWith,
      'pattern': '_edited',
      'description': 'Match files ending with "_edited"',
      'examples': ['photo_edited.jpg', 'image_edited.png'],
    },
    {
      'name': 'WhatsApp Images',
      'condition': RuleCondition.startsWith,
      'pattern': 'IMG-',
      'description': 'Match WhatsApp image files',
      'examples': ['IMG-20241127-WA0001.jpg', 'IMG-20241127-WA0002.jpg'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      if (widget.fixedAlbum != null) {
        if (mounted) {
          setState(() {
            _albums = [widget.fixedAlbum!];
            _selectedAlbum = widget.fixedAlbum!;
            _isLoading = false;
          });
        }
      } else {
        final albums = await AlbumService.instance.getAllAlbums();
        if (mounted) {
          setState(() {
            _albums = albums;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.sparkle,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'Create Auto Rule',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(PhosphorIconsLight.x),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTemplateSection(theme),
                          const SizedBox(height: 24),
                          _buildCustomRuleSection(theme),
                          if (_patternController.text.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildPreviewSection(theme),
                          ],
                        ],
                      ),
                    ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _canCreate() ? _createRule : null,
                    child: const Text('Create Rule'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Templates',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a pre-made template to get started quickly',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _templates
              .map((template) => _buildTemplateCard(theme, template))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTemplateCard(ThemeData theme, Map<String, dynamic> template) {
    return InkWell(
      onTap: () => _applyTemplate(template),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              template['name'],
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              template['description'],
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Examples:',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ...((template['examples'] as List<String>).take(2).map(
                  (example) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• $example',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      _nameController.text = template['name'];
      _selectedCondition = template['condition'];
      _patternController.text = template['pattern'];
    });
  }

  Widget _buildCustomRuleSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Custom Rule',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Rule Name',
            hintText: 'e.g., Screenshots to Screenshots Album',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        if (widget.fixedAlbum == null)
          DropdownButtonFormField<Album>(
            initialValue: _selectedAlbum,
            decoration: const InputDecoration(
              labelText: 'Target Album',
              border: OutlineInputBorder(),
            ),
            items: _albums.map((album) {
              return DropdownMenuItem(
                value: album,
                child: Text(album.name),
              );
            }).toList(),
            onChanged: (album) => setState(() => _selectedAlbum = album),
          )
        else
          TextFormField(
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Target Album',
              border: OutlineInputBorder(),
            ),
            initialValue: widget.fixedAlbum!.name,
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<RuleCondition>(
                initialValue: _selectedCondition,
                decoration: const InputDecoration(
                  labelText: 'Condition',
                  border: OutlineInputBorder(),
                ),
                items: RuleCondition.values.map((condition) {
                  return DropdownMenuItem(
                    value: condition,
                    child: Text(_getConditionDisplayName(condition)),
                  );
                }).toList(),
                onChanged: (condition) =>
                    setState(() => _selectedCondition = condition!),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _patternController,
                decoration: InputDecoration(
                  labelText: 'Pattern',
                  hintText: _getPatternHint(_selectedCondition),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _canCreate() {
    return _nameController.text.trim().isNotEmpty &&
        _patternController.text.trim().isNotEmpty &&
        _selectedAlbum != null;
  }

  void _createRule() {
    final rule = AlbumAutoRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      albumId: _selectedAlbum!.id,
      albumName: _selectedAlbum!.name,
      condition: _selectedCondition,
      pattern: _patternController.text.trim(),
      createdAt: DateTime.now(),
    );

    Navigator.pop(context, rule);
  }

  Widget _buildPreviewSection(ThemeData theme) {
    final testFilenames = [
      'IMG_1234.jpg',
      'screenshot_2024.png',
      'photo_edited.jpg',
      'IMG-20241127-WA0001.jpg',
      'document.pdf',
      'video.mp4',
      'my_screenshot.png',
      'edited_photo.jpg',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'See which files would match your rule',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Test Results:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...testFilenames.map((filename) {
                final matches = _testPattern(filename);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        matches
                            ? PhosphorIconsLight.checkCircle
                            : PhosphorIconsLight.xCircle,
                        size: 16,
                        color: matches
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filename,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: matches
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  bool _testPattern(String filename) {
    final pattern = _patternController.text.trim().toLowerCase();
    if (pattern.isEmpty) return false;

    final testName = filename.toLowerCase();

    switch (_selectedCondition) {
      case RuleCondition.contains:
        return testName.contains(pattern);
      case RuleCondition.startsWith:
        return testName.startsWith(pattern);
      case RuleCondition.endsWith:
        return testName.endsWith(pattern);
      case RuleCondition.equals:
        return testName == pattern;
      case RuleCondition.regex:
        try {
          final regex = RegExp(pattern, caseSensitive: false);
          return regex.hasMatch(testName);
        } catch (e) {
          return false;
        }
    }
  }

  String _getConditionDisplayName(RuleCondition condition) {
    switch (condition) {
      case RuleCondition.contains:
        return 'Contains';
      case RuleCondition.startsWith:
        return 'Starts with';
      case RuleCondition.endsWith:
        return 'Ends with';
      case RuleCondition.equals:
        return 'Equals';
      case RuleCondition.regex:
        return 'Regex pattern';
    }
  }

  String _getPatternHint(RuleCondition condition) {
    switch (condition) {
      case RuleCondition.contains:
        return 'e.g., screenshot';
      case RuleCondition.startsWith:
        return 'e.g., IMG_';
      case RuleCondition.endsWith:
        return 'e.g., _edited';
      case RuleCondition.equals:
        return 'e.g., photo';
      case RuleCondition.regex:
        return r'e.g., ^IMG_\d{4}$';
    }
  }
}

class EditAutoRuleDialog extends StatefulWidget {
  final AlbumAutoRule rule;

  const EditAutoRuleDialog({Key? key, required this.rule}) : super(key: key);

  @override
  State<EditAutoRuleDialog> createState() => _EditAutoRuleDialogState();
}

class _EditAutoRuleDialogState extends State<EditAutoRuleDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _patternController;
  Album? _selectedAlbum;
  late RuleCondition _selectedCondition;
  List<Album> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rule.name);
    _patternController = TextEditingController(text: widget.rule.pattern);
    _selectedCondition = widget.rule.condition;
    _loadAlbums();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbums() async {
    try {
      final albums = await AlbumService.instance.getAllAlbums();
      if (mounted) {
        setState(() {
          _albums = albums;
          _selectedAlbum = albums.firstWhere(
            (album) => album.id == widget.rule.albumId,
            orElse: () => albums.first,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.pencilSimple,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'Edit Auto Rule',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(PhosphorIconsLight.x),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEditForm(theme),
                          if (_patternController.text.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildPreviewSection(theme),
                          ],
                        ],
                      ),
                    ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _canSave() ? _saveRule : null,
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rule Details',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Rule Name',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Album>(
          initialValue: _selectedAlbum,
          decoration: const InputDecoration(
            labelText: 'Target Album',
            border: OutlineInputBorder(),
          ),
          items: _albums.map((album) {
            return DropdownMenuItem(
              value: album,
              child: Text(album.name),
            );
          }).toList(),
          onChanged: (album) => setState(() => _selectedAlbum = album),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<RuleCondition>(
                initialValue: _selectedCondition,
                decoration: const InputDecoration(
                  labelText: 'Condition',
                  border: OutlineInputBorder(),
                ),
                items: RuleCondition.values.map((condition) {
                  return DropdownMenuItem(
                    value: condition,
                    child: Text(_getConditionDisplayName(condition)),
                  );
                }).toList(),
                onChanged: (condition) =>
                    setState(() => _selectedCondition = condition!),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _patternController,
                decoration: InputDecoration(
                  labelText: 'Pattern',
                  hintText: _getPatternHint(_selectedCondition),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewSection(ThemeData theme) {
    final testFilenames = [
      'IMG_1234.jpg',
      'screenshot_2024.png',
      'photo_edited.jpg',
      'IMG-20241127-WA0001.jpg',
      'document.pdf',
      'video.mp4',
      'my_screenshot.png',
      'edited_photo.jpg',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'See which files would match your updated rule',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Test Results:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...testFilenames.map((filename) {
                final matches = _testPattern(filename);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        matches
                            ? PhosphorIconsLight.checkCircle
                            : PhosphorIconsLight.xCircle,
                        size: 16,
                        color: matches
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filename,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: matches
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  bool _testPattern(String filename) {
    final pattern = _patternController.text.trim().toLowerCase();
    if (pattern.isEmpty) return false;

    final testName = filename.toLowerCase();

    switch (_selectedCondition) {
      case RuleCondition.contains:
        return testName.contains(pattern);
      case RuleCondition.startsWith:
        return testName.startsWith(pattern);
      case RuleCondition.endsWith:
        return testName.endsWith(pattern);
      case RuleCondition.equals:
        return testName == pattern;
      case RuleCondition.regex:
        try {
          final regex = RegExp(pattern, caseSensitive: false);
          return regex.hasMatch(testName);
        } catch (e) {
          return false;
        }
    }
  }

  bool _canSave() {
    return _nameController.text.trim().isNotEmpty &&
        _patternController.text.trim().isNotEmpty &&
        _selectedAlbum != null;
  }

  void _saveRule() {
    final updatedRule = AlbumAutoRule(
      id: widget.rule.id,
      name: _nameController.text.trim(),
      albumId: _selectedAlbum!.id,
      albumName: _selectedAlbum!.name,
      condition: _selectedCondition,
      pattern: _patternController.text.trim(),
      isActive: widget.rule.isActive,
      createdAt: widget.rule.createdAt,
      lastTriggered: widget.rule.lastTriggered,
      matchCount: widget.rule.matchCount,
    );

    Navigator.pop(context, updatedRule);
  }

  String _getConditionDisplayName(RuleCondition condition) {
    switch (condition) {
      case RuleCondition.contains:
        return 'Contains';
      case RuleCondition.startsWith:
        return 'Starts with';
      case RuleCondition.endsWith:
        return 'Ends with';
      case RuleCondition.equals:
        return 'Equals';
      case RuleCondition.regex:
        return 'Regex pattern';
    }
  }

  String _getPatternHint(RuleCondition condition) {
    switch (condition) {
      case RuleCondition.contains:
        return 'e.g., screenshot';
      case RuleCondition.startsWith:
        return 'e.g., IMG_';
      case RuleCondition.endsWith:
        return 'e.g., _edited';
      case RuleCondition.equals:
        return 'e.g., photo';
      case RuleCondition.regex:
        return r'e.g., ^IMG_\d{4}$';
    }
  }
}
