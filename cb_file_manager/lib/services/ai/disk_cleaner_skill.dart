import 'dart:io';

/// Disk Cleaner agent skill — injected into the AI system prompt only on
/// Windows when the disk cleaner tools are available.
///
/// Kept separate from the main toolDefinitions to reduce prompt size on
/// platforms where the skill is not applicable.
class DiskCleanerSkill {
  DiskCleanerSkill._();

  /// Whether this skill should be active in the current environment.
  static bool get isAvailable => Platform.isWindows;

  /// Compact skill block appended to the system prompt when available.
  static const String skillBlock = '''

**Disk Cleaner skill (Windows-only):**

Tools:
- **list_disk_junk_categories** — {} → list categories with safety levels.
- **get_drive_space** — {} → free/used space per fixed drive.
- **scan_disk_junk** — {"drives":["C:\\\\"],"categories":["windows_temp",...]} → returns scan_id + summary. Read-only. Omit categories to scan defaults.
- **clean_disk_junk** — {"scan_id":"sc_xxx","categories":[...],"permanent":false} — REQUIRES USER APPROVAL. Move to Recycle Bin (default) or permanent if user explicitly asked.
- **get_pending_cleanup_review** — {} → returns the list of items the user is about to clean (set by the Disk Cleaner UI). Use this to review and flag risky items before confirming.
- **get_current_cleaner_scan** — {"max_items":20,"include_selected":true} → reads the full-disk Cleaner screen context for the current tab: root totals, selected node, top directories, top junk candidates, and selected cleanup items.

Workflow: scan → summarize → ask which categories → clean. Forbidden paths auto-skipped server-side.
- When the user is already on the CB Agent Cleaner screen and asks about the scan result, recommendations, what to delete, large folders, junk candidates, or current selection, call get_current_cleaner_scan first.
- "clean disk / free space / remove junk" → use scan_disk_junk then clean_disk_junk.
- "review cleanup" → call get_pending_cleanup_review, analyze results, flag anything risky.
''';
}
