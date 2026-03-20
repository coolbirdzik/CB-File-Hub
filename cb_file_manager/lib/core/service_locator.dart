import 'package:get_it/get_it.dart';
import '../helpers/core/user_preferences.dart';
import '../models/database/database_manager.dart';
import '../services/album_service.dart';
import '../helpers/tags/tag_manager.dart';
import '../helpers/tags/batch_tag_manager.dart';
import '../services/network_credentials_service.dart';
import '../providers/theme_provider.dart';
import '../services/streaming_service_manager.dart';
import '../helpers/media/folder_thumbnail_service.dart';
import '../config/language_controller.dart';
import '../ui/controllers/operation_progress_controller.dart';
import '../services/windowing/desktop_windowing_service.dart';

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

  // Register DesktopWindowingService (desktop-only; no-op on mobile).
  locator.registerLazySingleton<DesktopWindowingService>(
    () => DesktopWindowingService(),
  );

  // Note: Services are registered but not initialized here.
  // Initialization that requires async operations should be done
  // in the main.dart file after setupServiceLocator() is called.
}
