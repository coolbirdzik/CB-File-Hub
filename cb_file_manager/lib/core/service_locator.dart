import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/core/user_preferences.dart';
import '../models/database/database_manager.dart';
import '../services/album_service.dart';
import '../helpers/tags/tag_manager.dart';
import '../helpers/tags/batch_tag_manager.dart';
import '../helpers/tags/tag_thumbnail_manager.dart';
import '../helpers/tags/tag_hierarchy_manager.dart';
import '../services/network_credentials_service.dart';
import '../providers/theme_provider.dart';
import '../services/streaming_service_manager.dart';
import '../helpers/media/folder_thumbnail_service.dart';
import '../config/language_controller.dart';
import '../ui/controllers/operation_progress_controller.dart';
import '../services/windowing/desktop_windowing_service.dart';
import '../services/progress/desktop_app_icon_progress_service.dart';
import '../services/ai/ai_provider_service.dart';
import '../services/ai/ai_chat_history_service.dart';
import '../services/local_ai/local_ai_advisor_service.dart';
import '../services/disk_cleaner/disk_cleaner_service.dart';
import '../services/tab_activity/tab_activity_manager.dart';
import '../services/tab_activity/tab_cache_release_helper.dart';
import '../services/file_metadata_service.dart';
import '../services/archive/archive_service.dart';

/// Global service locator instance
final GetIt locator = GetIt.instance;

/// Setup and register all services in the dependency injection container
///
/// This function should be called once during app initialization before runApp.
/// It registers all singleton services that will be used throughout the application.
Future<void> setupServiceLocator() async {
  // Core services - these are fundamental services needed by other services

  // Register UserPreferences as a lazy singleton
  // Lazy singleton means it will only be instantiated when first accessed
  locator.registerLazySingleton<UserPreferences>(
    () => UserPreferences.instance,
  );

  // Register DatabaseManager as a lazy singleton
  locator.registerLazySingleton<DatabaseManager>(
    () => DatabaseManager.getInstance(),
  );

  // Media and file services

  // Register AlbumService for managing photo/video albums
  locator.registerLazySingleton<AlbumService>(
    () => AlbumService.instance,
  );

  // Tag management services

  // Register TagManager for file tagging functionality
  locator.registerLazySingleton<TagManager>(
    () => TagManager.instance,
  );

  // Register BatchTagManager for batch tag operations
  locator.registerLazySingleton<BatchTagManager>(
    () => BatchTagManager.getInstance(),
  );

  // Register TagThumbnailManager for tag thumbnail images
  locator.registerLazySingleton<TagThumbnailManager>(
    () => TagThumbnailManager.instance,
  );

  // Register TagHierarchyManager for parent-child tag relationships
  locator.registerLazySingleton<TagHierarchyManager>(
    () => TagHierarchyManager.instance,
  );

  // Network services

  // Register NetworkCredentialsService for storing network credentials
  locator.registerLazySingleton<NetworkCredentialsService>(
    () => NetworkCredentialsService(),
  );

  // Register StreamingServiceManager for media streaming
  locator.registerLazySingleton<StreamingServiceManager>(
    () => StreamingServiceManager(),
  );

  // UI services

  // Register ThemeProvider for theme management
  // Note: This is registered as a factory since it extends ChangeNotifier
  // and we want to ensure proper lifecycle management
  locator.registerLazySingleton<ThemeProvider>(
    () => ThemeProvider(),
  );

  // Register FolderThumbnailService
  locator.registerLazySingleton<FolderThumbnailService>(
    () => FolderThumbnailService(),
  );

  // Register LanguageController
  locator.registerLazySingleton<LanguageController>(
    () => LanguageController(),
  );

  // Register OperationProgressController (global operation progress UI)
  locator.registerLazySingleton<OperationProgressController>(
    () => OperationProgressController(),
  );

  locator.registerLazySingleton<DesktopAppIconProgressService>(
    () => DesktopAppIconProgressService(),
  );

  // Register DesktopWindowingService (desktop-only; no-op on mobile).
  locator.registerLazySingleton<DesktopWindowingService>(
    () => DesktopWindowingService(),
  );

  // AI services

  // Register AiProviderService for AI provider management and chat
  locator.registerLazySingleton<AiProviderService>(
    () => AiProviderService(),
  );

  // Register AiChatHistoryService for persisting conversation history
  locator.registerLazySingleton<AiChatHistoryService>(
    () => AiChatHistoryService(),
  );

  // Register LocalAiAdvisorService for on-device cleanup suggestions.
  // SharedPreferences is loaded here so consumers can resolve the service
  // synchronously during widget/bloc creation.
  final sharedPreferences = await SharedPreferences.getInstance();
  locator.registerLazySingleton<LocalAiAdvisorService>(
    () => LocalAiAdvisorService(prefs: sharedPreferences),
  );

  // File metadata service — provides cached image dimensions, video duration,
  // and folder item counts for the details/list view columns.
  locator.registerLazySingleton<FileMetadataService>(
    () => FileMetadataService(),
  );

  locator.registerLazySingleton<ArchiveService>(
    () => ArchiveService(),
  );

  // Disk cleaner skill — Windows-only, used both by the AI agent's
  // disk_cleaner tools and the companion CB Agent Cleaner screen.
  locator.registerLazySingleton<DiskCleanerService>(
    () => DiskCleanerService.instance,
  );

  // Tab activity manager — coordinates per-tab focus/idle lifecycle and
  // triggers aggressive cache release when a tab is left untouched for the
  // configured threshold (defaults to 1 hour, configurable in settings).
  // See [TabActivityManager].
  locator.registerLazySingleton<TabActivityManager>(() {
    final manager = TabActivityManager();
    manager.addInactiveListener((tabId, path) {
      // Fire-and-forget: cache release is best-effort and must not block
      // the periodic evaluation timer.
      TabCacheReleaseHelper.releaseForTab(tabId: tabId, path: path);
    });
    manager.startPeriodicEvaluation();

    // Pull the persisted threshold asynchronously. It defaults to the
    // built-in value until the preference is loaded.
    () async {
      try {
        final prefs = locator<UserPreferences>();
        await prefs.init();
        final minutes = await prefs.getTabInactiveThresholdMinutes();
        manager.setInactiveThreshold(Duration(minutes: minutes));
      } catch (_) {
        // Ignore — the manager keeps its default threshold.
      }
    }();

    return manager;
  });

  // Note: Services are registered but not initialized here.
  // Initialization that requires async operations should be done
  // in the main.dart file after setupServiceLocator() is called.
}
