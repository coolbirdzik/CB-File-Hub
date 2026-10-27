import '../../../config/languages/app_localizations.dart';

abstract final class CleanerAuditLabels {
  static String? title(AppLocalizations l, String? id) => switch (id) {
    'developer_analysis_cache' => l.cleanerDeveloperAnalysisTitle,
    'developer_download_cache' => l.cleanerDeveloperDownloadsTitle,
    'electron_crash_reports' => l.cleanerElectronCrashTitle,
    'cpp_database_review' => l.cleanerReviewTitle('C/C++'),
    'vcpkg_artifacts_review' => l.cleanerReviewTitle('vcpkg'),
    'nvidia_shader_review' => l.cleanerReviewTitle('NVIDIA'),
    'unreal_ddc_review' => l.cleanerReviewTitle('Unreal Zen / DDC'),
    'pikpak_media_review' => l.cleanerReviewTitle('PikPak'),
    'installer_cache_review' => l.cleanerReviewTitle(
      'Visual Studio / Installer',
    ),
    _ => null,
  };

  static String? reason(AppLocalizations l, String? id) => switch (id) {
    'developer_analysis_cache' => l.cleanerDeveloperAnalysisReason,
    'developer_download_cache' => l.cleanerDeveloperDownloadsReason,
    'electron_crash_reports' => l.cleanerElectronCrashReason,
    'cpp_database_review' => l.cleanerCppDatabaseReason,
    'vcpkg_artifacts_review' => l.cleanerVcpkgReason,
    'nvidia_shader_review' => l.cleanerNvidiaReason,
    'unreal_ddc_review' => l.cleanerUnrealReason,
    'pikpak_media_review' => l.cleanerPikPakReason,
    'installer_cache_review' => l.cleanerInstallerReason,
    _ => null,
  };
}
