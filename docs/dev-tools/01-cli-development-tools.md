# CLI Development Tools

## Overview

This document describes CLI tools used for development, testing, and data seeding in CB File Manager. Each feature that requires CLI tools should follow this documentation pattern.

## Seed Tags CLI

### Purpose
Seed test tags into the SQLite database for testing tag management features (bulk select, search, etc.).

### Location
```
cb_file_manager/bin/seed_tags.dart
```

### Prerequisites
- SQLite3 command line tool must be installed and available in PATH
- CB File Manager app must have been run at least once to create the database

### Database Location
- **Windows**: `C:\Users\<username>\Documents\CBFileHub_v2\cb_file_hub.sqlite`
- **macOS**: `~/Documents/CBFileHub_v2/cb_file_hub.sqlite`
- **Linux**: `~/Documents/CBFileHub_v2/cb_file_hub.sqlite`

### Usage

```bash
# Navigate to project directory
cd cb_file_manager

# List all tags in database
dart run bin/seed_tags.dart --list

# Seed n tags (default: 20)
dart run bin/seed_tags.dart --seed 50

# Clear all tags
dart run bin/seed_tags.dart --clear

# Add a specific tag
dart run bin/seed_tags.dart --add "My Tag"

# Remove a specific tag
dart run bin/seed_tags.dart --remove "My Tag"

# Refresh tags (clear and seed 20)
dart run bin/seed_tags.dart --refresh
```

### Command Options

| Option | Description | Example |
|--------|-------------|---------|
| `--list` | List all unique tags in database | `dart run bin/seed_tags.dart --list` |
| `--seed <n>` | Seed n tags to database (default: 20) | `dart run bin/seed_tags.dart --seed 100` |
| `--clear` | Delete all tags from database | `dart run bin/seed_tags.dart --clear` |
| `--add <tag>` | Add a single tag to first file | `dart run bin/seed_tags.dart --add "Urgent"` |
| `--remove <tag>` | Remove tag from all files | `dart run bin/seed_tags.dart --remove "Urgent"` |
| `--refresh` | Clear all and seed 20 new tags | `dart run bin/seed_tags.dart --refresh` |
| `--help` | Show help message | `dart run bin/seed_tags.dart --help` |

### How It Works

#### Seed Distribution
When seeding tags, the CLI:
1. Queries the database for existing files
2. Creates a placeholder file entry if no files exist
3. Distributes tags across files in round-robin fashion

#### Tag Naming Convention
Generated tags follow pattern: `<Category> - <Adjective> <Suffix> <Number>`

Categories: Music, Video, Photo, Work, Personal, Project, Archive, Important, Draft, Final

Adjectives: Urgent, Review, Pending, Completed, Archived, Backup, Temp, New, Old, Favorite

Suffixes: Q1, Q2, Q3, Q4, 2024, 2025, 2026, v1, v2, v3, Final, Draft, Backup

Example output:
```
Music - Urgent Q1 1
Video - Review Q2 2
Photo - Pending Q3 3
Work - Completed Q4 4
...
```

#### Database Operations
The CLI uses `sqlite3` command line tool directly:
- Query: `SELECT DISTINCT tag FROM file_tags ORDER BY tag;`
- Insert: `INSERT INTO file_tags (file_path, tag, normalized_tag, created_at) VALUES (...);`
- Delete: `DELETE FROM file_tags;`

## Creating New CLI Tools

### Template

When creating a new CLI tool for a feature, follow this structure:

```dart
#!/usr/bin/env dart
// CLI tool for [Feature Name]
// Run with: dart run bin/[tool_name].dart [options]
//
// Options:
//   --option1    : Description
//   --option2    : Description

import 'dart:io';

void main(List<String> args) async {
  // Parse arguments
  // Validate prerequisites
  // Execute operations
  // Output results
}
```

### Requirements

1. **Location**: All CLI tools go in `cb_file_manager/bin/`
2. **Dart Entry Point**: Must have `void main(List<String> args)`
3. **Help Flag**: Must support `--help` or `-h`
4. **Platform Support**: Should work on Windows, macOS, Linux
5. **Error Handling**: Must handle errors gracefully with clear messages

### Best Practices

1. Use `--help` to show usage information
2. Validate required tools are available (e.g., sqlite3)
3. Provide clear success/error messages
4. Support both full flags and abbreviations where appropriate
5. Use sensible defaults for optional parameters

## Troubleshooting

### sqlite3 not found
Install SQLite3:
- **Windows**: Download from https://sqlite.org/download.html
- **macOS**: `brew install sqlite3`
- **Linux**: `sudo apt install sqlite3` or equivalent

### Database not found
Run the CB File Manager app at least once to create the database.

### Permission denied
Ensure you have read/write permissions to the database file.
