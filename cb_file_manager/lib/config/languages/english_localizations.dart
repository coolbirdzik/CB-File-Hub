import 'app_localizations.dart';

class EnglishLocalizations implements AppLocalizations {
  @override
  String get appTitle => 'CB File Hub';

  // Common actions
  @override
  String get ok => 'OK';
  @override
  String get cancel => 'Cancel';
  @override
  String get save => 'Save';
  @override
  String get delete => 'Delete';
  @override
  String get edit => 'Edit';
  @override
  String get close => 'Close';
  @override
  String get exit => 'Exit';
  @override
  String get search => 'Search';
  @override
  String get all => 'All';
  @override
  String get settings => 'Settings';

  @override
  String get moreOptions => 'More options';

  // File operations
  @override
  String get copy => 'Copy';
  @override
  String get cut => 'Cut';
  @override
  String get move => 'Move';
  @override
  String get rename => 'Rename';
  @override
  String get newFolder => 'New Folder';
  @override
  String get properties => 'Properties';
  @override
  String get openWith => 'Open with';
  @override
  String get chooseDefaultApp => 'Choose default app';
  @override
  String get setCoolBirdAsDefaultForVideos =>
      'Set CB File Hub as default for video files';
  @override
  String get setCoolBirdAsDefaultForVideosAndroidHint =>
      'Opening Settings. In "Open by default", enable CB File Hub for video files.';
  @override
  String get openFolder => 'Open Folder';
  @override
  String get openFile => 'Open File';
  @override
  String get viewImage => 'View Image';
  @override
  String get open => 'Open';
  @override
  String get pasteHere => 'Paste Here';
  @override
  String get manageTags => 'Manage Tags';
  @override
  String get moveToTrash => 'Move to Trash';

  @override
  String get errorAccessingDirectory => 'Error accessing directory';
  @override
  String errorAccessingDirectoryWithError(String error) =>
      'Error accessing directory: $error';
  @override
  String accessDeniedAdminMessage(String path) =>
      'Access denied: Administrator privileges required to access $path';
  @override
  String directoryDoesNotExist(String path) =>
      'Directory does not exist: $path';

  // Action bar tooltips
  @override
  String get searchTooltip => 'Search';

  @override
  String get sortByTooltip => 'Sort by';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String get moreOptionsTooltip => 'More options';

  @override
  String get adjustGridSizeTooltip => 'Adjust item size';

  @override
  String get columnSettingsTooltip => 'Column settings';

  @override
  String get viewModeTooltip => 'View mode';

  // Dialog titles
  @override
  String get adjustGridSizeTitle => 'Adjust Item Size';

  @override
  String get columnVisibilityTitle => 'Customize Column Display';

  // Button labels
  @override
  String get apply => 'APPLY';

  // Sort options
  @override
  String get sortNameAsc => 'Name (A → Z)';

  @override
  String get sortNameDesc => 'Name (Z → A)';

  @override
  String get sortDateModifiedOldest => 'Date Modified (Oldest First)';

  @override
  String get sortDateModifiedNewest => 'Date Modified (Newest First)';

  @override
  String get sortDateCreatedOldest => 'Date Created (Oldest First)';

  @override
  String get sortDateCreatedNewest => 'Date Created (Newest First)';

  @override
  String get sortSizeSmallest => 'Size (Smallest First)';

  @override
  String get sortSizeLargest => 'Size (Largest First)';

  @override
  String get sortTypeAsc => 'File Type (A → Z)';

  @override
  String get sortTypeDesc => 'File Type (Z → A)';

  @override
  String get sortExtensionAsc => 'Extension (A → Z)';

  @override
  String get sortExtensionDesc => 'Extension (Z → A)';

  @override
  String get sortAttributesAsc => 'Attributes (A → Z)';

  @override
  String get sortAttributesDesc => 'Attributes (Z → A)';

  // View modes
  @override
  String get viewModeList => 'List';

  @override
  String get viewModeGrid => 'Grid';

  @override
  String get viewModeDetails => 'Details';

  @override
  String get viewModeGridPreview => 'Grid + Preview';

  @override
  String get previewPaneTitle => 'Preview';

  @override
  String get previewSelectFile => 'Select a file to preview';

  @override
  String get previewNotSupported => 'Preview not available for this file type';

  @override
  String get previewUnavailable => 'Preview not available';

  @override
  String get showPreview => 'Show preview';

  @override
  String get hidePreview => 'Hide preview';

  // Column names
  @override
  String get columnSize => 'Size';

  @override
  String get columnType => 'Type';

  @override
  String get columnDateModified => 'Date Modified';

  @override
  String get columnDateCreated => 'Date Created';

  @override
  String get columnAttributes => 'Attributes';

  // Column descriptions
  @override
  String get columnSizeDescription => 'Display file size';

  @override
  String get columnTypeDescription => 'Display file type (PDF, Word, etc.)';

  @override
  String get columnDateModifiedDescription =>
      'Display date and time file was modified';

  @override
  String get columnDateCreatedDescription =>
      'Display date and time file was created';

  @override
  String get columnAttributesDescription =>
      'Display file attributes (read/write permissions)';

  // Column visibility dialog
  @override
  String get columnVisibilityInstructions =>
      'Select the columns you want to display in details view. '
      'The "Name" column is always displayed and cannot be disabled.';

  // Grid size dialog
  @override
  String gridSizeLabel(int count) => 'Item size level: $count';

  @override
  String get gridSizeInstructions => 'Move the slider to adjust the item size';

  // More options menu
  @override
  String get selectMultipleFiles => 'Select multiple files';

  @override
  String get viewImageGallery => 'View image gallery';

  @override
  String get viewVideoGallery => 'View video gallery';

  // Navigation
  @override
  String get home => 'Home';
  @override
  String get back => 'Back';
  @override
  String get forward => 'Forward';
  @override
  String get refresh => 'Refresh';
  @override
  String get parentFolder => 'Parent Folder';
  @override
  String get local => 'Local';
  @override
  String get networks => 'Networks';

  // File types
  @override
  String get image => 'Image';
  @override
  String get video => 'Video';
  @override
  String get audio => 'Audio';
  @override
  String get document => 'Document';
  @override
  String get folder => 'Folder';
  @override
  String get file => 'File';

  // File type labels
  @override
  String get fileTypeGeneric => 'File';
  @override
  String get fileTypeJpeg => 'JPEG Image';
  @override
  String get fileTypePng => 'PNG Image';
  @override
  String get fileTypeGif => 'GIF Image';
  @override
  String get fileTypeBmp => 'BMP Image';
  @override
  String get fileTypeTiff => 'TIFF Image';
  @override
  String get fileTypeWebp => 'WebP Image';
  @override
  String get fileTypeSvg => 'SVG Image';
  @override
  String get fileTypeMp4 => 'MP4 Video';
  @override
  String get fileTypeAvi => 'AVI Video';
  @override
  String get fileTypeMov => 'MOV Video';
  @override
  String get fileTypeWmv => 'WMV Video';
  @override
  String get fileTypeFlv => 'FLV Video';
  @override
  String get fileTypeMkv => 'MKV Video';
  @override
  String get fileTypeMp3 => 'MP3 Audio';
  @override
  String get fileTypeWav => 'WAV Audio';
  @override
  String get fileTypeAac => 'AAC Audio';
  @override
  String get fileTypeFlac => 'FLAC Audio';
  @override
  String get fileTypeOgg => 'OGG Audio';
  @override
  String get fileTypePdf => 'PDF Document';
  @override
  String get fileTypeWord => 'Word Document';
  @override
  String get fileTypeExcel => 'Excel Spreadsheet';
  @override
  String get fileTypePowerPoint => 'PowerPoint Presentation';
  @override
  String get fileTypeTxt => 'Text File';
  @override
  String get fileTypeRtf => 'RTF Document';
  @override
  String get fileTypeZip => 'ZIP Archive';
  @override
  String get fileTypeRar => 'RAR Archive';
  @override
  String get fileType7z => '7Z Archive';
  @override
  String fileTypeWithExtension(String extension) => '$extension File';

  // Settings
  @override
  String get language => 'Language';
  @override
  String get theme => 'Theme';
  @override
  String get darkMode => 'Dark Mode';
  @override
  String get lightMode => 'Light Mode';
  @override
  String get systemMode => 'System Mode';
  @override
  String get selectLanguage => 'Select the language you want to use';
  @override
  String get selectTheme => 'Choose the display theme for the app';
  @override
  String get selectThumbnailPosition =>
      'Choose the video thumbnail extraction position';
  @override
  String get systemThemeDescription => 'Follow the system theme settings';
  @override
  String get lightThemeDescription => 'Light interface for all screens';
  @override
  String get darkThemeDescription => 'Dark interface for all screens';
  @override
  String get themeOnboardingTitle => 'Choose your theme';
  @override
  String get themeOnboardingDescription =>
      'Pick your default appearance before entering the app.';
  @override
  String get themeOnboardingLightLabel => 'Light';
  @override
  String get themeOnboardingDarkLabel => 'Dark';
  @override
  String get themeOnboardingMoreThemesMessage =>
      'More themes are available in Settings.';
  @override
  String get themeOnboardingContinue => 'Continue';
  @override
  String get vietnameseLanguage => 'Vietnamese';
  @override
  String get englishLanguage => 'English';

  // Messages
  @override
  String get fileDeleteConfirmation =>
      'Are you sure you want to delete this file?';
  @override
  String get folderDeleteConfirmation =>
      'Are you sure you want to delete this folder and all its contents?';
  @override
  String get fileDeleteSuccess => 'File deleted successfully';
  @override
  String get folderDeleteSuccess => 'Folder deleted successfully';
  @override
  String get operationFailed => 'Operation failed';

  // Tags
  @override
  String get tags => 'Tags';
  @override
  String get addTag => 'Add Tag';
  @override
  String get removeTag => 'Remove Tag';
  @override
  String get tagListRefreshing => 'Refreshing tag list...';
  @override
  String get tagManagement => 'Tag Management';
  @override
  String deleteTagConfirmation(String tag) => 'Delete tag "$tag"?';
  @override
  String get tagDeleteConfirmationText =>
      'This will remove the tag from all files. This action cannot be undone.';
  @override
  String tagDeleted(String tag) => 'Tag "$tag" deleted successfully';
  @override
  String errorDeletingTag(String error) => 'Error deleting tag: $error';
  @override
  String chooseTagColor(String tag) => 'Choose Color for "$tag"';
  @override
  String tagColorUpdated(String tag) => 'Color for tag "$tag" has been updated';
  @override
  String get allTags => 'All Tags';
  @override
  String get filesWithTag => 'Files with tag "%s"';
  @override
  String get tagsInDirectory => 'Tags in "%s"';
  @override
  String get aboutTags => 'About Tag Management';
  @override
  String get aboutTagsTitle => 'Introduction to tag management:';
  @override
  String get aboutTagsDescription =>
      'Tags help you organize files by adding custom labels. '
      'You can add or remove tags from files, and find all files with specific tags.';
  @override
  String get aboutTagsScreenDescription => '• All tags in your library\n'
      '• Files tagged with selected tag\n'
      '• Options to delete tags';
  @override
  String get deleteTag => 'Delete this tag from all files';
  @override
  String get deleteAlbum => 'Delete Album';

  // Tag Management Screen
  @override
  String get tagManagementTitle => 'Tag Management';
  @override
  String get debugTags => 'Debug Tags';
  @override
  String get searchTags => 'Search';
  @override
  String get searchTagsHint => 'Search tags...';
  @override
  String get createNewTag => 'Create New Tag';
  @override
  String get newTagTooltip => 'Create new tag';
  @override
  String get errorLoadingTags => 'Error loading tags: ';
  @override
  String get noTagsFoundMessage => 'No tags found';
  @override
  String get noTagsFoundDescription =>
      'Create new tags to start organizing files';
  @override
  String get createNewTagButton => 'Create New Tag';
  @override
  String noMatchingTagsMessage(String searchTags) =>
      'No tags match "$searchTags"';
  @override
  String get clearSearch => 'Clear Search';
  @override
  String get tagManagementHeader => 'Tag Management';
  @override
  String get tagsCreated => 'tags created';
  @override
  String get tagManagementDescription =>
      'Tap on a tag to view all files with that tag. Use the buttons on the right to change color or delete tags.';
  @override
  String get sortTags => 'Sort Tags';
  @override
  String get sortByAlphabet => 'By Alphabet';
  @override
  String get sortByPopular => 'By Popular';
  @override
  String get listViewMode => 'List Mode';
  @override
  String get gridViewMode => 'Grid Mode';
  @override
  String get previousPage => 'Previous Page';
  @override
  String get nextPage => 'Next Page';
  @override
  String get page => 'Page';
  @override
  String get firstPage => 'First Page';
  @override
  String get lastPage => 'Last Page';
  @override
  String get clickToViewFiles => 'Tap to view files';
  @override
  String get changeTagColor => 'Change Tag Color';
  @override
  String get deleteTagFromAllFiles => 'Delete this tag from all files';
  @override
  String get openInNewTab => 'Open in New Tab';
  @override
  String get viewFilesWithTag => 'View Files with Tag';
  @override
  String get renameTag => 'Rename Tag';
  @override
  String tagRenamed(String oldTag, String newTag) =>
      'Tag "$oldTag" renamed to "$newTag"';
  @override
  String get openInSplitView => 'Open in Split View';
  @override
  String get changeColor => 'Change Color';
  @override
  String get noFilesWithTag => 'No files found with this tag';
  @override
  String debugInfo(String tag) => 'Debug info: searching for tag "$tag"';
  @override
  String get backToAllTags => 'Back to All Tags';
  @override
  String get tryAgain => 'Try Again';
  @override
  String get filesWithTagCount => 'files';
  @override
  String get viewDetails => 'View Details';
  @override
  String get openContainingFolder => 'Open Containing Folder';
  @override
  String get editTags => 'Edit Tags';
  @override
  String get newTagTitle => 'Create New Tag';
  @override
  String get enterTagName => 'Enter tag name...';
  @override
  String get tagName => 'Tag name';
  @override
  String get enterNewTagName => 'Enter new tag name...';
  @override
  String tagAlreadyExists(String tagName) => 'Tag "$tagName" already exists';
  @override
  String tagCreatedSuccessfully(String tagName) =>
      'Tag "$tagName" created successfully';
  @override
  String get errorCreatingTag => 'Error creating tag: ';
  @override
  String get tagsSavedSuccessfully => 'Tags saved successfully';
  @override
  String get selectTagToRemove => 'Select a tag to remove:';
  @override
  String get doubleClickToRename => 'Double-click to rename';
  @override
  String get openingFolder => 'Opening folder: ';
  @override
  String get folderNotFound => 'Folder not found: ';
  @override
  String get refreshTags => 'Refresh tags';
  @override
  String tagsRefreshed(int count) => 'Tags refreshed - $count tags loaded';

  // Gallery
  @override
  String get imageGallery => 'Image Gallery';
  @override
  String get videoGallery => 'Video Gallery';

  // Additional translations for database settings
  @override
  String get databaseSettings => 'Database Settings';
  @override
  String get databaseStorage => 'Database Storage';
  @override
  String get useDatabaseStorage => 'Use SQLite Database';
  @override
  String get databaseStorageEnabled =>
      'Using SQLite for efficient local database storage';
  @override
  String get databaseDescription =>
      'Store tags and preferences in a local database';
  @override
  String get jsonStorage => 'Using JSON file for basic storage';
  @override
  String get objectBoxStorage =>
      'Using SQLite for efficient local database storage'; // Legacy

  // Cloud sync
  @override
  String get cloudSync => 'Cloud Sync';
  @override
  String get enableCloudSync => 'Enable Cloud Sync';
  @override
  String get cloudSyncDescription => 'Sync tags and preferences to the cloud';
  @override
  String get syncToCloud => 'Sync to Cloud';
  @override
  String get syncFromCloud => 'Sync from Cloud';
  @override
  String get cloudSyncEnabled =>
      'Tags and preferences will be synced to the cloud';
  @override
  String get cloudSyncDisabled => 'Cloud sync is disabled';
  @override
  String get enableDatabaseForCloud =>
      'Enable SQLite database to use cloud sync';

  // Database statistics
  @override
  String get databaseStatistics => 'Database Statistics';
  @override
  String get totalUniqueTags => 'Total unique tags';
  @override
  String get taggedFiles => 'Tagged files';
  @override
  String get popularTags => 'Most Popular Tags';
  @override
  String get recentTags => 'Recent Tags';
  @override
  String get selectedTags => 'Selected tags:';
  @override
  String batchAddTags(int count) => 'Add tags to $count files';
  @override
  String get applyingChanges => 'Applying changes...';
  @override
  String tagsUpdated(int count, int added, int removed) {
    var msg = 'Tags updated for $count files';
    final parts = <String>[];
    if (added > 0) parts.add('added $added');
    if (removed > 0) parts.add('removed $removed');
    if (parts.isNotEmpty) msg += ' (${parts.join(', ')})';
    return msg;
  }

  @override
  String get tagSuggestions => 'Tag Suggestions';
  @override
  String get advancedDatabaseSettings => 'Advanced Database Settings';
  @override
  String get noTagsFound => 'No tags found';
  @override
  String get refreshStatistics => 'Refresh Statistics';

  // Raw Data Viewer
  @override
  String get viewRawData => 'View Raw Data';
  @override
  String get rawDataPreferences => 'Preferences';
  @override
  String get rawDataTags => 'File Tags';
  @override
  String get rawDataDescription =>
      'View raw data stored in the database (for debugging)';
  @override
  String get noDataFound => 'No data found';

  // Import/Export
  @override
  String get importExportDatabase => 'Import/Export Database';
  @override
  String get backupRestoreDescription =>
      'Backup and restore your tags and file relationships';
  @override
  String get exportDatabase => 'Export Database';
  @override
  String get exportSettings => 'Export Settings';
  @override
  String get importDatabase => 'Import Database';
  @override
  String get importSettings => 'Import Settings';
  @override
  String get resetSettings => 'Reset Settings';
  @override
  String get exportDescription => 'Save your tags to a file';
  @override
  String get importDescription => 'Restore your tags from a file';
  @override
  String get completeBackup => 'Complete Backup';
  @override
  String get completeRestore => 'Complete Restore';
  @override
  String get exportAllData => 'Export all settings and database data';
  @override
  String get importAllData => 'Import all settings and database data';

  // Export/Import messages
  @override
  String get exportSuccess => 'Successfully exported to: ';
  @override
  String get exportFailed => 'Export failed';
  @override
  String get importSuccess => 'Successfully imported';
  @override
  String get importFailed => 'Import failed or canceled';
  @override
  String get importCancelled => 'Import cancelled';
  @override
  String get errorExporting => 'Error exporting: ';
  @override
  String get errorImporting => 'Error importing: ';

  // Video thumbnails
  @override
  String get videoThumbnails => 'Video Thumbnails';
  @override
  String get thumbnailMode => 'Generation Mode';
  @override
  String get thumbnailModeFast => 'Fast';
  @override
  String get thumbnailModeCustom => 'Custom';
  @override
  String get thumbnailModeFastDescription =>
      'Uses OS built-in methods. Faster but position is fixed.';
  @override
  String get thumbnailModeCustomDescription =>
      'Uses FFmpeg to extract at specific position. Slower but more control.';
  @override
  String get thumbnailPosition => 'Thumbnail position:';
  @override
  String get generatingAtPosition => 'Extracting at';
  @override
  String get generatingFast => 'Fast mode';
  @override
  String get maxConcurrency => 'Max parallel tasks';
  @override
  String get maxConcurrencyDescription =>
      'Higher values generate thumbnails faster but use more CPU';
  @override
  String get percentOfVideo => 'percent of video';
  @override
  String get thumbnailDescription =>
      'Set the position in the video (as a percentage of total duration) where thumbnails will be extracted';
  @override
  String get useSystemDefaultForVideo => 'Use system default app for video';
  @override
  String get useSystemDefaultForVideoDescription =>
      'When on, tapping a video opens it with the system default app (e.g. VLC). When off, uses the in-app player.';
  @override
  String get useSystemDefaultForVideoEnabled =>
      'Videos will open with the system default app';
  @override
  String get useSystemDefaultForVideoDisabled =>
      'Videos will open in the in-app player';
  @override
  String get thumbnailCache => 'Thumbnail Cache';
  @override
  String get thumbnailCacheDescription =>
      'Video thumbnails are cached to improve performance. If thumbnails appear outdated or you want to free up space, you can clear the cache.';
  @override
  String get clearThumbnailCache => 'Clear Thumbnail Cache';
  @override
  String get clearing => 'Clearing...';
  @override
  String get thumbnailCleared => 'All video thumbnails cleared';
  @override
  String get errorClearingThumbnail => 'Error clearing thumbnails: ';

  // New tab
  @override
  String get newTab => 'New Tab';

  // Admin access
  @override
  String get adminAccess => 'Admin Access';
  @override
  String get adminAccessRequired =>
      'This drive requires administrator privileges to access';
  @override
  String get requiresAdminPrivileges => 'Requires administrator privileges';
  @override
  String driveRequiresAdmin(String path) =>
      'The drive $path requires administrator privileges to access.';
  @override
  String get trashBin => 'Trash Bin';

  // File system
  @override
  String get drives => 'Drives';
  @override
  String get system => 'System';

  // Settings data
  @override
  String get settingsData => 'Settings Data';
  @override
  String get viewManageSettings => 'View and manage settings data';

  // About app
  @override
  String get aboutApp => 'About App';
  @override
  String get appDescription => 'An advanced file management solution';
  @override
  String get version => 'Version';
  @override
  String get developer => 'Developer';

  // Empty state
  @override
  String get emptyFolder => 'Empty folder';
  @override
  String get noImagesFound => 'No images found in this folder';
  @override
  String get noVideosFound => 'No videos found in this folder';
  @override
  String get loading => 'Loading...';

  // File picker dialogs
  @override
  String get chooseBackupLocation => 'Choose backup location';
  @override
  String get chooseRestoreLocation => 'Choose Restore File';
  @override
  String get saveSettingsExport => 'Save Settings Export';
  @override
  String get saveDatabaseExport => 'Save Database Export';
  @override
  String get selectBackupFolder => 'Select Backup Folder';

  // File details
  @override
  String get fileSize => 'Size';
  @override
  String get fileLocation => 'Location';
  @override
  String get fileCreated => 'Created';
  @override
  String get fileModified => 'Modified';
  @override
  String get fileName => 'File name';
  @override
  String get filePath => 'File path';
  @override
  String get fileType => 'File type';
  @override
  String get fileLastModified => 'Last modified';
  @override
  String get fileAccessed => 'Accessed';
  @override
  String get loadingVideo => 'Loading video...';
  @override
  String get errorLoadingImage => 'Error loading image';
  @override
  String errorLoadingImageWithError(String error) =>
      'Error loading image: $error';
  @override
  String get failedToDisplayImage => 'Failed to display image';
  @override
  String get noImageDataAvailable => 'No image data available';
  @override
  String get urlLoadingNotImplemented => 'URL loading not implemented yet';
  @override
  String get duration => 'Duration';
  @override
  String get resolution => 'Resolution';
  @override
  String get createCopy => 'Create copy';
  @override
  String get deleteFile => 'Delete file';

  // Folder thumbnails
  @override
  String get folderThumbnail => 'Folder thumbnail';
  @override
  String get chooseThumbnail => 'Choose thumbnail';
  @override
  String get clearThumbnail => 'Clear thumbnail';
  @override
  String get thumbnailAuto => 'Auto (first video/image)';
  @override
  String get folderThumbnailSet => 'Folder thumbnail updated';
  @override
  String get folderThumbnailCleared => 'Folder thumbnail cleared';
  @override
  String get invalidThumbnailFile => 'Please select an image or video file';
  @override
  String get noMediaFilesFound => 'No media files found in this folder';

  // Video actions
  @override
  String get share => 'Share';
  @override
  String get playVideo => 'Play video';
  @override
  String get videoInfo => 'Video info';
  @override
  String get deleteVideo => 'Delete video';
  @override
  String get loadingThumbnails => 'Loading thumbnails';
  @override
  String get deleteVideosConfirm => 'Delete videos?';
  @override
  String get deleteConfirmationMessage =>
      'Are you sure you want to delete the selected videos? This action cannot be undone.';
  @override
  String videosSelected(int count) =>
      '$count video${count == 1 ? '' : 's'} selected';
  @override
  String videosDeleted(int count) =>
      'Deleted $count video${count == 1 ? '' : 's'}';
  @override
  String searchingFor(String query) => 'Searching for: "$query"';
  @override
  String get errorDisplayingVideoInfo => 'Cannot display video information';
  @override
  String get searchVideos => 'Search videos';
  @override
  String get enterVideoName => 'Enter video name...';

  // Selection and grid
  @override
  String? get selectMultiple => 'Select multiple files';
  @override
  String? get gridSize => 'Grid size';

  @override
  String get searchOrEnterPath => 'Search or enter path';

  @override
  String get pleaseCreateTabFirst => 'Please create a tab first';

  @override
  String get viewMode => 'View mode';

  @override
  String get masonryLayout => 'Masonry layout (Pinterest)';

  // Sorting
  @override
  String get sort => 'Sort';
  @override
  String get sortByName => 'Sort by name';
  @override
  String get sortByPopularity => 'Sort by popularity';
  @override
  String get sortByRecent => 'Sort by recent';
  @override
  String get sortBySize => 'Sort by size';
  @override
  String get sortByDate => 'Sort by date';

  // Bulk Selection
  @override
  String get bulkSelect => 'Bulk select';
  @override
  String get selectAllTags => 'Select all';
  @override
  String selectAllOnAllPages(int totalCount) => 'Select all ($totalCount tags)';
  @override
  String get deselectAllTags => 'Deselect all';
  @override
  String tagsSelected(int count) =>
      '$count tag${count == 1 ? '' : 's'} selected';
  @override
  String bulkDeleteConfirmationTitle() => 'Delete selected tags?';
  @override
  String bulkDeleteConfirmationText(int count) =>
      'Are you sure you want to delete $count tag${count == 1 ? '' : 's'}? This action cannot be undone.';
  @override
  String bulkDeleteSuccess(int count) =>
      'Successfully deleted $count tag${count == 1 ? '' : 's'}';

  // Search errors
  @override
  String noFilesFoundTag(Map<String, String> args) =>
      'No files found with tag "${args['tag']}"';

  @override
  String noFilesFoundTagGlobal(Map<String, String> args) =>
      'No files found with tag "${args['tag']}" globally';

  @override
  String noFilesFoundTags(Map<String, String> args) =>
      'No files found with tags ${args['tags']}';

  @override
  String noFilesFoundTagsGlobal(Map<String, String> args) =>
      'No files found with tags ${args['tags']} globally';

  @override
  String noFilesFoundQuery(Map<String, String> args) =>
      'No results found for "${args['query']}"';

  @override
  String errorSearchTag(Map<String, String> args) =>
      'Error searching by tag: ${args['error']}';

  @override
  String errorSearchTagGlobal(Map<String, String> args) =>
      'Error searching by tag globally: ${args['error']}';

  @override
  String errorSearchTags(Map<String, String> args) =>
      'Error searching by multiple tags: ${args['error']}';

  @override
  String errorSearchTagsGlobal(Map<String, String> args) =>
      'Error searching by multiple tags globally: ${args['error']}';

  // Search status
  @override
  String searchingTag(Map<String, String> args) =>
      'Searching for tag "${args['tag']}"...';

  @override
  String searchingTagGlobal(Map<String, String> args) =>
      'Searching for tag "${args['tag']}" globally...';

  @override
  String searchingTags(Map<String, String> args) =>
      'Searching for tags ${args['tags']}...';

  @override
  String searchingTagsGlobal(Map<String, String> args) =>
      'Searching for tags ${args['tags']} globally...';

  // Search UI
  @override
  String get searchTips => 'Search Tips';

  @override
  String get searchTipsTitle => 'Search Tips';

  @override
  String get viewTagSuggestions => 'View tag suggestions';

  @override
  String get globalSearchModeEnabled => 'Switched to global search';

  @override
  String get localSearchModeEnabled => 'Switched to current folder search';

  @override
  String get globalSearchMode => 'Searching globally (tap to switch)';

  @override
  String get localSearchMode => 'Searching current folder (tap to switch)';

  @override
  String get searchByFilename => 'Search by filename';

  @override
  String get searchByTags => 'Search by tags';

  @override
  String get searchMultipleTags => 'Search multiple tags';

  @override
  String get globalSearch => 'Global search';

  @override
  String get searchByNameOrTag => 'Search by name or #tag';

  @override
  String get searchInSubfolders => 'Search in subfolders';

  @override
  String get featureNotImplemented => 'This feature will be added soon';

  @override
  String get searchInAllFolders => 'Search in all folders';

  @override
  String get searchInCurrentFolder => 'Search in current folder only';

  @override
  String get searchShortcuts => 'Shortcuts';

  @override
  String get searchHintText => 'Search files or use # to search by tags';

  @override
  String get searchHintTextTags => 'Search by tags... (e.g. #important #work)';

  @override
  String get suggestedTags => 'Suggested tags';

  @override
  String get noMatchingTags => 'No matching tags found';

  @override
  String get results => 'results';

  @override
  String searchResultsTitle(String countText) => 'Search results$countText';

  @override
  String searchResultsTitleForQuery(String query, String countText) =>
      'Search results for "$query"$countText';

  @override
  String searchResultsTitleForTag(String tag, String countText) =>
      'Tag search results for "$tag"$countText';

  @override
  String searchResultsTitleForTagGlobal(String tag, String countText) =>
      'Global tag search results for "$tag"$countText';

  @override
  String searchResultsTitleForFilter(String filter, String countText) =>
      'Filtered results for "$filter"$countText';

  @override
  String searchResultsTitleForMedia(String mediaType, String countText) =>
      'Search results for $mediaType$countText';

  @override
  String get searchByFilenameDesc => 'Enter a filename to search.';

  @override
  String get searchByTagsDesc =>
      'Use the # symbol to search by tag. Example: #important';

  @override
  String get searchMultipleTagsDesc =>
      'Use multiple tags at once to filter results more precisely. Each tag needs a # symbol at the beginning and must be separated by spaces. Example: #work #urgent #2023';

  @override
  String get globalSearchDesc =>
      'Click on the folder/globe icon to toggle between searching the current folder and the entire system.';

  @override
  String get searchShortcutsDesc =>
      'Press Enter to start searching. Use arrow keys to select tags from suggestions.';

  // File operations related to networks
  @override
  String get download => 'Download';
  @override
  String get downloadFile => 'Download File';
  @override
  String get selectDownloadLocation => 'Select location to save the file:';
  @override
  String get selectFolder => 'Select folder';
  @override
  String get browse => 'Browse...';
  @override
  String get upload => 'Upload File';
  @override
  String get uploadFile => 'Upload File';
  @override
  String get selectFileToUpload => 'Select file to upload:';
  @override
  String get create => 'Create';
  @override
  String get folderName => 'Folder Name';

  // Permissions
  @override
  String get grantPermissionsToContinue => 'Grant Permissions to Continue';

  @override
  String get permissionsDescription =>
      'To use the app smoothly, please grant the following permissions. You can skip and grant them later in Settings.';

  @override
  String get storagePermissionRequiredMessage =>
      'Access to all files is required to view folder contents. Please go to Settings > Apps > CB File Hub > Permissions and enable "All files access".';

  @override
  String get storagePhotosPermission => 'Storage/Photos Permission';

  @override
  String get storagePhotosDescription =>
      'The app needs access to Photos/Files to display and play local content.';

  @override
  String get allFilesAccessPermission => 'All Files Access (Important)';

  @override
  String get allFilesAccessDescription =>
      'This permission is needed to display all files including APKs, documents and other files in the Download folder.';

  @override
  String get installPackagesPermission => 'Install Packages (APK)';

  @override
  String get installPackagesDescription =>
      'This permission is needed to open and install APK files through Package Installer.';

  @override
  String get localNetworkPermission => 'Local Network';

  @override
  String get localNetworkDescription =>
      'Allows access to local network to browse SMB/NAS on the same network.';

  @override
  String get notificationsPermission => 'Notifications (Optional)';

  @override
  String get notificationsDescription =>
      'Enable notifications to receive playback updates and background tasks.';

  @override
  String get grantAllPermissions => 'Grant All Permissions';

  @override
  String get grantingPermissions => 'Granting permissions...';

  @override
  String get enterApp => 'Enter App';

  @override
  String get skipEnterApp => 'Skip, Enter App';

  @override
  String get granted => 'Granted';

  @override
  String get grantPermission => 'Grant Permission';

  // Home screen
  @override
  String get welcomeToFileManager => 'Welcome to CB File Hub';

  @override
  String get welcomeDescription => 'Your powerful file management companion';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get browseFiles => 'Browse Files';

  @override
  String get browseFilesDescription => 'Explore your local files and folders';

  @override
  String get manageMedia => 'Manage Media';

  @override
  String get manageMediaDescription => 'View images and videos in gallery';

  @override
  String get tagFiles => 'Tag Files';

  @override
  String get tagFilesDescription => 'Organize files with smart tags';

  @override
  String get networkAccess => 'Network Access';

  @override
  String get networkAccessDescription => 'Browse network drives and shares';

  @override
  String get keyFeatures => 'Key Features';

  @override
  String get fileManagement => 'File Management';

  @override
  String get fileManagementDescription =>
      'Browse and organize your files with ease';

  @override
  String get smartTagging => 'Smart Tagging';

  @override
  String get smartTaggingDescription => 'Tag files for lightning-fast search';

  @override
  String get mediaGallery => 'Media Gallery';

  @override
  String get mediaGalleryDescription =>
      'Beautiful gallery for images and videos';

  @override
  String get networkSupport => 'Network Support';

  @override
  String get networkSupportDescription => 'Seamless access to network drives';

  // Settings screen
  @override
  String get interface => 'Interface';

  @override
  String get selectInterfaceTheme => 'Select interface and favorite colors';

  @override
  String get chooseInterface => 'Choose Interface';

  @override
  String get interfaceDescription => 'Various colors and styles';

  @override
  String get showFileTags => 'Show File Tags';

  @override
  String get showFileTagsDescription =>
      'Display file tags outside file list in all view modes';

  @override
  String get showFileTagsToggle => 'Show file tags';

  @override
  String get showFileTagsToggleDescription =>
      'Enable/disable showing tags outside file list';

  @override
  String get rememberTabWorkspace => 'Remember tab workspace';

  @override
  String get rememberTabWorkspaceDescription =>
      'Restore last opened tab and keep drawer collapse state per tab.';

  @override
  String get cacheManagement => 'Cache Management';

  @override
  String get cacheManagementDescription => 'Clear cache data to free up memory';

  @override
  String get cacheFolder => 'Cache folder:';

  @override
  String get networkThumbnails => 'Network thumbnails:';

  @override
  String get videoThumbnailsCache => 'Video thumbnails:';

  @override
  String get tempFiles => 'Temp files:';

  @override
  String get notInitialized => 'Not initialized';

  @override
  String get refreshCacheInfo => 'Refresh';

  @override
  String get cacheInfoUpdated => 'Cache info updated';

  @override
  String get clearVideoThumbnailsCache => 'Clear video thumbnails cache';

  @override
  String get clearVideoThumbnailsDescription =>
      'Clear generated video thumbnails';

  @override
  String get clearNetworkThumbnailsCache =>
      'Clear SMB/network thumbnails cache';

  @override
  String get clearNetworkThumbnailsDescription =>
      'Clear generated network thumbnails';

  @override
  String get clearTempFilesCache => 'Clear temp files';

  @override
  String get clearTempFilesDescription =>
      'Clear temp files from network shares';

  @override
  String get clearAllCache => 'Clear all cache';

  @override
  String get clearAllCacheDescription => 'Clear all cache data';

  @override
  String get videoCacheCleared => 'Video thumbnails cache cleared';

  @override
  String get networkCacheCleared => 'Network thumbnails cache cleared';

  @override
  String get tempFilesCleared => 'Temp files cleared';

  @override
  String get allCacheCleared => 'All cache data cleared';

  @override
  String get errorClearingCache => 'Error: ';

  // Clipboard actions
  @override
  String copiedToClipboard(String name) => 'Copied "$name" to clipboard';
  @override
  String cutToClipboard(String name) => 'Cut "$name" to clipboard';
  @override
  String get pasting => 'Pasting...';

  // Rename dialogs
  @override
  String get renameFileTitle => 'Rename File';
  @override
  String get renameFolderTitle => 'Rename Folder';
  @override
  String currentNameLabel(String name) => 'Current name: $name';
  @override
  String get newNameLabel => 'New name';
  @override
  String renamedFileTo(String newName) => 'Renamed file to "$newName"';
  @override
  String renamedFolderTo(String newName) => 'Renamed folder to "$newName"';

  // Downloads
  @override
  String downloadedTo(String location) => 'Downloaded to $location';
  @override
  String downloadFailed(String error) => 'Download failed: $error';

  // Folder / Trash
  @override
  String get items => 'items';

  @override
  String get files => 'files';

  @override
  String get deleteTitle => 'Delete';

  @override
  String get permanentDeleteTitle => 'Permanent Delete';

  @override
  String confirmDeletePermanent(String name) =>
      'Are you sure you want to permanently delete "$name"? This action cannot be undone.';

  @override
  String confirmDeletePermanentMultiple(int count) =>
      'Are you sure you want to permanently delete $count items? This action cannot be undone.';

  @override
  String movedToTrash(String name) => '$name moved to trash';
  @override
  String moveItemsToTrashConfirmation(int count, String itemType) =>
      'Move $count $itemType to trash?';
  @override
  String get moveItemsToTrashDescription =>
      'These items will be moved to the trash bin. You can restore them later if needed.';
  @override
  String get clearFilter => 'Clear Filter';
  @override
  String filteredBy(String filter) => 'Filtered by: $filter';
  @override
  String noFilesMatchFilter(String filter) =>
      'No files match the filter "$filter"';

  // Trash / Recycle Bin screen
  @override
  String get emptyTrash => 'Empty Trash';
  @override
  String get emptyTrashConfirm =>
      'Are you sure you want to permanently delete all items in the trash? This action cannot be undone.';
  @override
  String get emptyTrashButton => 'EMPTY TRASH';
  @override
  String permanentlyDeleteItemsTitle(int count) =>
      'Permanently Delete $count items?';
  @override
  String get confirmPermanentlyDeleteThese =>
      'This action cannot be undone. Are you sure you want to permanently delete these items?';
  @override
  String itemRestoredSuccess(String name) => '$name restored successfully';
  @override
  String failedToRestore(String name) => 'Failed to restore $name';
  @override
  String errorRestoringItemWithError(String error) =>
      'Error restoring item: $error';
  @override
  String itemPermanentlyDeleted(String name) => '$name permanently deleted';
  @override
  String failedToDelete(String name) => 'Failed to delete $name';
  @override
  String failedToDeleteFilesCount(int count) =>
      'Failed to delete $count file${count == 1 ? '' : 's'}';
  @override
  String failedToDeleteItemsCount(int count) =>
      'Failed to delete $count item${count == 1 ? '' : 's'}';
  @override
  String errorDeletingItemWithError(String error) =>
      'Error deleting item: $error';
  @override
  String get trashEmptiedSuccess => 'Trash emptied successfully';
  @override
  String get failedToEmptyTrash => 'Failed to empty trash';
  @override
  String errorEmptyingTrashWithError(String error) =>
      'Error emptying trash: $error';
  @override
  String itemsRestoredSuccess(int count) =>
      '$count items restored successfully';
  @override
  String itemsRestoredWithFailures(int success, int failed) =>
      '$success items restored successfully, $failed failed';
  @override
  String itemsPermanentlyDeletedCount(int count) =>
      '$count items permanently deleted';
  @override
  String itemsDeletedWithFailures(int success, int failed) =>
      '$success items permanently deleted, $failed failed';
  @override
  String errorRestoringItemsWithError(String error) =>
      'Error restoring items: $error';
  @override
  String errorDeletingItemsWithError(String error) =>
      'Error deleting items: $error';
  @override
  String errorDeletingFilesWithError(String error) =>
      'Error deleting files: $error';
  @override
  String errorOpeningRecycleBinWithError(String error) =>
      'Error opening Recycle Bin: $error';
  @override
  String get restoreSelected => 'Restore Selected';
  @override
  String get deleteSelected => 'Delete Selected';
  @override
  String get selectItems => 'Select Items';
  @override
  String get openRecycleBin => 'Open Recycle Bin';
  @override
  String get emptyTrashTooltip => 'Empty Trash';
  @override
  String get trashIsEmpty => 'Trash is empty';
  @override
  String get itemsDeletedWillAppearHere => 'Items you delete will appear here';
  @override
  String originalLocation(String path) => 'Original location: $path';
  @override
  String deletedAt(String date, String size) => 'Deleted: $date • $size';
  @override
  String get systemLabel => 'System';
  @override
  String errorLoadingTrashItemsWithError(String error) =>
      'Error loading trash items: $error';
  @override
  String get restoreTooltip => 'Restore';
  @override
  String get deletePermanentlyTooltip => 'Delete permanently';

  // Misc helper labels
  @override
  String get networkFile => 'Network file';
  @override
  String tagCount(int count) => '$count tags';

  // Generic errors
  @override
  String errorGettingFolderProperties(String error) =>
      'Error getting folder properties: $error';
  @override
  String errorSavingTags(String error) => 'Error saving tags: $error';
  @override
  String errorCreatingFolder(String error) => 'Error creating folder: $error';
  @override
  String get pathNotAccessible => 'Path does not exist or cannot be accessed';

  // UI labels
  @override
  String get noStorageLocationsFound => 'No storage locations found';
  @override
  String get menuPinningOnlyLargeScreens =>
      'Menu pinning is only available on larger screens';

  @override
  String get pinMenu => 'Pin menu';

  @override
  String get unpinMenu => 'Unpin menu';

  @override
  String get pinnedSection => 'Pinned';

  @override
  String get pinToSidebar => 'Pin to Sidebar';

  @override
  String get unpinFromSidebar => 'Unpin from Sidebar';

  @override
  String get pinnedToSidebar => 'Pinned to sidebar';

  @override
  String get removedFromSidebar => 'Removed from sidebar';

  @override
  String get exitApplicationTitle => 'Exit Application?';
  @override
  String moveToTrashConfirmMessage(String name) =>
      'Are you sure you want to move "$name" to trash?';
  @override
  String get exitApplicationConfirm =>
      'Are you sure you want to exit the application?';
  @override
  String itemsSelected(int count) => '$count selected';
  @override
  String get noActiveTab => 'No active tab';
  @override
  String get masonryLayoutName => 'Masonry layout (Pinterest)';
  @override
  String get undo => 'Undo';
  @override
  String errorWithMessage(String message) => 'Error: $message';

  @override
  String get processing => 'Processing...';

  @override
  String get deletingFiles => 'Deleting files...';

  @override
  String get deletingItems => 'Deleting items...';

  @override
  String get movingItemsToTrash => 'Moving items to trash...';

  @override
  String get done => 'Done';

  @override
  String get regenerateThumbnailsWithNewPosition =>
      'Regenerate thumbnails with new position';

  @override
  String get thumbnailPositionUpdated =>
      'Cleared cache and will regenerate thumbnails at ';

  @override
  String get fileTagsEnabled => 'File tags display enabled';

  @override
  String get fileTagsDisabled => 'File tags display disabled';

  // System screen router
  @override
  String get unknownSystemPath => 'Unknown system path';

  @override
  String get ftpConnectionRequired => 'FTP Connection Required';

  @override
  String get ftpConnectionDescription =>
      'You need to connect to an FTP server first.';

  @override
  String get goToFtpConnections => 'Go to FTP Connections';

  @override
  String get cannotOpenNetworkPath => 'Cannot open network path';

  @override
  String get goBack => 'Go Back';

  @override
  String get tagPrefix => 'Tag';

  // Network browsing
  @override
  String get ftpConnections => 'FTP Connections';

  @override
  String get smbNetwork => 'SMB Network';

  @override
  String get refreshData => 'Refresh';

  @override
  String get addConnection => 'Add Connection';

  @override
  String get noFtpConnections => 'No FTP connections.';

  @override
  String get activeConnections => 'Active connections';

  @override
  String get savedConnections => 'Saved connections';

  @override
  String get connecting => 'Connecting';

  @override
  String get connect => 'Connect';

  @override
  String get unknown => 'Unknown';

  @override
  String get connectionError => 'Connection error';

  @override
  String get loadCredentialsError => 'Error loading saved credentials';

  @override
  String get networkScanFailed => 'Network scan failed';

  @override
  String get smbVersionUnknown => 'Unknown';

  @override
  String get connectionInfoUnavailable => 'Connection info unavailable';

  @override
  String get networkSettingsOpened => 'Network settings opened';

  @override
  String get cannotOpenNetworkSettings =>
      'Cannot open network settings, please open manually';

  @override
  String get networkDiscoveryDisabled => 'Network discovery may not be enabled';

  @override
  String get networkDiscoveryDescription =>
      'Enable network discovery in Windows settings to scan for SMB servers';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get activeConnectionsTitle => 'Active Connections';

  @override
  String get activeConnectionsDescription => 'SMB servers you are connected to';

  @override
  String get discoveredSmbServers => 'Discovered SMB Servers';

  @override
  String get discoveredSmbServersDescription =>
      'Servers discovered on your local network';

  @override
  String get noActiveSmbConnections => 'No active SMB connections';

  @override
  String get connectToSmbServer => 'Connect to an SMB server to see it here';

  @override
  String get connected => 'Connected';

  @override
  String get openConnection => 'Open Connection';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get scanningForSmbServers => 'Scanning for SMB servers...';

  @override
  String get devicesWillAppear =>
      'Devices will appear here as they are discovered';

  @override
  String get scanningMayTakeTime => 'This may take a few moments';

  @override
  String get noSmbServersFound => 'No SMB servers found';

  @override
  String get tryScanningAgain =>
      'Try scanning again or check your network settings';

  @override
  String get scanAgain => 'Scan Again';

  @override
  String get readyToScan => 'Ready to scan';

  @override
  String get clickRefreshToScan =>
      'Click the refresh button to start scanning for SMB servers';

  @override
  String get startScan => 'Start Scan';

  @override
  String get foundDevices => 'Found';

  @override
  String get scanning => 'Scanning...';

  @override
  String get scanComplete => 'Scan Complete';

  @override
  String get smbVersion => 'SMB Version';

  @override
  String get netbios => 'NetBIOS';

  // Network - additional
  @override
  String get selectAll => 'Select All';
  @override
  String get unknownError => 'An unknown error occurred.';
  @override
  String get networkConnections => 'Network Connections';
  @override
  String get availableServices => 'Available Services';
  @override
  String get noActiveNetworkConnections => 'No active network connections';
  @override
  String get useAddButtonToAddConnection =>
      'Use the (+) button to add a new connection';
  @override
  String get unknownConnection => 'Unknown Connection';
  @override
  String serviceTypeConnection(String serviceName) => '$serviceName Connection';
  @override
  String get noServicesAvailable => 'No services available';
  @override
  String get webdavConnections => 'WebDAV Connections';
  @override
  String errorOpeningTab(String tabName, String error) =>
      'Error opening tab for $tabName: $error';
  @override
  String connectToServiceServer(String serviceName) =>
      'Connect to $serviceName Server';
  @override
  String get serviceType => 'Service Type';
  @override
  String get host => 'Host';
  @override
  String get deleteSavedConnection => 'Delete Saved Connection';
  @override
  String get username => 'Username';
  @override
  String get password => 'Password';
  @override
  String get portOptional => 'Port (optional)';
  @override
  String get useSslTls => 'Use SSL/TLS';
  @override
  String get basePathOptional => 'Base Path (optional)';
  @override
  String get basePathHint => 'e.g., /webdav';
  @override
  String get domainOptional => 'Domain (optional)';
  @override
  String get saveCredentials => 'Save credentials';
  @override
  String get saveCredentialsDescription =>
      'Store login details for future connections';
  @override
  String get deleteSavedConnectionTitle => 'Delete Saved Connection?';
  @override
  String deleteSavedConnectionConfirm(String host) =>
      'Are you sure you want to delete the saved connection for "$host"?';
  @override
  String connectionDeleted(String host) => 'Connection for "$host" deleted.';
  @override
  String connectionNotFoundToDelete(String host) =>
      'Could not find connection for "$host" to delete.';
  @override
  String get errorDeletingConnection => 'Error deleting connection';
  @override
  String connectionFailed(String error) => 'Connection failed: $error';
  @override
  String get networkConnection => 'Network Connection';
  @override
  String get notConnected => 'Not connected';
  @override
  String get refreshSmbVersionInfo => 'Refresh SMB version info';
  @override
  String shareLabel(String sharePath) => 'Share: $sharePath';
  @override
  String get rootShare => 'Root share';
  @override
  String foundDevicesCount(int count) =>
      'Found $count device${count == 1 ? '' : 's'}';
  @override
  String get noWebdavConnections => 'No WebDAV connections.';
  @override
  String get addConnectionOrSampleToStart =>
      'Add a new connection or sample to get started.';
  @override
  String get addSample => 'Add Sample';
  @override
  String get editWebdavConnection => 'Edit WebDAV Connection';
  @override
  String get update => 'Update';
  @override
  String get connectionUpdatedSuccess => 'Connection updated successfully';
  @override
  String get failedToUpdateConnection => 'Failed to update connection';
  @override
  String get deleteConnection => 'Delete Connection';
  @override
  String deleteConnectionConfirm(String host) =>
      'Are you sure you want to delete the connection to "$host"?';
  @override
  String get connectionDeletedSuccess => 'Connection deleted successfully';
  @override
  String get failedToDeleteConnection => 'Failed to delete connection';
  @override
  String get addSampleWebdavConnection => 'Add Sample WebDAV Connection';
  @override
  String get sampleConnectionAddedSuccess =>
      'Sample connection added successfully';
  @override
  String get failedToAddSampleConnection => 'Failed to add sample connection';
  @override
  String lastConnected(String dateStr) => 'Last connected: $dateStr';
  @override
  String get editConnection => 'Edit Connection';
  @override
  String get closeConnection => 'Close Connection';
  @override
  String get retry => 'Retry';
  @override
  String get networkErrorPersistsHint =>
      'If this error persists, check your network connection and the server status.';
  @override
  String get pleaseEnterHost => 'Please enter a host';
  @override
  String get pleaseEnterPort => 'Please enter a port';
  @override
  String get pleaseEnterValidPort => 'Please enter a valid port number';
  @override
  String get connectionMode => 'Connection Mode:';
  @override
  String get passive => 'Passive';
  @override
  String get active => 'Active';
  @override
  String get port => 'Port';
  @override
  String get basePath => 'Base Path';

  // Drawer menu items
  @override
  String get networksMenu => 'Networks';

  @override
  String get networkTab => 'Network';

  @override
  String get about => 'About';

  // Tab manager
  @override
  String get newTabButton => 'New Tab';

  @override
  String get openNewTabToStart => 'Open a new tab to get started';

  @override
  String get tabManager => 'Tab Manager';

  @override
  String get openTabs => 'Open Tabs';

  @override
  String get noTabsOpen => 'No tabs open';

  @override
  String get closeAllTabs => 'Close All Tabs';

  @override
  String get activeTab => 'Active';

  @override
  String get closeTab => 'Close tab';

  @override
  String get addNewTab => 'Add new tab';

  // Desktop windows (tabbed browsing)
  @override
  String get newWindow => 'New window';

  @override
  String get moveTabToNewWindow => 'Move tab to new window';

  @override
  String get moveTabToWindow => 'Move tab to window...';

  @override
  String get mergeWindowIntoThis => 'Merge window into this...';

  @override
  String get selectWindow => 'Select window';

  @override
  String get noOtherWindows => 'No other windows';

  // Home screen
  @override
  String get welcomeTitle => 'Welcome to CB File Hub';

  @override
  String get welcomeSubtitle => 'Your powerful file management companion';

  @override
  String get quickActionsTip =>
      'Tip: Use quick actions below to get started quickly';

  @override
  String get quickActionsHome => 'Quick Actions';

  @override
  String get startHere => 'Start here';

  @override
  String get newTabAction => 'New Tab';

  @override
  String get newTabActionDesc => 'Open a new file browser tab';

  @override
  String get tagsAction => 'Tags';

  @override
  String get tagsActionDesc => 'Organize with smart tags';

  @override
  String get imageGalleryTab => 'Image Gallery';

  @override
  String get videoGalleryTab => 'Video Gallery';

  @override
  String get drivesTab => 'Drives';

  @override
  String get browseTab => 'Browse';

  @override
  String get documentsTab => 'Documents';

  @override
  String get homeTab => 'Home';

  @override
  String get internalStorage => 'Internal Storage';

  @override
  String get storagePrefix => 'Storage';

  @override
  String get rootFolder => 'Root';

  // Video Hub
  @override
  String get videoHub => 'Video Hub';

  @override
  String get manageYourVideos => 'Manage your videos';

  @override
  String get videos => 'Videos';

  @override
  String get videoActions => 'Video Actions';

  @override
  String get allVideos => 'All Videos';

  @override
  String get browseAllYourVideos => 'Browse all your videos';

  @override
  String get videosFolder => 'Videos folder';

  @override
  String get openFileManager => 'Open file manager';

  @override
  String get videoStatistics => 'Video Statistics';

  @override
  String get totalVideos => 'Total Videos';

  // Gallery Hub
  @override
  String get galleryHub => 'Gallery Hub';

  @override
  String get managePhotosAndAlbums => 'Manage your photos and albums';

  @override
  String get images => 'Images';

  @override
  String get galleryActions => 'Gallery Actions';

  @override
  String get quickAccess => 'Quick Access';

  @override
  String get browseAllYourPictures => 'Browse all your pictures';

  @override
  String get browseAllYourPhotos => 'Browse all your photos';

  @override
  String get organizeInAlbums => 'Organize in albums';

  @override
  String get picturesFolder => 'Pictures folder';

  @override
  String get photosFromCamera => 'Photos from camera';

  @override
  String get downloadedFiles => 'Downloaded files';

  @override
  String get downloadedImages => 'Downloaded images';

  @override
  String get featuredAlbums => 'Featured Albums';

  @override
  String get personalized => 'Personalized';

  @override
  String get configureFeaturedAlbums => 'Configure Featured Albums';

  @override
  String get noFeaturedAlbums => 'No Featured Albums';

  @override
  String get createSomeAlbumsToSeeThemFeaturedHere =>
      'Create some albums to see them featured here';

  @override
  String get removeFromFeatured => 'Remove from Featured';

  @override
  String get galleryStatistics => 'Gallery Statistics';

  @override
  String get totalImages => 'Total Images';

  @override
  String get albums => 'Albums';

  @override
  String get allImages => 'All Images';

  @override
  String get camera => 'Camera';

  @override
  String get downloads => 'Downloads';

  @override
  String get recent => 'Recent';

  @override
  String get folders => 'Folders';

  // Video player screenshot
  @override
  String get takeScreenshot => 'Take Screenshot';

  @override
  String get screenshotSaved => 'Screenshot saved';

  @override
  String get screenshotSavedAt => 'Screenshot saved at';

  @override
  String get screenshotFailed => 'Failed to save screenshot';

  @override
  String get screenshotSavedToFolder =>
      'Screenshot saved to Screenshots folder';

  @override
  String get openScreenshotFolder => 'Open folder';

  @override
  String get viewScreenshot => 'View';

  @override
  String get screenshotNotAvailableVlc => 'Screenshot not available';

  @override
  String get screenshotNotAvailableVlcMessage =>
      'Screenshot is not available with VLC player.\nPlease switch to Media Kit player in settings.';

  @override
  String get screenshotFileNotFound => 'Image file not found';

  @override
  String get screenshotCannotOpenTab =>
      'Cannot open folder tab in this context';

  @override
  String get screenshotErrorOpeningFolder => 'Error opening folder';

  @override
  String get closeAction => 'Close';

  // Video library
  @override
  String get videoLibrary => 'Video Library';

  @override
  String get videoLibraries => 'Video Libraries';

  @override
  String get createVideoLibrary => 'Create Video Library';

  @override
  String get editVideoLibrary => 'Edit Video Library';

  @override
  String get deleteVideoLibrary => 'Delete Video Library';

  @override
  String get addVideoSource => 'Add Video Source';

  @override
  String get removeVideoSource => 'Remove Source';

  @override
  String get videoSources => 'Video Sources';

  @override
  String get noVideoSources => 'No video sources added yet';

  @override
  String get filterByTags => 'Filter by Tags';

  @override
  String get clearTagFilter => 'Clear Filter';

  @override
  String get recentVideos => 'Recent Videos';

  @override
  String get videoHubTitle => 'Video Hub';

  @override
  String get videoHubWelcome => 'Manage your video libraries';

  @override
  String get manageVideoLibraries => 'Manage Video Libraries';

  @override
  String get videoCount => 'Video Count';

  @override
  String get scanForVideos => 'Scan for Videos';

  @override
  String get rescanLibrary => 'Rescan Library';

  @override
  String deleteVideoLibraryConfirmation(String name) =>
      'Delete video library "$name"?';

  @override
  String get libraryDeletedSuccessfully => 'Library deleted successfully';

  @override
  String get sourceAdded => 'Source added successfully';

  @override
  String get sourceRemoved => 'Source removed successfully';

  @override
  String get selectVideoSource => 'Select Video Source Folder';

  @override
  String get videoLibrarySettings => 'Video Library Settings';

  @override
  String get manageVideoSources => 'Manage Video Sources';

  @override
  String get videoExtensions => 'Video Extensions';

  @override
  String get includeSubdirectories => 'Include Subdirectories';

  @override
  String get noVideosInLibrary => 'No videos in this library';

  @override
  String get libraryCreatedSuccessfully => 'Library created successfully';

  @override
  String videoLibraryCount(int count) => '$count libraries';

  // Streaming and download dialogs
  @override
  String openFileTypeFile(String fileType) => 'Open $fileType File';
  @override
  String streamDownloadPrompt(String fileType) =>
      '$fileType file type is not directly supported for streaming. Do you want to download it to your device?';
  @override
  String get downloadingFile => 'Downloading file...';
  @override
  String get fileDownloadedSuccess => 'File downloaded successfully';
  @override
  String get errorDownloadingFile => 'Error downloading file';
  @override
  String get errorTitle => 'Error';
  @override
  String get mediaPlaybackError => 'Media playback error';
  @override
  String mediaPlaybackErrorVlcContent(String error) =>
      'Cannot play file with VLC Direct SMB:\n\n$error\n\nPlease check:\n• SMB connection\n• File path\n• File access permission';
  @override
  String mediaPlaybackErrorNativeContent(String error) =>
      'Cannot play file with Native VLC Direct SMB:\n\n$error\n\nPlease check:\n• SMB connection\n• File path\n• File access permission\n• Native SMB client availability';
  @override
  String get chooseAnotherApp => 'Choose another app...';
  @override
  String get folderProperties => 'Folder Properties';
  @override
  String get createNewFolder => 'Create New Folder';
  @override
  String get createNewFile => 'Create New File';
  @override
  String get folderPropertyPath => 'Path';
  @override
  String get folderPropertyCreated => 'Created';
  @override
  String get folderPropertyContent => 'Content';
  @override
  String get folderPropertySizeDirectChildren => 'Size (direct children)';
  @override
  String get networkServiceNotAvailable => 'Network service not available';
  @override
  String get folderNameLabel => 'Folder Name';
  @override
  String get fileNameLabel => 'File Name';
  @override
  String errorCreatingFile(String error) => 'Error creating file: $error';
}
