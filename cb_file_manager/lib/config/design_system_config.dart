/// Global feature flags for desktop visual system rollout.
class DesignSystemConfig {
  const DesignSystemConfig._();

  /// Enables the desktop Fluent host shell.
  static const bool enableFluentDesktopShell = bool.fromEnvironment(
    'CB_ENABLE_FLUENT_DESKTOP_SHELL',
    defaultValue: true,
  );

  /// Forces desktop to keep the legacy Material host shell.
  static const bool enableLegacyMaterialDesktopShell = bool.fromEnvironment(
    'CB_ENABLE_LEGACY_MATERIAL_DESKTOP_SHELL',
    defaultValue: false,
  );

  /// Enables desktop acrylic visuals in the app shell.
  static const bool enableDesktopAcrylicWindowBackground = bool.fromEnvironment(
    'CB_ENABLE_DESKTOP_ACRYLIC_WINDOW_BG',
    defaultValue: true,
  );

  /// Keeps acrylic enabled on Windows 10.
  static const bool keepAcrylicOnWindows10 = bool.fromEnvironment(
    'CB_KEEP_WIN10_ACRYLIC',
    defaultValue: true,
  );
}
