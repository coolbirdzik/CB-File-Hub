# Tag Management

## Overview

CB File Manager uses SQLite database to store file tags. Tags are stored in the `file_tags` table with the following schema:

```sql
CREATE TABLE file_tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path TEXT NOT NULL,
  tag TEXT NOT NULL,
  normalized_tag TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE(file_path, normalized_tag) ON CONFLICT REPLACE
);
```

## Database Location

- **Windows**: `C:\Users\<username>\Documents\CBFileHub_v2\cb_file_hub.sqlite`
- **macOS**: `~/Documents/CBFileHub_v2/cb_file_hub.sqlite`
- **Linux**: `~/Documents/CBFileHub_v2/cb_file_hub.sqlite`

## Tag Storage Locations

Tags are stored in two places:
1. **SQLite Database** (`file_tags` table) - Primary storage for file tags
2. **SharedPreferences** (`standalone_tags`) - For tags created but not assigned to any file

## CLI Tool for Tag Management

A CLI tool is provided for testing and seeding tags:

### Location
```
cb_file_manager/bin/seed_tags.dart
```

### Usage

```bash
# Navigate to project directory
cd cb_file_manager

# List all tags
dart run bin/seed_tags.dart --list

# Seed n tags (distributed across files)
dart run bin/seed_tags.dart --seed 50

# Clear all tags
dart run bin/seed_tags.dart --clear

# Add a specific tag
dart run bin/seed_tags.dart --add "My Tag"

# Remove a specific tag
dart run bin/seed_tags.dart --remove "My Tag"
```

### How Tags are Distributed

When using `--seed`, tags are distributed across existing files in the database:
- If no files exist, tags are added to a placeholder file `/seed_test/placeholder.mp4`
- Tags are distributed one per file in round-robin fashion
- Each tag gets a unique combination: `<Category> - <Adjective> <Suffix> <Number>`

Example tags:
- `Music - Urgent Q1 1`
- `Video - Review Q2 2`
- `Photo - Pending Q3 3`
- etc.

## Development Notes

### TagManager Initialization

The `TagManager` class prioritizes SQLite storage:

```dart
static Future<void> initialize() async {
  await _preferences.init();
  _databaseManager = DatabaseManager.getInstance();
  if (!_databaseManager!.isInitialized()) {
    await _databaseManager!.initialize();
  }
  _useObjectBox = true;  // Uses SQLite
}
```

If initialization fails, it falls back to JSON file storage.

### Reading Tags

Tags are loaded from both sources and merged:

```dart
final Set<String> tags = await TagManager.getAllUniqueTags("");
final standaloneTags = await TagManager.getStandaloneTags();
tags.addAll(standaloneTags);
```

## Troubleshooting

### Tags not appearing in app
1. Check database exists: `Documents/CBFileHub_v2/cb_file_hub.sqlite`
2. Verify tags exist: `SELECT * FROM file_tags;`
3. Clear and reseed if needed: `dart run bin/seed_tags.dart --clear && dart run bin/seed_tags.dart --seed 20`

### JSON fallback
If SQLite fails to initialize, app falls back to JSON storage at:
- `Documents/cb_file_hub/cb_file_hub_global_tags.json`
