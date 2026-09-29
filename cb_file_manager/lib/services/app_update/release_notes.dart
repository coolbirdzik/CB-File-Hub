/// Turns the generated GitHub release notes into something readable in the
/// app: the change list only, grouped by kind, without commit hashes or
/// conventional-commit prefixes.
library;

enum ReleaseChangeKind { feature, fix, improvement }

class ReleaseChange {
  final ReleaseChangeKind kind;
  final String text;

  const ReleaseChange(this.kind, this.text);

  @override
  bool operator ==(Object other) =>
      other is ReleaseChange && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'ReleaseChange($kind, $text)';
}

/// Keeps the "What's changed" part of the generated GitHub release notes and
/// drops the title plus the download/installation instructions that follow.
String trimReleaseNotes(String notes) {
  final kept = <String>[];
  for (final line in notes.replaceAll('\r\n', '\n').split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('# ')) continue;
    if (trimmed.startsWith('## ') &&
        (trimmed.contains('Downloads') || trimmed.contains('Installation'))) {
      break;
    }
    kept.add(line);
  }
  return kept.join('\n').trim();
}

final _bullet = RegExp(r'^\s*[-*]\s+(.+)$');
// "(4b8b237)" from `git log --pretty="%s (%h)"`.
final _trailingHash = RegExp(r'\s*\([0-9a-f]{7,40}\)\s*$');
// "by @user in https://github.com/.../pull/12" from GitHub's generator.
final _trailingAuthor = RegExp(r'\s+by @\S+ in \S+\s*$');
final _conventionalPrefix = RegExp(r'^([a-zA-Z]+)(\([^)]*\))?!?:\s*');

/// Commit types that mean nothing to someone using the app.
const _hiddenTypes = {'ci', 'build', 'chore', 'docs', 'test', 'style'};

/// Whether [notes] contain a change list at all, as opposed to prose or
/// nothing (store updates carry no notes).
bool releaseNotesHaveList(String notes) =>
    trimReleaseNotes(notes).split('\n').any(_bullet.hasMatch);

/// The bullet points of [notes], cleaned up and classified. Empty when the
/// notes have no bullet list, or only list changes users never see (CI,
/// tests, docs).
List<ReleaseChange> parseReleaseChanges(String notes) {
  final changes = <ReleaseChange>[];
  for (final line in trimReleaseNotes(notes).split('\n')) {
    final match = _bullet.firstMatch(line);
    if (match == null) continue;
    var text = match
        .group(1)!
        .replaceFirst(_trailingHash, '')
        .replaceFirst(_trailingAuthor, '')
        .trim();
    if (text.isEmpty || text == 'No commits found') continue;

    var kind = ReleaseChangeKind.improvement;
    final prefix = _conventionalPrefix.firstMatch(text);
    if (prefix != null) {
      final type = prefix.group(1)!.toLowerCase();
      if (_hiddenTypes.contains(type)) continue;
      if (type == 'feat' || type == 'feature') {
        kind = ReleaseChangeKind.feature;
      } else if (type == 'fix' || type == 'hotfix') {
        kind = ReleaseChangeKind.fix;
      }
      text = text.substring(prefix.end).trim();
      if (text.isEmpty) continue;
    }
    text = text[0].toUpperCase() + text.substring(1);
    final change = ReleaseChange(kind, text);
    if (!changes.contains(change)) changes.add(change);
  }
  return changes;
}
