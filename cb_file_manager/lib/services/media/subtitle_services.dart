import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local_ai/local_ai_advisor_service.dart';
import '../local_ai/local_model_downloads.dart';
import 'subtitle_preferences.dart';
import 'subtitle_cache.dart';

/// A video/PiP process may not bootstrap the full file browser service locator.
/// Both entry points still share the same persisted model registry and folder.
class SubtitleServices {
  final LocalAiAdvisorService models;
  final LocalModelDownloads downloads;
  final SubtitlePreferences preferences;
  SubtitleCache get cache => SubtitleCache.instance;
  SubtitleServices(this.models, this.downloads, this.preferences);
  static Future<SubtitleServices>? _standalone;
  static Future<SubtitleServices> load() =>
      GetIt.I.isRegistered<LocalAiAdvisorService>()
      ? _load()
      : (_standalone ??= _load());
  static Future<SubtitleServices> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final models = GetIt.I.isRegistered<LocalAiAdvisorService>()
        ? GetIt.I<LocalAiAdvisorService>()
        : LocalAiAdvisorService(prefs: prefs);
    final downloads = GetIt.I.isRegistered<LocalModelDownloads>()
        ? GetIt.I<LocalModelDownloads>()
        : LocalModelDownloads(models);
    return SubtitleServices(
      models,
      downloads,
      SubtitlePreferences.shared(prefs),
    );
  }
}
