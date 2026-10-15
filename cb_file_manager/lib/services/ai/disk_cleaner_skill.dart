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
- **clean_disk_junk** — {"scan_id":"<exact ID returned by scan_disk_junk>","categories":[...],"permanent":false} — REQUIRES USER APPROVAL. Move to Recycle Bin (default) or permanent if user explicitly asked.
- **get_pending_cleanup_review** — {} → returns the list of items the user is about to clean (set by the Disk Cleaner UI). Use this to review and flag risky items before confirming.
- **get_current_cleaner_scan** — {"max_items":20,"include_selected":true} → reads the full-disk Cleaner screen context for the current tab: root totals, selected node, top directories, top junk candidates, and selected cleanup items.
- **select_cleaner_scan_items** — {"scan_id":"<exact ID from get_current_cleaner_scan>","paths":["<exact scanned path>"],"replace":true} → checks exact targets in that tab's scan results for user review. No deletion or approval dialog. replace:false adds to the existing selection. Available only for ready, fresh Disk usage results. Never pass a junk scan's sc_... ID.
- **inspect_cleaner_scan_item** — {"scan_id":"<latest scan ID>","path":"<exact scanned path>"} → expands/scrolls/highlights one row on the existing scan screen and returns its evidence plus the latest scan_id. This focus does not check it for cleanup.
- **set_cleaner_scan_item_analysis** — {"scan_id":"<ID returned by inspection>","path":"<inspected path>","decision":"CLEAN|REVIEW|KEEP","reason":"<concrete reason in the user's language>","select":false} → shows a verdict badge and explanation beside the scan. select:true checks CLEAN safe-junk targets for review; REVIEW/KEEP are never automatically checked. No deletion.
- **get_current_app_storage** — {"filter":"all|large|stale|cleanable","max_apps":20,"app_id":"optional","include_paths":false} → reads the App Insights report only after the user explicitly shares it from the Cleaner Apps view. Read-only; it cannot uninstall apps or delete app folders.

Keep analysis and cleanup as two separate workflows:
- Analysis: scan/read current scan → rank large folders and files → explain ownership/category/safety → recommend CLEAN, REVIEW, or KEEP. If the user asks to select recommendations, call select_cleaner_scan_items for evidence-backed CLEAN candidates and report the actual selected paths/count/size. Leave REVIEW/KEEP unchecked unless the user explicitly asks for those exact items. If no candidates qualify, explain why and leave selection unchanged.
- For requests to interact with the scanned UI, or analyze whether scanned files should be deleted, prefer an interactive walkthrough: get_current_cleaner_scan → inspect_cleaner_scan_item for one important item → read its evidence → set_cleaner_scan_item_analysis → continue to the next item. Cover a few useful candidates, including a REVIEW or KEEP item when available. Use select:true for CLEAN only when selection was requested. Use the latest scan_id returned by each interaction, because the UI context changes as you interact. Do not batch inspection and assessment; let the visible focused row precede its explanation. Finish with a brief summary; the per-item reasons are already visible in the scan screen.
- Cleanup: only after the user explicitly asks to clean and confirms the category or target set → call clean_disk_junk → wait for the existing approval UI.
- A request to inspect, explain, recommend, find large files, ask what occupies space, or ask what should be deleted is analysis-only. NEVER call clean_disk_junk for those requests. Selection for review with select_cleaner_scan_items is allowed when requested; it never authorizes deletion.
- Even after scan_disk_junk returns, summarize its evidence in normal text. Do not echo tool JSON, scan arguments, or a clean_disk_junk payload as the answer.
- In recommendations, list path, file/folder type, size, owner or category, CLEAN/REVIEW/KEEP, and a short reason. Being large alone is never evidence that deletion is safe.
- Forbidden paths remain blocked server-side.
- Never invent or copy a placeholder for scan_id. Use the exact `sc_...` value returned by scan_disk_junk. If the exact value is unavailable, omit scan_id so the runtime can bind the latest scan from the current tab.
- Valid cache category IDs are browser_cache, thumbnail_cache, app_cache, windows_update_cache, and dev_cache. Do not use a generic "cache" category.
- When the user is already on the CB Agent Cleaner screen and asks about the scan result, recommendations, what to delete, large folders, junk candidates, or current selection, call get_current_cleaner_scan first.
- When the user explicitly shares App Insights and asks which apps are large, not seen recently, or have cleanable data, call get_current_app_storage. Treat last-opened values as estimates and unknown values as unknown, never as unused.
- "clean disk / free space / remove junk" without confirmed categories → scan, explain findings, and ask the user which recommended categories to clean. Do not clean in the same turn.
- "clean the categories/items I selected/confirmed" → use clean_disk_junk with the exact current scan ID and selected categories, then rely on the approval UI.
- "review cleanup" → call get_pending_cleanup_review, analyze results, flag anything risky.
''';
}
