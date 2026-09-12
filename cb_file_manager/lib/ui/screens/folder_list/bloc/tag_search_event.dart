import 'package:equatable/equatable.dart';

abstract class TagSearchEvent extends Equatable {
  const TagSearchEvent();

  @override
  List<Object?> get props => [];
}

// ─── Load ─────────────────────────────────────────────────────────

class TagSearchLoadTagsForFile extends TagSearchEvent {
  final String filePath;
  const TagSearchLoadTagsForFile(this.filePath);

  @override
  List<Object> get props => [filePath];
}

class TagSearchLoadTagsForFiles extends TagSearchEvent {
  final List<String> filePaths;
  const TagSearchLoadTagsForFiles(this.filePaths);

  @override
  List<Object> get props => [filePaths];
}

class TagSearchLoadAllTags extends TagSearchEvent {
  final String directory;
  const TagSearchLoadAllTags(this.directory);

  @override
  List<Object> get props => [directory];
}

// ─── Single tag ops ────────────────────────────────────────────────

class TagSearchAddTagToFile extends TagSearchEvent {
  final String filePath;
  final String tag;
  const TagSearchAddTagToFile(this.filePath, this.tag);

  @override
  List<Object> get props => [filePath, tag];
}

class TagSearchRemoveTagFromFile extends TagSearchEvent {
  final String filePath;
  final String tag;
  const TagSearchRemoveTagFromFile(this.filePath, this.tag);

  @override
  List<Object> get props => [filePath, tag];
}

class TagSearchDeleteTagGlobally extends TagSearchEvent {
  final String tag;
  final String currentDirectory;
  const TagSearchDeleteTagGlobally(this.tag, this.currentDirectory);

  @override
  List<Object> get props => [tag, currentDirectory];
}

// ─── Batch tag ops ─────────────────────────────────────────────────

class TagSearchBatchAddTag extends TagSearchEvent {
  final List<String> filePaths;
  final String tag;
  const TagSearchBatchAddTag(this.filePaths, this.tag);

  @override
  List<Object> get props => [filePaths, tag];
}

// ─── Search by tag ────────────────────────────────────────────────

class TagSearchByTag extends TagSearchEvent {
  final String tag;
  final String currentDirectory;
  const TagSearchByTag(this.tag, this.currentDirectory);

  @override
  List<Object> get props => [tag, currentDirectory];
}

class TagSearchByTagGlobally extends TagSearchEvent {
  final String tag;
  const TagSearchByTagGlobally(this.tag);

  @override
  List<Object> get props => [tag];
}

class TagSearchByMultipleTags extends TagSearchEvent {
  final List<String> tags;
  final String currentDirectory;
  const TagSearchByMultipleTags(this.tags, this.currentDirectory);

  @override
  List<Object> get props => [tags, currentDirectory];
}

class TagSearchByMultipleTagsGlobally extends TagSearchEvent {
  final List<String> tags;
  const TagSearchByMultipleTagsGlobally(this.tags);

  @override
  List<Object> get props => [tags];
}

class TagSearchSetResults extends TagSearchEvent {
  final List<String> resultPaths;
  final String tagName;
  final bool isGlobal;
  final int total;
  const TagSearchSetResults({
    required this.resultPaths,
    required this.tagName,
    this.isGlobal = false,
    required this.total,
  });

  @override
  List<Object> get props => [resultPaths, tagName, isGlobal, total];
}

class TagSearchClearResults extends TagSearchEvent {
  const TagSearchClearResults();
}

class TagSearchRemovePaths extends TagSearchEvent {
  final Set<String> paths;
  const TagSearchRemovePaths(this.paths);

  @override
  List<Object> get props => [paths];
}
