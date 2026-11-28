import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/components/common/file_browser_preference_option.dart';
import 'package:material_ui/material_ui.dart';

/// Global file browser choices; irrelevant platform controls are omitted.
class FileBrowserSettingsSection extends StatefulWidget {
  const FileBrowserSettingsSection({super.key});

  @override
  State<FileBrowserSettingsSection> createState() =>
      _FileBrowserSettingsSectionState();
}

class _FileBrowserSettingsSectionState
    extends State<FileBrowserSettingsSection> {
  final _preferences = UserPreferences.instance;
  late final _optionChanges = Listenable.merge([
    _preferences.fileBrowserOptions,
    _preferences.allowFileExtensionRename,
  ]);
  bool _saving = false;

  Future<void> _save(Future<bool> Function() persist) async {
    setState(() => _saving = true);
    try {
      final saved = await persist();
      if (!saved && mounted) {
        AppToast.error(
          context,
          AppLocalizations.of(context)!.fileBrowserSaveFailed,
        );
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(
          context,
          AppLocalizations.of(context)!.fileBrowserSaveFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _optionChanges,
      builder: (context, _) => Column(
        children: [
          for (final option in FileBrowserPreferenceOption.available())
            _tile(
              option.label(l),
              option.description(l),
              option.icon,
              option.isEnabled(_preferences),
              (value) => option.setEnabled(_preferences, value),
            ),
        ],
      ),
    );
  }

  Widget _tile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Future<bool> Function(bool) persist,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(icon, size: 20),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    trailing: Switch(
      value: value,
      onChanged: _saving ? null : (value) => _save(() => persist(value)),
    ),
    onTap: _saving ? null : () => _save(() => persist(!value)),
  );
}
