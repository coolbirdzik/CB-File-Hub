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
  @override
  String get thirdPartyApps => 'Third-party apps';
  @override
  String get configureContextMenu => 'Configure context menu';
  @override
  String get contextMenuLayout => 'Context menu layout';
  @override
  String get contextMenuLayoutDescription =>
      'Reorder or hide commands shown when you right-click';
  @override
  String get contextMenuLayoutHint =>
      'Drag commands to reorder them. Hidden commands remain available here.';
  @override
  String get contextMenuForFiles => 'Files';
  @override
  String get contextMenuForFolders => 'Folders';
  @override
  String get contextMenuForMultipleItems => 'Multiple items';
  @override
  String get resetContextMenuLayout => 'Reset layout';
  @override
  String get contextMenuLayoutReset => 'Context menu layout was reset';

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
  String get setCoolBirdAsDefaultForArchives =>
      'Set CB File Hub as default for archive files';
  @override
  String get setCoolBirdAsDefaultForArchivesSuccess =>
      'CB File Hub is now the default for archive files.';
  @override
  String get setCoolBirdAsDefaultForArchivesFailed =>
      'Could not set CB File Hub as the default for archive files.';
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
  String get manage => 'Manage';

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
  String get viewModeColumns => 'Columns';

  @override
  String get viewModeTree => 'Tree';

  @override
  String get viewModeTiles => 'Tiles';

  @override
  String get previewPaneTitle => 'Preview';

  @override
  String get previewSelectFile => 'Select a file to preview';

  @override
  String get previewNotSupported => 'Preview not available for this file type';

  @override
  String get archiveSectionTitle => 'Archive';

  @override
  String get archiveBrowseTitle => 'Browse contents';

  @override
  String get archiveExtractHere => 'Extract here';

  @override
  String get archiveExtractTo => 'Extract to…';

  @override
  String get archiveExtractToTitle => 'Choose extraction folder';

  @override
  String get archiveExtractAll => 'Extract all';

  @override
  String get archiveExtracting => 'Extracting archive…';

  @override
  String get archiveExtractComplete => 'Archive extracted';

  @override
  String archiveExtractFailed(String error) => 'Extraction failed: $error';

  @override
  String get archiveEmpty => 'This archive is empty';

  @override
  String archivePreviewSummary(int count) => '$count item(s)';

  @override
  String archivePreviewMore(int count) => '… and $count more';

  @override
  String get previewUnavailable => 'Preview not available';

  @override
  String get previewTextTruncated => 'Showing partial content';

  @override
  String get previewTextTooLarge => 'File is too large to preview';

  @override
  String get showPreview => 'Show preview';

  @override
  String get hidePreview => 'Hide preview';

  // Column names
  @override
  String get columnName => 'Name';

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

  @override
  String get columnDateAccessed => 'Date Accessed';

  @override
  String get columnExtension => 'Extension';

  @override
  String get columnPath => 'Path';

  @override
  String get columnTags => 'Tags';

  @override
  String get columnDimensions => 'Dimensions';

  @override
  String get columnDuration => 'Duration';

  @override
  String get columnItemCount => 'Item Count';

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

  @override
  String get columnDateAccessedDescription =>
      'Display date and time file was last accessed';

  @override
  String get columnExtensionDescription =>
      'Display file extension (e.g. .mp4, .docx)';

  @override
  String get columnPathDescription => 'Display relative file path';

  @override
  String get columnTagsDescription => 'Display file tags';

  @override
  String get columnDimensionsDescription =>
      'Display image/video dimensions (width x height)';

  @override
  String get columnDurationDescription =>
      'Display media duration for video/audio files';

  @override
  String get columnItemCountDescription =>
      'Display number of items inside folders';

  // Column visibility dialog
  @override
  String get columnVisibilityInstructions =>
      'Select the columns you want to display in details view. '
      'The "Name" column is always displayed and cannot be disabled.';

  // List field visibility
  @override
  String get listFieldVisibilityTitle => 'Customize List Fields';

  @override
  String get listFieldVisibilityInstructions =>
      'Select the fields you want to display in list view.';

  // Metadata format strings
  @override
  String dimensionsFormat(int width, int height) => '$width \u00D7 $height';

  @override
  String itemCountFormat(int count) => '$count items';

  // Grid size dialog
  @override
  String gridSizeLabel(int count) => 'Item size level: $count';

  @override
  String get gridSizeInstructions => 'Move the slider to adjust the item size';

  // More options menu
  @override
  String get selectMultipleFiles => 'Select multiple files';

  @override
  String get selectMultipleTags => 'Select multiple tags';

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

  // File template type names
  @override
  String get fileTypeMarkdown => 'Markdown';
  @override
  String get fileTypeJson => 'JSON File';
  @override
  String get fileTypeHtml => 'HTML Document';
  @override
  String get fileTypeCss => 'CSS Stylesheet';
  @override
  String get fileTypeDart => 'Dart File';
  @override
  String get fileTypePython => 'Python Script';
  @override
  String get fileTypeJavaScript => 'JavaScript';
  @override
  String get fileTypeTypeScript => 'TypeScript';
  @override
  String get fileTypeJava => 'Java File';
  @override
  String get fileTypeCpp => 'C++ File';
  @override
  String get fileTypeC => 'C File';
  @override
  String get fileTypeGo => 'Go File';
  @override
  String get fileTypeRust => 'Rust File';
  @override
  String get fileTypeXml => 'XML File';
  @override
  String get fileTypeYaml => 'YAML File';
  @override
  String get fileTypeShell => 'Shell Script';
  @override
  String get fileTypeCsv => 'CSV Spreadsheet';
  @override
  String get fileTypeLibreDoc => 'LibreOffice Document';
  @override
  String get fileTypeLibreSheet => 'LibreOffice Spreadsheet';
  @override
  String get fileTypeLibrePresentation => 'LibreOffice Presentation';
  @override
  String get fileTypeLibreDraw => 'LibreOffice Drawing';
  @override
  String get fileTypeLibreChart => 'LibreOffice Chart';
  @override
  String get fileTypeLibreFormula => 'LibreOffice Formula';
  @override
  String get fileTypeWpsDoc => 'WPS Document';
  @override
  String get fileTypeWpsSheet => 'WPS Spreadsheet';
  @override
  String get fileTypeWpsPresentation => 'WPS Presentation';
  @override
  String get fileTypeGoogleDoc => 'Google Doc';
  @override
  String get fileTypeGoogleSheet => 'Google Sheet';
  @override
  String get fileTypeGoogleSlides => 'Google Slides';
  @override
  String get fileTypeTar => 'TAR Archive';
  @override
  String get fileTypeGzip => 'GZIP Archive';

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
  String get accentColor => 'Accent color';
  @override
  String currentAccentColor(String name) => 'Current accent: $name';
  @override
  String get fontColor => 'Font color';
  @override
  String currentFontColor(String name) => 'Current font color: $name';
  @override
  String get uiFont => 'Font family';
  @override
  String currentUiFont(String name) => 'Current font: $name';
  @override
  String get uiFontUnicodeHint =>
      'Free Unicode fonts (Vietnamese + Latin Extended). Extra fonts download once and cache locally.';
  @override
  String get backdropMode => 'Backdrop mode';
  @override
  String get backdropModeDynamic => 'Dynamic';
  @override
  String get backdropModeWallpaper => 'Wallpaper';
  @override
  String get backdropModeDynamicDescription =>
      'Using system dynamic acrylic backdrop.';
  @override
  String get backdropModeWallpaperDescription =>
      'Using system wallpaper as backdrop.';
  @override
  String get noSystemWallpaperDetected => 'No system wallpaper detected';
  @override
  String get customBackdropImage => 'Custom';
  @override
  String get backdropImageNotFound => 'Image not found';
  @override
  String get desktopAcrylicStrength => 'Desktop acrylic strength';
  @override
  String desktopAcrylicStrengthDescription(int percentage) =>
      'Adjust blur and tint intensity for desktop backdrop ($percentage%).';
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
  @override
  String get failedToCreateAlbum => 'Failed to create album';
  @override
  String get failedToUpdateAlbum => 'Failed to update album';

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
  String get treeViewMode => 'Tree Mode';
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
  String get setThumbnail => 'Set Thumbnail';
  @override
  String get manageHierarchy => 'Manage Hierarchy';
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
  String get selectFilesToRemoveTags => 'Please select files to remove tags';
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
  @override
  String get tagManagementInfoTitle => 'Tag management info';
  @override
  String get tagManagementInfoDescription =>
      'This screen lets you manage tags for files and folders.\n\n'
      '• View all tags\n'
      '• Search tags\n'
      '• Sort tags by name or popularity\n'
      '• View files assigned to a tag';
  @override
  String removeTagsFromFilesTitle(int count) => 'Remove tags from $count files';
  @override
  String get loadingTags => 'Loading tags...';
  @override
  String get noCommonTagsAcrossSelectedFiles =>
      'There are no common tags across the selected files';
  @override
  String removeTagsSuccess(int removedTagCount, int fileCount) =>
      'Removed $removedTagCount tags from $fileCount files';
  @override
  String removeTagsError(String error) => 'Error removing tags: $error';
  @override
  String batchTagProcessingError(String error) =>
      'Error processing tags: $error';
  @override
  String searchError(String error) => 'Search error: $error';

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
  String get syncToCloudSuccess => 'Synced to cloud successfully';
  @override
  String get syncToCloudFailed => 'Failed to sync to cloud';
  @override
  String get syncFromCloudSuccess => 'Synced from cloud successfully';
  @override
  String get syncFromCloudFailed => 'Failed to sync from cloud';
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
  @override
  String get backupAndRestore => 'Backup & Restore';
  @override
  String get backupRestoreHint =>
      'Backup tags and preferences to a .db file (fast, scalable), or export preferences to JSON (human-readable).';
  @override
  String get exportSqlite => 'Export SQLite';
  @override
  String get exportSqliteDesc => 'Fast backup (.db) — tags + preferences';
  @override
  String get exportJson => 'Export JSON';
  @override
  String get exportJsonDesc => 'Export preferences as readable JSON';
  @override
  String get importBackup => 'Import Backup';
  @override
  String get importBackupDesc => 'Auto-detects .db or .json file';
  @override
  String get exporting => 'Exporting...';
  @override
  String get importing => 'Importing...';
  @override
  String get sharedPreferences => 'SharedPreferences';
  @override
  String get sharedPreferencesDesc => 'View and clear app key-value settings';
  @override
  String get clearSharedPreferencesConfirm => 'Clear all SharedPreferences?';
  @override
  String get deleteKeyConfirm => 'Delete this key?';
  @override
  String get clear => 'Clear';
  @override
  String get sharedPreferencesCleared => 'SharedPreferences cleared.';
  @override
  String get deletedKey => 'Deleted: ';
  @override
  String get copied => 'Copied: ';
  @override
  String tagsImported(int count) => '$count tags imported';
  @override
  String settingsRestored(int count) => '$count settings restored';
  @override
  String get saveBackup => 'Save backup';
  @override
  String get exportPreferencesAsJson => 'Export preferences as JSON';
  @override
  String get sharedPreferencesKeyRemoved =>
      'Setting removed from SharedPreferences.';
  @override
  String get jsonCopiedToClipboard => 'JSON copied to clipboard';
  @override
  String get copyValue => 'Copy value';
  @override
  String get deleteKey => 'Delete key';
  @override
  String get copyJson => 'Copy JSON';
  @override
  String get viewJson => 'View JSON';
  @override
  String get clearAll => 'Clear all';

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
  String get seekSpeed => 'Seek speed';
  @override
  String get seekSpeedDescription =>
      'How fast the video skips when holding the seek key or long-pressing on mobile';
  @override
  String get seekSpeedSlow => 'Slow';
  @override
  String get seekSpeedMedium => 'Medium';
  @override
  String get seekSpeedFast => 'Fast';
  @override
  String get openVideoInNewWindow => 'Open videos in a separate window';
  @override
  String get openVideoInNewWindowDescription =>
      'Desktop only. Uses one separate in-app player window; opening another video replaces the current video in that window.';
  @override
  String get openVideoInNewWindowEnabled =>
      'Videos will open in a separate player window';
  @override
  String get openVideoInNewWindowDisabled =>
      'The video player will open in the current window';
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
  String get cropImage => 'Crop image';
  @override
  String get applyCrop => 'Apply';
  @override
  String get useOriginal => 'Use original';
  @override
  String get aspectFree => 'Free';
  @override
  String get tagGridCropRecommendation =>
      'Recommended for tag grid cards: 16:9, at least 1280 × 720 px';
  @override
  String get tagGridAspectPreset => '16:9 · Tag grid';
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
  @override
  String get viewModeFeatureComingSoon =>
      'View mode switching will be added later';
  @override
  String get cannotCreateFileInThisLocation =>
      'Cannot create a file in this location';

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
  String get globalSearchModeEnabled => 'Switched to subfolder search';

  @override
  String get localSearchModeEnabled => 'Switched to current folder search';

  @override
  String get globalSearchMode => 'Searching in subfolders (tap to switch)';

  @override
  String get localSearchMode => 'Searching current folder (tap to switch)';

  @override
  String get searchByFilename => 'Search by filename';

  @override
  String get searchByTags => 'Search by tags';

  @override
  String get searchMultipleTags => 'Search multiple tags';

  @override
  String get globalSearch => 'Subfolder search';

  @override
  String get searchByNameOrTag => 'Search by name or #tag';

  @override
  String get searchInSubfolders => 'Search in subfolders';

  @override
  String get featureNotImplemented => 'This feature will be added soon';

  @override
  String get searchInAllFolders => 'Search in current folder and subfolders';

  @override
  String get searchInCurrentFolder => 'Search in current folder only';

  @override
  String get searchShortcuts => 'Shortcuts';

  @override
  String get regexMode => 'Regex mode';

  @override
  String get regexModeEnabled => 'Regex mode enabled';

  @override
  String get regexModeDisabled => 'Regex mode disabled';

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
      'Click on the folder/globe icon to toggle between searching only the current folder and searching including subfolders.';

  @override
  String get regexSearchDesc =>
      'Enable regex mode ({ }) to match names with regular expressions.\n'
      'Basic examples:\n'
      '• Starts with "img_": ^img_.*\n'
      '• Ends with .mp4: .*\\.mp4\$\n'
      '• Contains "invoice": .*invoice.*\n'
      '• Exactly 4 digits: ^\\d{4}\$\n'
      '• Report with year: ^report_\\d{4}\\.pdf\$';

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
  String get fileThumbnailFit => 'File thumbnail display';

  @override
  String get fileThumbnailFitDescription =>
      'Choose whether file thumbnails fill the frame or show the full image';

  @override
  String get tagThumbnailFit => 'Tag thumbnail display';

  @override
  String get tagThumbnailFitDescription =>
      'Choose whether tag thumbnails show the full image or fill the frame';

  @override
  String get thumbnailFitContain => 'Show full image';

  @override
  String get thumbnailFitCover => 'Fill frame';

  @override
  String get rememberTabWorkspace => 'Remember tab workspace';

  @override
  String get rememberTabWorkspaceDescription =>
      'Restore last opened tab and keep drawer collapse state per tab.';

  @override
  String get tabInactiveThreshold => 'Tab inactive timeout';

  @override
  String get tabInactiveThresholdDescription =>
      'Auto-suspend a tab and release its caches after it has been left untouched for this duration. Set to "Off" to keep tabs always active.';

  @override
  String get tabInactiveThresholdDisabled => 'Off';

  @override
  String get tabInactiveThresholdMinutesValue => 'minutes';

  @override
  String get tabInactiveThresholdHoursValue => 'hours';

  @override
  String get cacheManagement => 'Cache Management';

  @override
  String get cacheManagementDescription => 'Clear cache data to free up memory';

  @override
  String get appDataManagement => 'App Data Management';

  @override
  String get appDataManagementDescription =>
      'Review and clear cached and stored app data';

  @override
  String get documentsData => 'Stored data';

  @override
  String get documentsDataDescription =>
      'Persistent files kept in Documents that survive cache cleanup';

  @override
  String get tagThumbnails => 'Tag thumbnails';

  @override
  String get tagThumbnailsDescription =>
      'Images you chose as tag thumbnails (extracted video frames)';

  @override
  String get clearTagThumbnails => 'Clear tag thumbnails';

  @override
  String get tagThumbnailsCleared => 'Tag thumbnails cleared';

  @override
  String get documentsRoot => 'Documents root';

  @override
  String get cacheFolder => 'Cache folder:';

  @override
  String get networkThumbnails => 'Network thumbnails:';

  @override
  String get videoThumbnailsCache => 'Video thumbnails:';

  @override
  String get tempFiles => 'Temp files:';

  @override
  String get videoLibraryCache => 'Video gallery cache:';

  @override
  String get clearVideoLibraryCache => 'Clear video gallery cache';

  @override
  String get videoLibraryCacheCleared => 'Video gallery cache cleared';

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
  @override
  String get allowFileExtensionRename => 'Allow editing file extensions';

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
  @override
  String get columnDateDeleted => 'Date Deleted';
  @override
  String get columnOriginalPath => 'Original Path';
  @override
  String get askCbAgentAboutThisFile => 'Ask CB Agent about this file';
  @override
  String get askCbAgentAboutThisFolder => 'Ask CB Agent about this folder';

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
  String get driveGroupFixed => 'This PC';
  @override
  String get driveGroupRemovable => 'Removable';
  @override
  String get driveGroupNetwork => 'Network';
  @override
  String get driveGroupOther => 'Other';
  @override
  String get driveTapToBrowse => 'Tap to browse';
  @override
  String get driveRestrictedAccess => 'Restricted access';
  @override
  String get driveEject => 'Eject';
  @override
  String get driveEjectConfirmTitle => 'Eject drive?';
  @override
  String driveEjectConfirmMessage(String name) =>
      'Safely remove "$name"? Make sure no files are in use.';
  @override
  String get driveEjectSuccess => 'Drive ejected';
  @override
  String driveEjectFailed(String error) => 'Unable to eject: $error';
  @override
  String get driveRename => 'Rename';
  @override
  String get driveRenameTitle => 'Rename volume';
  @override
  String get driveRenameHint => 'Volume label';
  @override
  String get driveRenameSuccess => 'Volume renamed';
  @override
  String driveRenameFailed(String error) => 'Unable to rename: $error';
  @override
  String get driveFormatConfirmTitle => 'Format drive?';
  @override
  String driveFormatConfirmMessage(String name) =>
      'Open the system format tool for "$name"? This can erase all data on the volume.';
  @override
  String get driveOpenInCleaner => 'Open in Disk Cleaner';
  @override
  String get driveUsed => 'Used';
  @override
  String get driveFree => 'Free';
  @override
  String get driveTotal => 'Total';
  @override
  String get driveType => 'Type';
  @override
  String get driveFilesystem => 'File system';
  @override
  String get driveSerial => 'Serial';
  @override
  String get driveKindFixed => 'Local Disk';
  @override
  String get driveKindRemovable => 'Removable';
  @override
  String get driveKindNetwork => 'Network';
  @override
  String get driveKindOptical => 'Optical';
  @override
  String get driveKindRam => 'RAM Disk';
  @override
  String get driveKindInternal => 'Internal storage';
  @override
  String get driveKindUnknown => 'Storage';
  @override
  String get openInNewPane => 'Open in new pane';
  @override
  String get openInWindowsTerminal => 'Open in Windows Terminal';
  @override
  String get driveCleanup => 'Cleanup';
  @override
  String get driveFormat => 'Format';
  @override
  String get driveBitLocker => 'Turn on BitLocker';
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
  String itemsCount(int count) => '$count items';
  @override
  String get noActiveTab => 'No active tab';
  @override
  String get masonryLayoutName => 'Masonry layout (Pinterest)';
  @override
  String get undo => 'Undo';
  @override
  String errorWithMessage(String message) => 'Error: $message';
  @override
  String get referencedFile => 'Referenced file';
  @override
  String referencedFiles(int count) => '$count referenced files';
  @override
  String pathsCopied(int count) => '$count path(s) copied';
  @override
  String get moveToTrashTitle => 'Move to Trash';
  @override
  String get imageMovedToTrash => 'Image moved to trash';
  @override
  String get failedToMoveImageToTrash => 'Failed to move image to trash';
  @override
  String failedToMoveImageToTrashWithError(String error) =>
      'Failed to move image to trash: $error';
  @override
  String get copiedPathToClipboard => 'Copied path to clipboard';
  @override
  String get unableToOpenWithExternalApp => 'Unable to open with external app';
  @override
  String failedToDisplayImageInformation(String error) =>
      'Failed to display image information: $error';
  @override
  String removedFromAlbum(int count) =>
      'Removed $count ${count == 1 ? 'image' : 'images'} from album';
  @override
  String get addingFilesInBackground => 'Adding files in background...';
  @override
  String addedFilesProgress(int added, int total) =>
      'Added $added out of $total files';
  @override
  String get filesAddedSuccessfully => 'Files added successfully';

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
  String get closeOtherTabs => 'Close other tabs';

  @override
  String get markTabInactive => 'Mark as inactive';

  @override
  String get restoringTab => 'Restoring tab…';

  @override
  String get keepTabAlwaysActive => 'Keep tab always active';

  @override
  String get allowTabAutoSuspend => 'Allow tab to auto-suspend';

  @override
  String get tabAlwaysActiveTooltip => 'Always active';

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
  String get thisPC => 'This PC';

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

  @override
  String get pipOverlayEnabled => 'PiP overlay enabled';

  @override
  String get pipAndroidEnableFailed => 'Unable to enable PiP on Android';

  @override
  String pipError(String error) => 'PiP error: $error';

  @override
  String get pipNoSource => 'No video source available to open PiP';

  @override
  String get pipOpenedInSeparateWindow => 'PiP opened in a separate window';

  @override
  String get pipNotSupportedOnPlatform =>
      'PiP is not supported on this platform';

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
  @override
  String get noFileSelectedForBenchmarking =>
      'No file selected for benchmarking';
  @override
  String benchmarkError(String error) => 'Benchmark error: $error';
  @override
  String benchmarkFailed(String error) => 'Benchmark failed: $error';
  @override
  String get saveTagToLocalDatabaseFailed =>
      'Failed to save tag to local database';
  @override
  String saveTagFailed(String error) => 'Failed to save tag: $error';
  @override
  String debugTagsSeeded(int savedCount, int requestedCount) =>
      'Successfully seeded $savedCount/$requestedCount tags';
  @override
  String debugTagsSeedFailed(String error) => 'Error seeding tags: $error';
  @override
  String get debugTagsCleared => 'All tags cleared';
  @override
  String debugTagsClearFailed(String error) => 'Error clearing tags: $error';
  @override
  String addFolderToAlbumFailed(String error) => 'Error adding folder: $error';
  @override
  String addFilesToAlbumFailed(String error) => 'Error adding files: $error';
  @override
  String loadRulesFailed(String error) => 'Error loading rules: $error';
  @override
  String openTerminalFailed(String error) => 'Unable to open terminal: $error';
  @override
  String startCleanupFailed(String error) => 'Unable to start cleanup: $error';
  @override
  String startFormatFailed(String error) => 'Unable to start format: $error';
  @override
  String foundResultsWithTag(int count, String tag) =>
      'Found $count results with tag "$tag"';

  // AI Agent
  @override
  String get aiSearchAgent => 'AI Search Agent';
  @override
  String get aiSearchAgentDescription =>
      'Configure AI providers for intelligent file search';
  @override
  String get aiProvider => 'AI Provider';
  @override
  String get aiProviders => 'AI Providers';
  @override
  String get addProvider => 'Add Provider';
  @override
  String get editProvider => 'Edit Provider';
  @override
  String get deleteProvider => 'Delete Provider';
  @override
  String get providerPreset => 'Provider Preset';
  @override
  String get selectProviderPreset => 'Select a provider preset';
  @override
  String get providerName => 'Provider Name';
  @override
  String get apiType => 'API Type';
  @override
  String get authMode => 'Authentication';
  @override
  String get defaultModel => 'Default Model';
  @override
  String get apiKey => 'API Key';
  @override
  String get codexOauth => 'Codex OAuth';
  @override
  String get endpointUrl => 'Endpoint URL';
  @override
  String get modelName => 'Model Name';
  @override
  String get openAiCompatible => 'OpenAI Compatible';
  @override
  String get anthropic => 'Anthropic';
  @override
  String get temperature => 'Temperature';
  @override
  String get maxTokens => 'Max Tokens';
  @override
  String get systemPrompt => 'System Prompt';
  @override
  String get timeout => 'Timeout (seconds)';
  @override
  String get maxRetries => 'Max Retries';
  @override
  String get testConnection => 'Test Connection';
  @override
  String get connectionSuccess => 'Connection successful';
  @override
  String get aiConnectionFailed => 'Connection failed';
  @override
  String get enableAiSearch => 'Enable AI Search';
  @override
  String get defaultSearchScope => 'Default Search Scope';
  @override
  String get maxContentReadSize => 'Max Content Read Size';
  @override
  String get providerEnabled => 'Provider enabled';
  @override
  String get providerDisabled => 'Provider disabled';
  @override
  String get providerPriority => 'Priority';
  @override
  String get advancedSettings => 'Advanced Settings';
  @override
  String get testingConnection => 'Testing connection...';
  @override
  String get codexOauthDescription =>
      'Use the local Codex/ChatGPT sign-in instead of a raw API key.';
  @override
  String get codexCredentialUnavailable =>
      'Codex credential path is not available on this device.';
  @override
  String get codexCredentialMissing =>
      'Codex OAuth credentials were not found. Run codex login first.';
  @override
  String get launchCodexLogin => 'Launch Codex Login';
  @override
  String get codexLoginLaunched =>
      'Codex login was launched in a separate terminal window.';
  @override
  String get checkCredentials => 'Check Credentials';
  @override
  String deleteProviderConfirmation(String name) =>
      'Are you sure you want to delete the provider "$name"?';
  @override
  String get noProviders => 'No AI providers configured';

  // AI Chat
  @override
  String get aiChat => 'AI Chat';
  @override
  String get askAiToFindFiles => 'Ask AI to find files...';
  @override
  String get sendMessage => 'Send';
  @override
  String get clearChat => 'Clear Chat';
  @override
  String get searchScope => 'Search Scope';
  @override
  String get currentFolder => 'Current Folder';
  @override
  String get recursiveSearch => 'Recursive Search';
  @override
  String get aiTaggedFiles => 'Tagged Files';
  @override
  String get allDrives => 'All Drives';
  @override
  String get findingFiles => 'Finding files...';
  @override
  String get noResultsFound => 'No results found';
  @override
  String get aiSearchResults => 'AI Search Results';
  @override
  String get retryMessage => 'Retry';
  @override
  String get providerFallback => 'Trying next provider...';
  @override
  String get allProvidersFailed => 'All AI providers failed';
  @override
  String get setupAiProvider => 'Set up an AI provider in Settings';
  @override
  String get noProviderConfigured => 'No AI provider configured';
  @override
  String get relevanceScore => 'Relevance';
  @override
  String get aiExplanation => 'AI Explanation';
  @override
  String get aiSearchMode => 'AI Search';
  @override
  String get switchToAiSearch => 'Switch to AI search';
  @override
  String get switchToNormalSearch => 'Switch to normal search';
  @override
  String get aiChatTab => 'AI Chat';
  @override
  String get suggestRecentPhotos => 'Find recent photos';
  @override
  String get suggestLargeVideos => 'Show large videos';
  @override
  String get suggestTaggedFiles => 'Files tagged as...';
  @override
  String get fetchModels => 'Fetch Models';
  @override
  String get fetchingModels => 'Fetching models...';
  @override
  String get loadingModels => 'Loading models...';
  @override
  String get noModelsFound => 'No models found';
  @override
  String get noModelConfigured => 'No model';
  @override
  String get selectModel => 'Select a model';
  @override
  String get modelSearchHint => 'Search models...';
  @override
  String fetchModelsError(String error) => 'Failed to fetch models: $error';
  @override
  String get newConversation => 'New Chat';
  @override
  String get conversations => 'Conversations';
  @override
  String get deleteConversation => 'Delete conversation';
  @override
  String get noConversations => 'No conversations yet';

  // CB Agent rebrand
  @override
  String get cbAgent => 'CB Agent';
  @override
  String get cbAgentTitle => 'CB Agent';
  @override
  String get cbAgentSubtitle => 'Built-in AI assistant for CB File Hub';

  // Disk Cleaner (CB Agent skill)
  @override
  String get cbAgentCleanerTitle => 'Disk Cleaner (CB Agent)';
  @override
  String get diskCleanerNotAvailable =>
      'Disk Cleaner is only available on Windows';
  @override
  String get diskCleanerScanTitle => 'Scan for junk files';
  @override
  String get diskCleanerScanRunning => 'Scanning...';
  @override
  String get diskCleanerScanDone => 'Scan complete';
  @override
  String get diskCleanerCleanTitle => 'Clean junk files';
  @override
  String get diskCleanerCleanDone => 'Cleanup complete';
  @override
  String get diskCleanerAskAgent => 'Ask CB Agent';
  @override
  String get diskCleanerMoveToRecycleBin => 'Move to Recycle Bin';
  @override
  String get diskCleanerPermanentDelete => 'Permanent delete';
  @override
  String get diskCleanerSelectCategories => 'Select categories';
  @override
  String get diskCleanerSelectDrives => 'Select drives';
  @override
  String get diskCleanerScanAgain => 'Scan again';
  @override
  String get diskCleanerCachedResultStatus =>
      'Showing the previous scan (cached result). Scan again to refresh.';

  // Disk Cleaner — extended UI strings
  @override
  String get diskCleanerCancel => 'Cancel';
  @override
  String get diskCleanerShowCleanableOnly => 'Show cleanable only';
  @override
  String diskCleanerCleanableOnlyChip(int count) => 'Cleanable only ($count)';
  @override
  String get diskCleanerCheckAllCleanable => 'Check all cleanable';
  @override
  String get diskCleanerUncheckAll => 'Uncheck all';

  @override
  String get diskCleanerColumnName => 'Name';
  @override
  String get diskCleanerColumnSize => 'Size';
  @override
  String get diskCleanerColumnPercentOfParent => '% of Parent';
  @override
  String get diskCleanerColumnFiles => 'Files';
  @override
  String get diskCleanerBuildingTree => 'Building disk tree...';
  @override
  String get diskCleanerNoFilesFound => 'No files found';
  @override
  String get diskCleanerAnalyzingDisk => 'Analyzing disk usage...';
  @override
  String get diskCleanerPieChartPending =>
      'Pie chart will appear after scan completes.';
  @override
  String get diskCleanerPieEmpty => 'Empty';
  @override
  String get diskCleanerPreparingFiles => 'Preparing files...';
  @override
  String get diskCleanerCleaning => 'Cleaning...';
  @override
  String get diskCleanerScanningSelectedDirs =>
      'Scanning selected directories...';
  @override
  String get diskCleanerDeletingJunkHint =>
      'Deleting selected items. If a file fails, you can skip it or try again.';
  @override
  String get diskCleanerPermanentDeleteLabel => 'Permanent delete';
  @override
  String get diskCleanerRecycleBinLabel => 'Recycle Bin';
  @override
  String get diskCleanerDeletingItems => 'Deleting items...';
  @override
  String get diskCleanerReviewMode => 'Review mode';
  @override
  String get diskCleanerBackToResults => 'Back to results';
  @override
  String get diskCleanerReviewByAgent => 'Review by CB Agent';
  @override
  String get diskCleanerPermanentlyDeleting => 'Permanently deleting...';
  @override
  String get diskCleanerMovingToRecycleBin => 'Moving to Recycle Bin...';
  @override
  String get diskCleanerWaitingDecision => 'Waiting for your decision...';
  @override
  String get diskCleanerFileInUse =>
      'This file appears to be in use by another application.';
  @override
  String get diskCleanerRetryInUseHint =>
      'Retrying now will usually fail again until the app or process using this file is closed.';
  @override
  String get diskCleanerBlockedBy => 'Blocked by:';
  @override
  String get diskCleanerSkipAllRemaining => 'Skip all remaining items';
  @override
  String get diskCleanerSkip => 'Skip';
  @override
  String get diskCleanerTryAgain => 'Try again';
  @override
  String get diskCleanerPermanentDeleteConfirmTitle => 'Permanent delete?';
  @override
  String diskCleanerPermanentDeleteFromBinContent(int count, String size) =>
      'This will permanently delete $count items ($size) from your Recycle Bin. They cannot be restored after this.';
  @override
  String diskCleanerPermanentDeleteSelectedContent(int count, String size) =>
      'This will permanently delete $count selected items ($size). They cannot be restored after this.';
  @override
  String get diskCleanerColumnFileName => 'File name';
  @override
  String get diskCleanerColumnPath => 'Path';
  @override
  String get diskCleanerColumnCategory => 'Category';
  @override
  String get diskCleanerRecycleBinEmpty =>
      'No items are currently in the Recycle Bin.';
  @override
  String diskCleanerItemsInRecycleBin(int count, String size) =>
      '$count items in Recycle Bin ($size)';
  @override
  String diskCleanerSkippedInUseSnack(int count) =>
      'Skipped $count file(s) currently in use. Details were logged.';
  @override
  String diskCleanerSkippedAfterFailureSnack(int count) =>
      'Skipped $count file(s) after delete failed.';
  @override
  String diskCleanerFreedBadge(String size, int count) =>
      'Freed $size  •  $count items';
  @override
  String diskCleanerFailedBadge(int count) => '$count failed';
  @override
  String diskCleanerInUseBadge(int count) => '$count in use';
  @override
  String diskCleanerSkippedBadge(int count) => '$count skipped';
  @override
  String diskCleanerSkippedInUseBanner(int count) =>
      'Skipped $count file(s) currently in use. See logs for the full path list.';
  @override
  String diskCleanerSkippedByUserBanner(int count) =>
      'Skipped $count file(s) after delete failed because you chose Skip.';
  @override
  String diskCleanerDeletedPermanentlyBody(int count) =>
      'Deleted $count items permanently.';
  @override
  String diskCleanerFreedSpace(String size) => 'Freed $size';
  @override
  String diskCleanerPermanentDeleteFinished(int count) =>
      'Permanent delete finished for $count items.';
  @override
  String diskCleanerPermanentDeletingProgress(int done, int total) =>
      'Permanently deleting... $done / $total';
  @override
  String get diskCleanerDeletingLabel => 'Deleting...';
  @override
  String get diskCleanerRemaining => 'remaining';
  @override
  String diskCleanerDriveFree(String label, String size) =>
      '$label  $size free';
  @override
  String diskCleanerFilesCount(int count) => '$count files';
  @override
  String diskCleanerDirsCount(int count) => '$count dirs';
  @override
  String get diskCleanerStarting => 'Starting...';
  @override
  String diskCleanerDriveSummary(String path, String size, int count) =>
      '$path  $size  •  $count files';
  @override
  String get diskCleanerGrowthTitle => 'Recently increased folders';
  @override
  String diskCleanerGrowthFilter(int count) => 'Recently increased ($count)';
  @override
  String diskCleanerGrowthIncrease(String size) => '+$size';
  @override
  String diskCleanerGrowthCurrentSize(String size) => 'Current size: $size';
  @override
  String diskCleanerAgentPath(String path) => 'CB Agent: $path';
  @override
  String diskCleanerItemsBytes(int count, String size) =>
      '$count items • $size';
  @override
  String diskCleanerSizeFiles(String size, int files) => '$size • $files files';

  @override
  String diskCleanerRolledUpItems(int items) => '$items smaller items';
  @override
  String diskCleanerScannedProgress(String size, int files) =>
      '$size scanned • $files files';
  @override
  String get diskCleanerPieChartPendingScan =>
      'Pie chart will appear as soon as scan completes';
  @override
  String get diskCleanerIncrementalScanTitle => 'Incremental scan';
  @override
  String diskCleanerIncrementalScanProgress(int count) =>
      'Updated $count changed folder(s)';
  @override
  String get diskCleanerFullScanFallback =>
      'Incremental scan unavailable — full scan completed';
  @override
  String get diskCleanerOldLargeTitle => 'Old and large items';
  @override
  String get diskCleanerOldLargeSubtitle =>
      'Review hints only. Filesystem timestamps do not prove an item is unused.';
  @override
  String get diskCleanerOldLargeAll => 'All';
  @override
  String get diskCleanerOldLargeFiles => 'Files';
  @override
  String get diskCleanerOldLargeFolders => 'Folders';
  @override
  String diskCleanerOldLargeLastActivity(String date) =>
      'Last activity hint: $date';
  @override
  String get diskCleanerOldLargeReviewOnly => 'Review only';
  @override
  String get diskCleanerOldLargeEmpty =>
      'No old, large files or folders were found.';
  @override
  String diskCleanerScanningPath(String path) => 'Scanning $path';
  @override
  String diskCleanerProcessedCount(int done, int total) =>
      '$done / $total processed';
  @override
  String diskCleanerJunkSummary(String size) => 'Junk: $size';
  @override
  String get diskCleanerContinue => 'Continue';
  @override
  String get diskCleanerAiPanelUnavailable =>
      'AI panel not available in this context';
  @override
  String get diskCleanerAskAgentAboutThis => 'Ask CB Agent about this';
  @override
  String get diskCleanerAiDeleteAnalysisIntro =>
      'Please analyze whether I should delete this file or folder:';
  @override
  String get diskCleanerAiLabelPath => 'Path';
  @override
  String get diskCleanerAiLabelType => 'Type';
  @override
  String get diskCleanerAiLabelName => 'Name';
  @override
  String get diskCleanerAiLabelSize => 'Size';
  @override
  String get diskCleanerAiLabelFiles => 'Files';
  @override
  String get diskCleanerAiTypeFile => 'File';
  @override
  String get diskCleanerAiTypeFolder => 'Folder';
  @override
  String diskCleanerAiCategoryMarkedJunk(String category) =>
      'Category: $category (marked as junk)';
  @override
  String get diskCleanerAiNotMarkedAsJunk => 'Not marked as junk by rules.';
  @override
  String get diskCleanerAiDeleteAnalysisQuestion =>
      'Explain what this file or folder is likely used for, whether it is safe to delete, what risks I should consider, and give a clear recommendation: delete, keep, or review manually.';
  @override
  String diskCleanerScanFailedMsg(String error) => 'Scan failed: $error';
  @override
  String diskCleanerCleanupFailedMsg(String error) => 'Cleanup failed: $error';
  @override
  String diskCleanerPermanentDeleteFailedMsg(String error) =>
      'Permanent delete failed: $error';
  @override
  String diskCleanerAgentFoundJunk(int count, String size) =>
      'CB Agent found $count junk items ($size)';
  @override
  String diskCleanerAndMoreItems(int count) => '... and $count more items';
  @override
  String diskCleanerSelectedBytes(String size, String total) =>
      'Selected: $size / $total';
  @override
  String diskCleanerReviewModeSelected(String size) =>
      'Review mode • Selected: $size';
  @override
  String diskCleanerDeletePermanentlyButton(String size) =>
      'Delete $size permanently';
  @override
  String diskCleanerMoveToRecycleBinButton(String size) =>
      'Move $size to Recycle Bin';
  @override
  String diskCleanerReviewAndClean(String size) => 'Review $size & clean';
  @override
  String diskCleanerPermanentDeletedSuccess(int count, String size) =>
      'Permanently deleted $count items ($size)';
  @override
  String diskCleanerPermanentDeletedWithInUse(
          int count, String size, int skipped) =>
      'Permanently deleted $count items ($size). Skipped $skipped in-use file(s); details were logged.';
  @override
  String diskCleanerPermanentDeletedWithSkipped(
          int count, String size, int skipped) =>
      'Permanently deleted $count items ($size). Skipped $skipped file(s) after delete failed.';

  // Cleaner - drive picker, quick clean, junk reasons
  @override
  String get diskCleanerDriveLowSpace => 'Low space';
  @override
  String diskCleanerDriveCapacity(String used, String total, String free) =>
      '$used of $total used · $free free';
  @override
  String diskCleanerLastScanFound(String when, String junk) =>
      'Last scan $when · found $junk of junk';
  @override
  String get diskCleanerTimeJustNow => 'just now';
  @override
  String get diskCleanerTimeToday => 'today';
  @override
  String get diskCleanerTimeYesterday => 'yesterday';
  @override
  String diskCleanerTimeDaysAgo(int days) => '$days days ago';
  @override
  String diskCleanerTimeWeeksAgo(int weeks) =>
      weeks == 1 ? 'a week ago' : '$weeks weeks ago';
  @override
  String diskCleanerTimeMonthsAgo(int months) =>
      months <= 1 ? 'a month ago' : '$months months ago';
  @override
  String get diskCleanerQuickCleanHint =>
      'Temporary files, caches and the Recycle Bin. Apps rebuild these on demand.';
  @override
  String get diskCleanerQuickCleanButton => 'Quick clean';
  @override
  String get diskCleanerQuickCleanScanning => 'Finding safe items...';
  @override
  String get diskCleanerQuickCleanNothing => 'Nothing safe to clean right now';
  @override
  String get diskCleanerQuickCleanReviewTitle => 'Review quick clean';
  @override
  String diskCleanerQuickCleanReviewSubtitle(int count, String size) =>
      '$count items in these groups, $size in total.';
  @override
  String get diskCleanerQuickCleanRecycleNote =>
      'Everything goes to the Recycle Bin, so you can restore it from there.';
  @override
  String get diskCleanerCategoryWindowsTemp => 'Windows temporary files';
  @override
  String get diskCleanerCategoryBrowserCache => 'Browser caches';
  @override
  String get diskCleanerCategoryRecycleBin => 'Recycle Bin';
  @override
  String get diskCleanerCategoryThumbnailCache => 'Thumbnail cache';
  @override
  String get diskCleanerCategoryAppCache => 'App caches';
  @override
  String get diskCleanerCategoryCrashLogs => 'Crash dumps and logs';
  @override
  String get diskCleanerCategoryWindowsUpdate => 'Windows Update cache';
  @override
  String get diskCleanerCategoryPrefetch => 'Prefetch data';
  @override
  String get diskCleanerCategoryDeliveryOptimization =>
      'Delivery Optimization files';
  @override
  String get diskCleanerCategoryDevCache => 'Developer caches';
  @override
  String get diskCleanerReasonWindowsTemp =>
      'Left behind by apps. Safe to remove; nothing depends on it.';
  @override
  String get diskCleanerReasonBrowserCache =>
      'Your browser rebuilds this on demand. Pages may load slightly slower once.';
  @override
  String get diskCleanerReasonRecycleBin =>
      'Already deleted files waiting to be emptied.';
  @override
  String get diskCleanerReasonThumbnailCache =>
      'Windows regenerates thumbnails the next time you open a folder.';
  @override
  String get diskCleanerReasonAppCache =>
      'Temporary app data. Apps recreate it; you stay signed in.';
  @override
  String get diskCleanerReasonCrashLogs =>
      'Diagnostic files from past crashes. Only useful for troubleshooting.';
  @override
  String get diskCleanerReasonWindowsUpdate =>
      'Installers for updates that are already applied.';
  @override
  String get diskCleanerReasonPrefetch =>
      'App launch hints. Windows rebuilds them over the next few launches.';
  @override
  String get diskCleanerReasonDeliveryOptimization =>
      'Update files cached for sharing with other PCs on your network.';
  @override
  String get diskCleanerReasonDevCache =>
      'Build and package caches. Your tools re-download or rebuild them.';
  @override
  String get diskCleanerReasonGeneric =>
      'Matched a known junk location and is safe to remove.';

  // Cleaner - tree preset views
  @override
  String get diskCleanerPresetTooltip => 'Filter the tree';
  @override
  String get diskCleanerPresetAll => 'Everything';
  @override
  String get diskCleanerPresetLargeFiles => 'Files over 1 GB';
  @override
  String get diskCleanerPresetLogsCaches => 'Logs and caches';
  @override
  String get diskCleanerPresetInstallers => 'Installers and archives';

  // Cleaner - cleaned screen outcome
  @override
  String diskCleanerFreeSpaceBeforeAfter(String before, String after) =>
      'Free space: $before → $after';
  @override
  String get diskCleanerGrowthWatchTitle => 'Growing since your last scan';
  @override
  String diskCleanerGrowthWatchLine(String path, String size) =>
      '$path  +$size';

  // Cleaner App Insights
  @override
  String get cleanerUtilitiesTitle => 'CB Agent Cleaner';
  @override
  String get cleanerUtilitiesSubtitle =>
      'Utilities that help keep this PC fast and organized';
  @override
  String get cleanerUtilitiesStorageGroup => 'Storage';
  @override
  String get cleanerDiskUsageTitle => 'Disk usage';
  @override
  String get cleanerDiskUtilityDescription =>
      'Inspect folders and safely clean confirmed junk';
  @override
  String get cleanerAppsTitle => 'Apps';
  @override
  String get cleanerAppsUtilityDescription =>
      'Find large or rarely used apps and review their data';
  @override
  String get cleanerAppsLoading => 'Analyzing installed apps...';
  @override
  String get cleanerAppsUnavailable =>
      'App insights will be available after the disk scan completes.';
  @override
  String cleanerAppsLoadFailed(String error) =>
      'Could not analyze installed apps: $error';
  @override
  String get cleanerAppsPartialBanner => 'Results are still updating.';
  @override
  String get cleanerAppsSearchHint => 'Search apps';
  @override
  String get cleanerAppsFilterAll => 'All';
  @override
  String get cleanerAppsFilterAttention => 'Review';
  @override
  String get cleanerAppsFilterLarge => 'Large';
  @override
  String get cleanerAppsFilterStale => 'Rarely used';
  @override
  String get cleanerAppsFilterCleanable => 'Cleanable';
  @override
  String get cleanerAppsSortLabel => 'Sort';
  @override
  String get cleanerAppsSortSize => 'Largest first';
  @override
  String get cleanerAppsSortName => 'Name';
  @override
  String get cleanerAppsSortLastOpened => 'Oldest activity';
  @override
  String get cleanerAppsLargeThresholdLabel => 'Large app';
  @override
  String get cleanerAppsStaleThresholdLabel => 'Not seen';
  @override
  String cleanerAppsDays(int days) => '$days days';
  @override
  String get cleanerAppsSummaryFootprint => 'Confirmed footprint';
  @override
  String get cleanerAppsSummaryAttention => 'Worth reviewing';
  @override
  String get cleanerAppsSummaryLarge => 'Large apps';
  @override
  String get cleanerAppsSummaryStale => 'Not seen recently';
  @override
  String get cleanerAppsSummaryCleanable => 'Cleanable cache';
  @override
  String cleanerAppsThresholdAtLeast(String size) => '$size or larger';
  @override
  String cleanerAppsNotSeenForDays(int days) =>
      'No recorded launch for $days days';
  @override
  String get cleanerAppsReviewableCache => 'Available for safe review';
  @override
  String cleanerAppsShowingCount(int count) => 'Showing $count apps';
  @override
  String get cleanerAppsNoResults => 'No apps match these filters.';
  @override
  String get cleanerAppsUnknown => 'Unknown';
  @override
  String cleanerAppsLastOpened(String date) => 'Last seen: $date';
  @override
  String cleanerAppsNotOpenedForDays(int days) => 'Not opened for $days days';
  @override
  String get cleanerAppsUsageUnknownCompact => 'No recent activity data';
  @override
  String get cleanerAppsAttentionBadge => 'Review';
  @override
  String get cleanerAppsViewOptions => 'View options';
  @override
  String cleanerAppsUsageEvidence(String source, String confidence) =>
      '$source • $confidence';
  @override
  String cleanerAppsPossibleSize(String size) => 'Possible: $size';
  @override
  String cleanerAppsCleanableAmount(String size) => 'Cleanable: $size';
  @override
  String get cleanerAppsDetails => 'App details';
  @override
  String get cleanerAppsUsageEvidenceLabel => 'Usage evidence';
  @override
  String get cleanerAppsSelectApp => 'Select an app to view its storage.';
  @override
  String get cleanerAppsConfirmedFootprint => 'Confirmed';
  @override
  String get cleanerAppsPossibleFootprint => 'Possible';
  @override
  String get cleanerAppsStorageBreakdown => 'Storage breakdown';
  @override
  String get cleanerAppsNoStorageDetails =>
      'No measured storage locations are available for this app.';
  @override
  String get cleanerAppsSharedFolders => 'Shared / unattributed large folders';
  @override
  String get cleanerAppsSharedFoldersDescription =>
      'These folders are not assigned to one app and are never selected for cleanup.';
  @override
  String get cleanerAppsOpenFolder => 'Open folder';
  @override
  String get cleanerAppsManageInWindows => 'Manage in Windows';
  @override
  String get cleanerAppsReviewCleanable => 'Review cleanable data';
  @override
  String get cleanerAppsAskAgent => 'Ask CB Agent';
  @override
  String cleanerAppsVersion(String version) => 'Version $version';
  @override
  String cleanerAppsInstalledOrUpdated(String date) =>
      'Installed or updated: $date';
  @override
  String get cleanerAppsSourceWin32 => 'Win32 app';
  @override
  String get cleanerAppsSourceStore => 'Microsoft Store app';
  @override
  String get cleanerAppsMeasurementMeasured => 'Measured';
  @override
  String get cleanerAppsMeasurementEstimated => 'Windows estimate';
  @override
  String get cleanerAppsMeasurementPartial => 'Partial';
  @override
  String get cleanerAppsMeasurementUnknown => 'Unknown size';
  @override
  String get cleanerAppsAttributionConfirmed => 'Confirmed';
  @override
  String get cleanerAppsAttributionPossible => 'Possible';
  @override
  String get cleanerAppsAttributionShared => 'Shared';
  @override
  String get cleanerAppsUsageUserAssist => 'Windows launch history';
  @override
  String get cleanerAppsUsagePrefetch => 'Windows Prefetch';
  @override
  String get cleanerAppsConfidenceHigh => 'High confidence';
  @override
  String get cleanerAppsConfidenceMedium => 'Medium confidence';
  @override
  String get cleanerAppsStorageInstall => 'Installation';
  @override
  String get cleanerAppsStorageLocalData => 'Local app data';
  @override
  String get cleanerAppsStorageRoamingData => 'Roaming app data';
  @override
  String get cleanerAppsStoragePackageData => 'Package data';
  @override
  String get cleanerAppsStorageProgramData => 'Shared program data';
  @override
  String get cleanerAppsStorageCache => 'Cache';
  @override
  String get cleanerAppsStorageLogs => 'Logs';
  @override
  String get cleanerAppsStorageShared => 'Shared storage';
  @override
  String get cleanerAppsStorageUnknown => 'Other storage';
  @override
  String get cleanerAppsCleanableBadge => 'Cleanable';

  @override
  String get aiThinking0 => 'Thinking...';
  @override
  String get aiThinking1 => 'Analyzing...';
  @override
  String get aiThinking2 => 'Searching...';
  @override
  String get aiThinking3 => 'Generating response...';
  @override
  String get aiWaitingApproval => 'Waiting for your approval...';
  @override
  String aiRunningTool(String toolName) => 'Running $toolName...';

  // Local AI Advisor
  @override
  String get localAiAdvisor => 'Local AI Advisor';
  @override
  String get localAiAdvisorDescription =>
      'On-device cleanup suggestions with your own Gemma 4 model';
  @override
  String get huggingFaceToken => 'Hugging Face Token';
  @override
  String get huggingFaceTokenHint =>
      'Optional: For private models or extended catalog access';
  @override
  String get pasteToken => 'Paste Token';
  @override
  String get tokenSaved => 'Token saved securely';
  @override
  String get clearToken => 'Clear Token';
  @override
  String get browseModels => 'Browse Models';
  @override
  String get installedModels => 'Installed Models';
  @override
  String get noModelsInstalled => 'No models installed yet';
  @override
  String get installModel => 'Install';
  @override
  String get uninstallModel => 'Uninstall';
  @override
  String get selectActiveModel => 'Set Active';
  @override
  String get modelInstalling => 'Installing model...';
  @override
  String get modelInstalled => 'Model installed successfully';
  @override
  String get modelUninstalled => 'Model uninstalled';
  @override
  String get downloadProgress => 'Download progress';
  @override
  String get noTokenSet => 'No token set';
  @override
  String get setTokenFirst => 'Set your Hugging Face token first';
  @override
  String get openLocation => 'Open Location';
  @override
  String get localAiIncompatibleArtifact =>
      'This model file is not compatible with on-device chat. Reinstall the LiteRT-LM version to enable local chat.';
  @override
  String get localAiReinstallCompatible => 'Reinstall compatible model';
  @override
  String get localAiContextWindow => 'Context window';
  @override
  String get localAiContextWindowHint =>
      'Maximum tokens per chat (prompt + reply). Higher values handle larger files and longer conversations but use more memory.';
  @override
  String get localAiTokensSuffix => 'tokens';
  @override
  String get localAiInvalidTokenCount => 'Please enter a valid number';
}
