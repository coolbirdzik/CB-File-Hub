import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';

class DebugTagsWidget extends StatefulWidget {
  const DebugTagsWidget({Key? key}) : super(key: key);

  @override
  State<DebugTagsWidget> createState() => _DebugTagsWidgetState();
}

class _DebugTagsWidgetState extends State<DebugTagsWidget> {
  bool _isLoading = true;
  bool _isSeeding = false;
  String _debugInfo = '';
  Set<String> _allTags = {};
  Map<String, int> _popularTags = {};
  bool _useDatabase = true;

  // Sample tag categories for realistic seed data
  static const List<String> _categories = [
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

  static const List<String> _adjectives = [
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

  static const List<String> _suffixes = [
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

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
  }

  Future<void> _seedTags(int count) async {
    setState(() {
      _isSeeding = true;
    });

    try {
      int savedCount = 0;
      final List<String> tagsToSeed = [];
      for (int i = 0; i < count; i++) {
        final category = _categories[i % _categories.length];
        final adjective = _adjectives[i % _adjectives.length];
        final suffix = _suffixes[i % _suffixes.length];
        final tag = '$category - $adjective $suffix ${i + 1}';
        tagsToSeed.add(tag);
      }

      savedCount = await TagManager.addMultipleStandaloneTags(tagsToSeed);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Successfully seeded $savedCount/$count tags!')),
        );
        await _loadDebugInfo();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error seeding tags: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSeeding = false;
        });
      }
    }
  }

  Future<void> _clearAllTags() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Tags'),
        content: Text(
            'Are you sure you want to delete all ${_allTags.length} tags? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      for (final tag in _allTags) {
        await TagManager.deleteTagGlobally(tag);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All tags cleared!')),
        );
        await _loadDebugInfo();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing tags: $e')),
        );
      }
    }
  }

  Future<void> _loadDebugInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize preferences
      final preferences = UserPreferences.instance;
      await preferences.init();
      _useDatabase = true;

      // Initialize TagManager
      await TagManager.initialize();

      // Get all unique tags
      final allTags = await TagManager.getAllUniqueTags("");
      _allTags = allTags;

      // Get popular tags
      final popularTags = await TagManager.instance.getPopularTags(limit: 10);
      _popularTags = popularTags;

      // Check database manager
      final dbManager = DatabaseManager.getInstance();
      await dbManager.initialize();
      final dbTags = await dbManager.getAllUniqueTags();

      setState(() {
        _debugInfo = '''
=== DEBUG TAGS SYSTEM ===
SQLite enabled: $_useDatabase
Total unique tags found: ${allTags.length}
Database tags: ${dbTags.length}
Popular tags: ${popularTags.length}

All Tags: $allTags
Database Tags: $dbTags
Popular Tags: $popularTags
''';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _debugInfo = 'Error: $e\nStack trace: ${StackTrace.current}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Tags'),
        actions: [
          if (_isSeeding)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(PhosphorIconsLight.plus),
              tooltip: 'Seed 20 tags',
              onPressed: () => _seedTags(20),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsLight.trash),
              tooltip: 'Clear all tags',
              onPressed: _allTags.isEmpty ? null : _clearAllTags,
            ),
          ],
          IconButton(
            icon: const Icon(PhosphorIconsLight.arrowsClockwise),
            onPressed: _loadDebugInfo,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Debug Information',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _debugInfo,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All Tags (${_allTags.length})',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          if (_allTags.isEmpty)
                            const Text('No tags found')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _allTags
                                  .map((tag) => Chip(
                                        label: Text(tag),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.2),
                                      ))
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Popular Tags (${_popularTags.length})',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          if (_popularTags.isEmpty)
                            const Text('No popular tags found')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _popularTags.entries
                                  .map((entry) => Chip(
                                        label: Text(
                                            '${entry.key} (${entry.value})'),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .secondary
                                            .withValues(alpha: 0.2),
                                      ))
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
