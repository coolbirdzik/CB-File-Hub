import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../models/local_ai/local_ai_advisor_model.dart';
import '../../../../services/local_ai/local_ai_advisor_service.dart';
import '../../../../services/local_ai/local_model_downloads.dart';
import '../../../../services/local_ai/subtitle_model_catalog.dart';
import '../../../../services/media/subtitle_preferences.dart';
import 'subtitle_cache_controls.dart';

String modelPurposeLabel(AppLocalizations l, LocalModelPurpose purpose) =>
    switch (purpose) {
      LocalModelPurpose.chat => l.aiModelChat,
      LocalModelPurpose.speech => l.aiModelSpeech,
      LocalModelPurpose.translation => l.aiModelTranslation,
    };

class SubtitleSettingsPanel extends StatefulWidget {
  final LocalAiAdvisorService models;
  final LocalModelDownloads downloads;
  final VoidCallback? onManageModels;
  const SubtitleSettingsPanel({
    super.key,
    required this.models,
    required this.downloads,
    this.onManageModels,
  });
  @override
  State<SubtitleSettingsPanel> createState() => _SubtitleSettingsPanelState();
}

class _SubtitleSettingsPanelState extends State<SubtitleSettingsPanel> {
  SubtitlePreferences? _prefs;
  StreamSubscription<void>? _installed;
  @override
  void initState() {
    super.initState();
    _installed = widget.models.onInstalledModelsChanged.listen((_) {
      if (mounted) setState(() {});
    });
    widget.downloads.addListener(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    final shared = await SharedPreferences.getInstance();
    if (!mounted) return;
    _prefs = SubtitlePreferences.shared(shared);
    _prefs!.addListener(_changed);
    setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _installed?.cancel();
    widget.downloads.removeListener(_changed);
    _prefs?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final prefs = _prefs;
    if (prefs == null) return const LinearProgressIndicator();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('ai-subtitles-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.aiSubtitles),
            subtitle: Text(l.aiSubtitlesHint),
            value: prefs.enabled,
            onChanged: prefs.setEnabled,
          ),
          const SizedBox(height: 12),
          _modelChoice(
            l,
            LocalModelPurpose.speech,
            prefs.speechModel,
            prefs.setSpeechModel,
          ),
          const SizedBox(height: 12),
          _modelChoice(
            l,
            LocalModelPurpose.translation,
            prefs.translationModel,
            prefs.setTranslationModel,
          ),
          const SizedBox(height: 12),
          _languageChoice(l.aiSubtitleSource, prefs.resolvedSourceLanguage, {
            'auto': 'Auto detect',
            ...subtitleSourceLanguagesFor(prefs.speechModel),
          }, prefs.setSource),
          const SizedBox(height: 12),
          _languageChoice(l.aiSubtitleTarget, prefs.targetLanguage, {
            SubtitlePreferences.followApp: 'Follow app language',
            ...subtitleTargetLanguages,
          }, prefs.setTarget),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l.aiSubtitleBilingual),
            value: prefs.bilingual,
            onChanged: prefs.setBilingual,
          ),
          if (widget.onManageModels != null)
            TextButton.icon(
              key: const ValueKey('ai-subtitles-manage-models'),
              onPressed: widget.onManageModels,
              icon: const Icon(Icons.download_outlined),
              label: Text(l.aiSubtitleManage),
            ),
          const SubtitleCacheControls(),
        ],
      ),
    );
  }

  Widget _languageChoice(
    String label,
    String selected,
    Map<String, String> options,
    Future<void> Function(String) changed,
  ) {
    final field = DropdownButtonFormField<String>(
      key: ValueKey('$label:$selected'),
      initialValue: options.containsKey(selected)
          ? selected
          : options.keys.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (value) {
        if (value != null) unawaited(changed(value));
      },
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        IconButton(
          key: ValueKey('subtitle-language-search:$label'),
          tooltip: '${AppLocalizations.of(context)!.search}: $label',
          icon: const Icon(Icons.search),
          onPressed: () async {
            final value = await showDialog<String>(
              context: context,
              builder: (_) => _SubtitleLanguageSearch(
                label: label,
                selected: selected,
                options: options,
              ),
            );
            if (value != null && mounted) await changed(value);
          },
        ),
      ],
    );
  }

  Widget _modelChoice(
    AppLocalizations l,
    LocalModelPurpose purpose,
    String selected,
    Future<void> Function(String) changed,
  ) {
    final entries = SubtitleModelCatalog.entries
        .where((e) => e.purpose == purpose)
        .toList();
    final selectedEntry = entries.where((e) => e.id == selected).firstOrNull;
    final installed = widget.models.getManagedModels().any(
      (m) => m.catalogId == selected,
    );
    final download = widget.downloads[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('subtitle-model:${purpose.name}:$selected'),
          initialValue: selectedEntry?.id,
          isExpanded: true,
          decoration: InputDecoration(labelText: modelPurposeLabel(l, purpose)),
          items: entries
              .map(
                (e) =>
                    DropdownMenuItem(value: e.id, child: Text(e.displayName)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) unawaited(changed(value));
          },
        ),
        if (selectedEntry?.sizeBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${selectedEntry!.description ?? (selectedEntry.sizeBytes! >= 1000000000 ? '${(selectedEntry.sizeBytes! / 1000000000).toStringAsFixed(2)} GB' : '${(selectedEntry.sizeBytes! / 1000000).ceil()} MB')} · ${selectedEntry.license ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (!installed && selectedEntry != null) ...[
          const SizedBox(height: 6),
          if (download != null && !download.failed) ...[
            LinearProgressIndicator(value: download.progress),
            TextButton(
              onPressed: () => widget.downloads.cancel(selected),
              child: Text(l.cancel),
            ),
          ] else
            TextButton.icon(
              onPressed: () => widget.downloads.start(selectedEntry),
              icon: const Icon(Icons.download_outlined),
              label: Text(
                '${download?.failed == true ? l.retry : l.installModel} · ${selectedEntry.displayName}',
              ),
            ),
          if (download?.error != null)
            Text(
              download!.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ],
    );
  }
}

/// The full model language list remains A–Z, with English names and code search.
class _SubtitleLanguageSearch extends StatefulWidget {
  final String label, selected;
  final Map<String, String> options;
  const _SubtitleLanguageSearch({
    required this.label,
    required this.selected,
    required this.options,
  });
  @override
  State<_SubtitleLanguageSearch> createState() =>
      _SubtitleLanguageSearchState();
}

class _SubtitleLanguageSearchState extends State<_SubtitleLanguageSearch> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final entries = widget.options.entries
        .where(
          (entry) =>
              entry.value.toLowerCase().contains(_query) ||
              entry.key.toLowerCase().contains(_query),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 440,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('subtitle-language-filter'),
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.search,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    key: ValueKey('subtitle-language-option:${entry.key}'),
                    title: Text(entry.value),
                    selected: entry.key == widget.selected,
                    trailing: entry.key == widget.selected
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(context).pop(entry.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
