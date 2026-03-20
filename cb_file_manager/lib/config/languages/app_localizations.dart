import 'package:flutter/material.dart';

abstract class AppLocalizations {
  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  // App title
  String get appTitle;

  // Common actions
  String get ok;
  String get cancel;
  String get save;
  String get delete;
  String get edit;
  String get close;
  String get exit;
  String get search;
  String get all;
  String get settings;
  String get moreOptions;

  // File operations
  String get copy;
  String get cut;
  String get move;
  String get rename;
  String get newFolder;
  String get properties;
  String get openWith;
  String get chooseDefaultApp;
  String get setCoolBirdAsDefaultForVideos;
  String get setCoolBirdAsDefaultForVideosAndroidHint;
  String get openFolder;
  String get openFile;
  String get viewImage;
  String get open;
  String get pasteHere;
  String get manageTags;
  String get moveToTrash;
  String get errorAccessingDirectory;
  String errorAccessingDirectoryWithError(String error);
  String accessDeniedAdminMessage(String path);
  String directoryDoesNotExist(String path);

  // Action bar tooltips
  String get searchTooltip;
  String get sortByTooltip;
  String get refreshTooltip;
  String get moreOptionsTooltip;
  String get adjustGridSizeTooltip;
  String get columnSettingsTooltip;
  String get viewModeTooltip;

  // Dialog titles
  String get adjustGridSizeTitle;
  String get columnVisibilityTitle;

  // Button labels
  String get apply;

  // Sort options
  String get sortNameAsc;
  String get sortNameDesc;
  String get sortDateModifiedOldest;
  String get sortDateModifiedNewest;
  String get sortDateCreatedOldest;
  String get sortDateCreatedNewest;
  String get sortSizeSmallest;
  String get sortSizeLargest;
  String get sortTypeAsc;
  String get sortTypeDesc;
  String get sortExtensionAsc;
  String get sortExtensionDesc;
  String get sortAttributesAsc;
  String get sortAttributesDesc;

  // View modes
  String get viewModeList;
  String get viewModeGrid;
  String get viewModeDetails;
  String get viewModeGridPreview;

  // Preview pane
  String get previewPaneTitle;
  String get previewSelectFile;
  String get previewNotSupported;
  String get previewUnavailable;
  String get showPreview;
  String get hidePreview;

  // Column names
  String get columnSize;
  String get columnType;
  String get columnDateModified;
  String get columnDateCreated;
  String get columnAttributes;

  // Column descriptions
  String get columnSizeDescription;
  String get columnTypeDescription;
  String get columnDateModifiedDescription;
  String get columnDateCreatedDescription;
  String get columnAttributesDescription;

  // Column visibility dialog
  String get columnVisibilityInstructions;

  // Grid size dialog
  String gridSizeLabel(int count);
  String get gridSizeInstructions;

  // More options menu
  String get selectMultipleFiles;
  String get viewImageGallery;
  String get viewVideoGallery;

  // Navigation
  String get home;
  String get back;
  String get forward;
  String get refresh;
  String get parentFolder;

  // Video Hub
  String get videoHub;
  String get manageYourVideos;
  String get videos;
  String get videoActions;
  String get allVideos;
  String get browseAllYourVideos;
  String get videosFolder;
  String get openFileManager;
  String get videoStatistics;
  String get totalVideos;

  String get internalStorage;
  String get storagePrefix;
  String get rootFolder;

  // File types
  String get image;
  String get video;
  String get audio;
  String get document;
  String get folder;
  String get file;

  // File type labels
  String get fileTypeGeneric;
  String get fileTypeJpeg;
  String get fileTypePng;
  String get fileTypeGif;
  String get fileTypeBmp;
  String get fileTypeTiff;
  String get fileTypeWebp;
  String get fileTypeSvg;
  String get fileTypeMp4;
  String get fileTypeAvi;
  String get fileTypeMov;
  String get fileTypeWmv;
  String get fileTypeFlv;
  String get fileTypeMkv;
  String get fileTypeMp3;
  String get fileTypeWav;
  String get fileTypeAac;
  String get fileTypeFlac;
  String get fileTypeOgg;
  String get fileTypePdf;
  String get fileTypeWord;
  String get fileTypeExcel;
  String get fileTypePowerPoint;
  String get fileTypeTxt;
  String get fileTypeRtf;
  String get fileTypeZip;
  String get fileTypeRar;
  String get fileType7z;
  String fileTypeWithExtension(String extension);

  // Settings
  String get language;
  String get theme;
  String get darkMode;
  String get lightMode;
  String get systemMode;
  String get selectLanguage;
  String get selectTheme;
  String get selectThumbnailPosition;
  String get systemThemeDescription;
  String get lightThemeDescription;
  String get darkThemeDescription;
  String get themeOnboardingTitle;
  String get themeOnboardingDescription;
  String get themeOnboardingLightLabel;
  String get themeOnboardingDarkLabel;
  String get themeOnboardingMoreThemesMessage;
  String get themeOnboardingContinue;
  String get vietnameseLanguage;
  String get englishLanguage;

  // Messages
  String get fileDeleteConfirmation;
  String get folderDeleteConfirmation;
  String get fileDeleteSuccess;
  String get folderDeleteSuccess;
  String get operationFailed;

  // Tags
  String get tags;
  String get addTag;
  String get removeTag;
  String get tagManagement;
  String deleteTagConfirmation(String tag);
  String get tagDeleteConfirmationText;
  String tagDeleted(String tag);
  String errorDeletingTag(String error);
  String chooseTagColor(String tag);
  String tagColorUpdated(String tag);
  String get allTags;
  String get filesWithTag;
  String get tagsInDirectory;
  String get aboutTags;
  String get aboutTagsTitle;
  String get aboutTagsDescription;
  String get aboutTagsScreenDescription;
  String get deleteTag;
  String get deleteAlbum;

  // Tag Management Screen
  String get tagManagementTitle;
  String get debugTags;
  String get searchTags;
  String get searchTagsHint;
  String get createNewTag;
  String get newTagTooltip;
  String get errorLoadingTags;
  String get noTagsFoundMessage;
  String get noTagsFoundDescription;
  String get createNewTagButton;
  String noMatchingTagsMessage(String searchTags);
  String get clearSearch;
  String get tagManagementHeader;
  String get tagsCreated;
  String get tagManagementDescription;
  String get sortTags;
  String get sortByAlphabet;
  String get sortByPopular;
  String get listViewMode;
  String get gridViewMode;
  String get previousPage;
  String get nextPage;
  String get page;
  String get firstPage;
  String get lastPage;
  String get clickToViewFiles;
  String get changeTagColor;
  String get deleteTagFromAllFiles;
  String get openInNewTab;
  String get viewFilesWithTag;
  String get renameTag;
  String tagRenamed(String oldTag, String newTag);
  String get openInSplitView;
  String get changeColor;
  String get noFilesWithTag;
  String debugInfo(String tag);
  String get backToAllTags;
  String get tryAgain;
  String get filesWithTagCount;
  String get viewDetails;
  String get openContainingFolder;
  String get editTags;
  String get newTagTitle;
  String get enterTagName;
  String get tagName;
  String get enterNewTagName;
  String tagAlreadyExists(String tagName);
  String tagCreatedSuccessfully(String tagName);
  String get errorCreatingTag;
  String get tagsSavedSuccessfully;
  String get selectTagToRemove;
  String get doubleClickToRename;
  String get openingFolder;
  String get folderNotFound;
  String get refreshTags;
  String tagsRefreshed(int count);

  // Sorting
  String get sort;
  String get sortByName;
  String get sortByPopularity;
  String get sortByRecent;
  String get sortBySize;

  // Bulk Selection
  String get bulkSelect;
  String get selectAllTags;
  String selectAllOnAllPages(int totalCount);
  String get deselectAllTags;
  String tagsSelected(int count);
  String bulkDeleteConfirmationTitle();
  String bulkDeleteConfirmationText(int count);
  String bulkDeleteSuccess(int count);
  String get sortByDate;

  // Gallery
  String get imageGallery;
  String get videoGallery;

  // Gallery Hub
  String get galleryHub;
  String get managePhotosAndAlbums;
  String get images;
  String get galleryActions;
  String get quickAccess;
  String get browseAllYourPictures;
  String get browseAllYourPhotos;
  String get organizeInAlbums;
  String get picturesFolder;
  String get photosFromCamera;
  String get downloadedFiles;
  String get downloadedImages;
  String get featuredAlbums;
  String get personalized;
  String get configureFeaturedAlbums;
  String get noFeaturedAlbums;
  String get createSomeAlbumsToSeeThemFeaturedHere;
  String get removeFromFeatured;
  String get galleryStatistics;
  String get totalImages;
  String get albums;
  String get allImages;
  String get camera;
  String get downloads;
  String get recent;
  String get folders;

  // Storage locations
  String get local;
  String get networks;

  // File operations related to networks
  String get download;
  String get downloadFile;
  String get selectDownloadLocation;
  String get selectFolder;
  String get browse;
  String get upload;
  String get uploadFile;
  String get selectFileToUpload;
  String get create;
  String get folderName;

  // Additional translations for database settings
  String get databaseSettings;
  String get databaseStorage;
  String get useDatabaseStorage;
  String get databaseStorageEnabled;
  String
      get objectBoxStorage; // Kept for backward compatibility if needed, or remove if unused
  String get jsonStorage;
  String get databaseDescription;

  // Cloud sync
  String get cloudSync;
  String get enableCloudSync;
  String get cloudSyncDescription;
  String get syncToCloud;
  String get syncFromCloud;
  String get cloudSyncEnabled;
  String get cloudSyncDisabled;
  String get enableDatabaseForCloud;

  // Database statistics
  String get databaseStatistics;
  String get totalUniqueTags;
  String get taggedFiles;
  String get popularTags;
  String get recentTags;
  String get selectedTags;
  String get tagSuggestions;
  String batchAddTags(int count);
  String get applyingChanges;
  String tagsUpdated(int count, int added, int removed);
  String get advancedDatabaseSettings;
  String get noTagsFound;
  String get refreshStatistics;

  // Raw Data Viewer
  String get viewRawData;
  String get rawDataPreferences;
  String get rawDataTags;
  String get rawDataDescription;
  String get noDataFound;

  // Import/Export
  String get importExportDatabase;
  String get backupRestoreDescription;
  String get exportDatabase;
  String get exportSettings;
  String get importDatabase;
  String get importSettings;
  String get exportDescription;
  String get importDescription;
  String get completeBackup;
  String get completeRestore;
  String get exportAllData;
  String get importAllData;

  String get resetSettings;

  // Export/Import messages
  String get exportSuccess;
  String get exportFailed;
  String get importSuccess;
  String get importFailed;
  String get importCancelled;
  String get errorExporting;
  String get errorImporting;

  // Video thumbnails
  String get videoThumbnails;
  String get thumbnailMode;
  String get thumbnailModeFast;
  String get thumbnailModeCustom;
  String get thumbnailModeFastDescription;
  String get thumbnailModeCustomDescription;
  String get thumbnailPosition;
  String get percentOfVideo;
  String get thumbnailDescription;
  String get generatingAtPosition;
  String get generatingFast;
  String get maxConcurrency;
  String get maxConcurrencyDescription;
  String get useSystemDefaultForVideo;
  String get useSystemDefaultForVideoDescription;
  String get useSystemDefaultForVideoEnabled;
  String get useSystemDefaultForVideoDisabled;
  String get thumbnailCache;
  String get thumbnailCacheDescription;
  String get clearThumbnailCache;
  String get clearing;
  String get thumbnailCleared;
  String get errorClearingThumbnail;

  // New tab
  String get newTab;

  // Admin access
  String get adminAccess;
  String get adminAccessRequired;
  String get requiresAdminPrivileges;
  String driveRequiresAdmin(String path);
  String get trashBin;

  // File system
  String get drives;
  String get system;

  // Settings data
  String get settingsData;
  String get viewManageSettings;

  // File details
  String get fileSize;
  String get fileLocation;
  String get fileCreated;
  String get fileModified;
  String get fileName;
  String get filePath;
  String get fileType;
  String get fileLastModified;
  String get fileAccessed;
  String get loadingVideo;
  String get errorLoadingImage;
  String errorLoadingImageWithError(String error);
  String get failedToDisplayImage;
  String get noImageDataAvailable;
  String get urlLoadingNotImplemented;
  String get duration;
  String get resolution;
  String get createCopy;
  String get deleteFile;

  // Folder thumbnails
  String get folderThumbnail;
  String get chooseThumbnail;
  String get clearThumbnail;
  String get thumbnailAuto;
  String get folderThumbnailSet;
  String get folderThumbnailCleared;
  String get invalidThumbnailFile;
  String get noMediaFilesFound;

  // Video actions
  String get share;
  String get playVideo;
  String get videoInfo;
  String get deleteVideo;
  String get loadingThumbnails;
  String get deleteVideosConfirm; // "Xóa {count} video?"
  String get deleteConfirmationMessage; // "Bạn có chắc chắn..."
  String videosSelected(int count); // "{count} video đã chọn"
  String videosDeleted(int count); // "Đã xóa {count} video"
  String searchingFor(String query); // "Tìm kiếm: {query}"
  String get errorDisplayingVideoInfo;
  String get searchVideos; // "Tìm kiếm video"
  String get enterVideoName; // "Nhập tên video..."

  // Selection and grid
  String? get selectMultiple; // "Chọn nhiều file"
  String? get gridSize; // "Kích thước lưới"

  // Clipboard actions
  String copiedToClipboard(String name);
  String cutToClipboard(String name);
  String get pasting;

  // Rename dialogs
  String get renameFileTitle;
  String get renameFolderTitle;
  String currentNameLabel(String name);
  String get newNameLabel;
  String renamedFileTo(String newName);
  String renamedFolderTo(String newName);

  // Downloads
  String downloadedTo(String location);
  String downloadFailed(String error);

  // Folder / Trash
  String get items;
  String get files;
  String get deleteTitle;
  String get permanentDeleteTitle;
  String confirmDeletePermanent(String name);
  String confirmDeletePermanentMultiple(int count);
  String movedToTrash(String name);
  String moveItemsToTrashConfirmation(int count, String itemType);
  String moveToTrashConfirmMessage(String name);
  String get moveItemsToTrashDescription;
  String get clearFilter;
  String filteredBy(String filter);
  String noFilesMatchFilter(String filter);

  // Trash / Recycle Bin screen
  String get emptyTrash;
  String get emptyTrashConfirm;
  String get emptyTrashButton;
  String permanentlyDeleteItemsTitle(int count);
  String get confirmPermanentlyDeleteThese;
  String itemRestoredSuccess(String name);
  String failedToRestore(String name);
  String errorRestoringItemWithError(String error);
  String itemPermanentlyDeleted(String name);
  String failedToDelete(String name);
  String failedToDeleteFilesCount(int count);
  String failedToDeleteItemsCount(int count);
  String errorDeletingItemWithError(String error);
  String get trashEmptiedSuccess;
  String get failedToEmptyTrash;
  String errorEmptyingTrashWithError(String error);
  String itemsRestoredSuccess(int count);
  String itemsRestoredWithFailures(int success, int failed);
  String itemsPermanentlyDeletedCount(int count);
  String itemsDeletedWithFailures(int success, int failed);
  String errorRestoringItemsWithError(String error);
  String errorDeletingItemsWithError(String error);
  String errorDeletingFilesWithError(String error);
  String errorOpeningRecycleBinWithError(String error);
  String get restoreSelected;
  String get deleteSelected;
  String get selectItems;
  String get openRecycleBin;
  String get emptyTrashTooltip;
  String get trashIsEmpty;
  String get itemsDeletedWillAppearHere;
  String originalLocation(String path);
  String deletedAt(String date, String size);
  String get systemLabel;
  String errorLoadingTrashItemsWithError(String error);
  String get restoreTooltip;
  String get deletePermanentlyTooltip;

  // Misc helper labels
  String get networkFile;
  String tagCount(int count);

  // Generic errors
  String errorGettingFolderProperties(String error);
  String errorSavingTags(String error);
  String errorCreatingFolder(String error);
  String get pathNotAccessible;

  // UI labels
  String get noStorageLocationsFound;
  String get menuPinningOnlyLargeScreens;
  String get pinMenu;
  String get unpinMenu;
  String get pinnedSection;
  String get pinToSidebar;
  String get unpinFromSidebar;
  String get pinnedToSidebar;
  String get removedFromSidebar;
  String get exitApplicationTitle;
  String get exitApplicationConfirm;
  String itemsSelected(int count);
  String get noActiveTab;
  String get masonryLayoutName;
  String get undo;
  String errorWithMessage(String message);

  // File picker dialogs
  String get chooseBackupLocation;
  String get chooseRestoreLocation;
  String get saveSettingsExport;
  String get saveDatabaseExport;
  String get selectBackupFolder;

  // About app
  String get aboutApp;
  String get appDescription;
  String get version;
  String get developer;

  // Empty state
  String get emptyFolder;
  String get noImagesFound;
  String get noVideosFound;
  String get loading;

  // Search errors
  String noFilesFoundTag(Map<String, String> args);
  String noFilesFoundTagGlobal(Map<String, String> args);
  String noFilesFoundTags(Map<String, String> args);
  String noFilesFoundTagsGlobal(Map<String, String> args);
  String noFilesFoundQuery(Map<String, String> args);
  String errorSearchTag(Map<String, String> args);
  String errorSearchTagGlobal(Map<String, String> args);
  String errorSearchTags(Map<String, String> args);
  String errorSearchTagsGlobal(Map<String, String> args);

  // Search status
  String searchingTag(Map<String, String> args);
  String searchingTagGlobal(Map<String, String> args);
  String searchingTags(Map<String, String> args);
  String searchingTagsGlobal(Map<String, String> args);
  String get searchOrEnterPath;
  String get pleaseCreateTabFirst;

  String get viewMode;
  String get masonryLayout;

  // Tag list state
  String get tagListRefreshing;

  // Search UI
  String get searchTips;
  String get searchTipsTitle;
  String get viewTagSuggestions;
  String get globalSearchModeEnabled;
  String get localSearchModeEnabled;
  String get globalSearchMode;
  String get localSearchMode;
  String get searchByFilename;
  String get searchByTags;
  String get searchMultipleTags;
  String get globalSearch;
  String get searchByNameOrTag;
  String get searchInSubfolders;
  String get featureNotImplemented;
  String get searchInAllFolders;
  String get searchInCurrentFolder;
  String get searchShortcuts;
  String get searchHintText;
  String get searchHintTextTags;
  String get suggestedTags;
  String get noMatchingTags;
  String get results;
  String searchResultsTitle(String countText);
  String searchResultsTitleForQuery(String query, String countText);
  String searchResultsTitleForTag(String tag, String countText);
  String searchResultsTitleForTagGlobal(String tag, String countText);
  String searchResultsTitleForFilter(String filter, String countText);
  String searchResultsTitleForMedia(String mediaType, String countText);
  String get searchByFilenameDesc;
  String get searchByTagsDesc;
  String get searchMultipleTagsDesc;
  String get globalSearchDesc;
  String get searchShortcutsDesc;

  // Permissions
  String get grantPermissionsToContinue;
  String get permissionsDescription;
  String get storagePermissionRequiredMessage;
  String get storagePhotosPermission;
  String get storagePhotosDescription;
  String get allFilesAccessPermission;
  String get allFilesAccessDescription;
  String get installPackagesPermission;
  String get installPackagesDescription;
  String get localNetworkPermission;
  String get localNetworkDescription;
  String get notificationsPermission;
  String get notificationsDescription;
  String get grantAllPermissions;
  String get grantingPermissions;
  String get enterApp;
  String get skipEnterApp;
  String get granted;
  String get grantPermission;

  // Home screen
  String get welcomeToFileManager;
  String get welcomeDescription;
  String get quickActions;
  String get browseFiles;
  String get browseFilesDescription;
  String get manageMedia;
  String get manageMediaDescription;
  String get tagFiles;
  String get tagFilesDescription;
  String get networkAccess;
  String get networkAccessDescription;
  String get keyFeatures;
  String get fileManagement;
  String get fileManagementDescription;
  String get smartTagging;
  String get smartTaggingDescription;
  String get mediaGallery;
  String get mediaGalleryDescription;
  String get networkSupport;
  String get networkSupportDescription;

  // Settings screen
  String get interface;
  String get selectInterfaceTheme;
  String get chooseInterface;
  String get interfaceDescription;
  String get showFileTags;
  String get showFileTagsDescription;
  String get showFileTagsToggle;
  String get showFileTagsToggleDescription;
  String get rememberTabWorkspace;
  String get rememberTabWorkspaceDescription;
  String get cacheManagement;
  String get cacheManagementDescription;
  String get cacheFolder;
  String get networkThumbnails;
  String get videoThumbnailsCache;
  String get tempFiles;
  String get notInitialized;
  String get refreshCacheInfo;
  String get cacheInfoUpdated;
  String get clearVideoThumbnailsCache;
  String get clearVideoThumbnailsDescription;
  String get clearNetworkThumbnailsCache;
  String get clearNetworkThumbnailsDescription;
  String get clearTempFilesCache;
  String get clearTempFilesDescription;
  String get clearAllCache;
  String get clearAllCacheDescription;
  String get videoCacheCleared;
  String get networkCacheCleared;
  String get tempFilesCleared;
  String get allCacheCleared;
  String get errorClearingCache;
  String get processing;
  String get deletingFiles;
  String get deletingItems;
  String get movingItemsToTrash;
  String get done;
  String get regenerateThumbnailsWithNewPosition;
  String get thumbnailPositionUpdated;
  String get fileTagsEnabled;
  String get fileTagsDisabled;

  // System screen router
  String get unknownSystemPath;
  String get ftpConnectionRequired;
  String get ftpConnectionDescription;
  String get goToFtpConnections;
  String get cannotOpenNetworkPath;
  String get goBack;
  String get tagPrefix;

  // Network browsing
  String get ftpConnections;
  String get smbNetwork;
  String get refreshData;
  String get addConnection;
  String get noFtpConnections;
  String get activeConnections;
  String get savedConnections;
  String get connecting;
  String get connect;
  String get unknown;
  String get connectionError;
  String get loadCredentialsError;
  String get networkScanFailed;
  String get smbVersionUnknown;
  String get connectionInfoUnavailable;
  String get networkSettingsOpened;
  String get cannotOpenNetworkSettings;
  String get networkDiscoveryDisabled;
  String get networkDiscoveryDescription;
  String get openSettings;
  String get activeConnectionsTitle;
  String get activeConnectionsDescription;
  String get discoveredSmbServers;
  String get discoveredSmbServersDescription;
  String get noActiveSmbConnections;
  String get connectToSmbServer;
  String get connected;
  String get openConnection;
  String get disconnect;
  String get scanningForSmbServers;
  String get devicesWillAppear;
  String get scanningMayTakeTime;
  String get noSmbServersFound;
  String get tryScanningAgain;
  String get scanAgain;
  String get readyToScan;
  String get clickRefreshToScan;
  String get startScan;
  String get foundDevices;
  String get scanning;
  String get scanComplete;
  String get smbVersion;
  String get netbios;

  // Network - additional
  String get selectAll;
  String get unknownError;
  String get networkConnections;
  String get availableServices;
  String get noActiveNetworkConnections;
  String get useAddButtonToAddConnection;
  String get unknownConnection;
  String serviceTypeConnection(String serviceName);
  String get noServicesAvailable;
  String get webdavConnections;
  String errorOpeningTab(String tabName, String error);
  String connectToServiceServer(String serviceName);
  String get serviceType;
  String get host;
  String get deleteSavedConnection;
  String get username;
  String get password;
  String get portOptional;
  String get useSslTls;
  String get basePathOptional;
  String get basePathHint;
  String get domainOptional;
  String get saveCredentials;
  String get saveCredentialsDescription;
  String get deleteSavedConnectionTitle;
  String deleteSavedConnectionConfirm(String host);
  String connectionDeleted(String host);
  String connectionNotFoundToDelete(String host);
  String get errorDeletingConnection;
  String connectionFailed(String error);
  String get networkConnection;
  String get notConnected;
  String get refreshSmbVersionInfo;
  String shareLabel(String sharePath);
  String get rootShare;
  String foundDevicesCount(int count);
  String get noWebdavConnections;
  String get addConnectionOrSampleToStart;
  String get addSample;
  String get editWebdavConnection;
  String get update;
  String get connectionUpdatedSuccess;
  String get failedToUpdateConnection;
  String get deleteConnection;
  String deleteConnectionConfirm(String host);
  String get connectionDeletedSuccess;
  String get failedToDeleteConnection;
  String get addSampleWebdavConnection;
  String get sampleConnectionAddedSuccess;
  String get failedToAddSampleConnection;
  String lastConnected(String dateStr);
  String get editConnection;
  String get closeConnection;
  String get retry;
  String get networkErrorPersistsHint;
  String get pleaseEnterHost;
  String get pleaseEnterPort;
  String get pleaseEnterValidPort;
  String get connectionMode;
  String get passive;
  String get active;
  String get port;
  String get basePath;

  // Drawer menu items
  String get networksMenu;
  String get networkTab;
  String get about;

  // Tab manager
  String get newTabButton;
  String get openNewTabToStart;
  String get tabManager;
  String get openTabs;
  String get noTabsOpen;
  String get closeAllTabs;
  String get activeTab;
  String get closeTab;
  String get addNewTab;

  // Desktop windows (tabbed browsing)
  String get newWindow;
  String get moveTabToNewWindow;
  String get moveTabToWindow;
  String get mergeWindowIntoThis;
  String get selectWindow;
  String get noOtherWindows;

  // Home screen
  String get welcomeTitle;
  String get welcomeSubtitle;
  String get quickActionsTip;
  String get quickActionsHome;
  String get startHere;
  String get newTabAction;
  String get newTabActionDesc;
  String get tagsAction;
  String get tagsActionDesc;
  String get imageGalleryTab;
  String get videoGalleryTab;
  String get drivesTab;
  String get browseTab;
  String get documentsTab;
  String get homeTab;

  // Video player screenshot
  String get takeScreenshot;
  String get screenshotSaved;
  String get screenshotSavedAt;
  String get screenshotFailed;
  String get screenshotSavedToFolder;
  String get openScreenshotFolder;
  String get viewScreenshot;
  String get screenshotNotAvailableVlc;
  String get screenshotNotAvailableVlcMessage;
  String get screenshotFileNotFound;
  String get screenshotCannotOpenTab;
  String get screenshotErrorOpeningFolder;
  String get closeAction;

  // Video library
  String get videoLibrary;
  String get videoLibraries;
  String get createVideoLibrary;
  String get editVideoLibrary;
  String get deleteVideoLibrary;
  String get addVideoSource;
  String get removeVideoSource;
  String get videoSources;
  String get noVideoSources;
  String get filterByTags;
  String get clearTagFilter;
  String get recentVideos;
  String get videoHubTitle;
  String get videoHubWelcome;
  String get manageVideoLibraries;
  String get videoCount;
  String get scanForVideos;
  String get rescanLibrary;
  String deleteVideoLibraryConfirmation(String name);
  String get libraryDeletedSuccessfully;
  String get sourceAdded;
  String get sourceRemoved;
  String get selectVideoSource;
  String get videoLibrarySettings;
  String get manageVideoSources;
  String get videoExtensions;
  String get includeSubdirectories;
  String get noVideosInLibrary;
  String get libraryCreatedSuccessfully;
  String videoLibraryCount(int count);

  // Streaming and download dialogs
  String openFileTypeFile(String fileType);
  String streamDownloadPrompt(String fileType);
  String get downloadingFile;
  String get fileDownloadedSuccess;
  String get errorDownloadingFile;
  String get errorTitle;
  String get mediaPlaybackError;
  String mediaPlaybackErrorVlcContent(String error);
  String mediaPlaybackErrorNativeContent(String error);
  String get chooseAnotherApp;
  String get folderProperties;
  String get createNewFolder;
  String get createNewFile;
  String get folderPropertyPath;
  String get folderPropertyCreated;
  String get folderPropertyContent;
  String get folderPropertySizeDirectChildren;
  String get networkServiceNotAvailable;
  String get folderNameLabel;
  String get fileNameLabel;
  String errorCreatingFile(String error);
}
