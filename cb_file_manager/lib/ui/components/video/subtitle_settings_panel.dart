import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../models/local_ai/local_ai_advisor_model.dart';
import '../../../../services/local_ai/local_ai_advisor_service.dart';
import '../../../../services/local_ai/local_model_downloads.dart';
import '../../../../services/local_ai/subtitle_model_catalog.dart';
import '../../../../services/media/subtitle_preferences.dart';
import '../../../../services/media/subtitle_cache.dart';
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
  final SubtitleCache? cache;
  const SubtitleSettingsPanel({
    super.key,
    required this.models,
    required this.downloads,
    this.onManageModels,
    this.cache,
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
    final source =
        _languageChoice(l.aiSubtitleSource, prefs.resolvedSourceLanguage, {
          if (subtitleModelDetectsLanguage(prefs.speechModel))
            'auto': 'Auto detect',
          ...subtitleSourceLanguagesFor(prefs.speechModel),
        }, prefs.setSource);
    final target = _languageChoice(l.aiSubtitleTarget, prefs.targetLanguage, {
      SubtitlePreferences.followApp: 'Follow app language',
      ...subtitleTargetLanguages,
    }, prefs.setTarget);
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
          _sectionHeader(l.aiSubtitleModelsSection),
          _modelChoice(
            l,
            LocalModelPurpose.speech,
            prefs.speechModel,
            prefs.setSpeechModel,
          ),
          const SizedBox(height: 16),
          _modelChoice(
            l,
            LocalModelPurpose.translation,
            prefs.translationModel,
            prefs.setTranslationModel,
          ),
          if (widget.onManageModels != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('ai-subtitles-manage-models'),
                onPressed: widget.onManageModels,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(l.aiSubtitleManage),
              ),
            ),
          _sectionHeader(l.aiSubtitleLanguagesSection),
          // Side by side only when each field keeps room for long names; the
          // 520 px player dialog stays single-column.
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 560
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: source),
                      const SizedBox(width: 16),
                      Expanded(child: target),
                    ],
                  )
                : Column(
                    children: [source, const SizedBox(height: 12), target],
                  ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l.aiSubtitleBilingual),
            value: prefs.bilingual,
            onChanged: prefs.setBilingual,
          ),
          _sectionHeader(l.aiSubtitleFilesSection),
          _fileModeChoice(l, prefs),
          SubtitleCacheControls(cache: widget.cache),
        ],
      ),
    );
  }

  Widget _fileModeChoice(AppLocalizations l, SubtitlePreferences prefs) {
    final theme = Theme.of(context);
    final selected = prefs.fileMode;
    (String, String) text(SubtitleFileMode mode) => switch (mode) {
      SubtitleFileMode.appOnly => (
        l.aiSubtitleFileAppOnly,
        l.aiSubtitleFileAppOnlyHint,
      ),
      SubtitleFileMode.askWhenDone => (
        l.aiSubtitleFileAsk,
        l.aiSubtitleFileAskHint,
      ),
      SubtitleFileMode.subsFolder => (
        l.aiSubtitleFileSubs,
        l.aiSubtitleFileSubsHint,
      ),
      SubtitleFileMode.besideHidden => (
        l.aiSubtitleFileHidden,
        l.aiSubtitleFileHiddenHint,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<SubtitleFileMode>(
          key: ValueKey('ai-subtitle-file-mode:${selected.name}'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.aiSubtitleFilesSection),
          items: [
            for (final mode in SubtitleFileMode.available)
              DropdownMenuItem(
                value: mode,
                child: Text(text(mode).$1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (mode) {
            if (mode != null) unawaited(prefs.setFileMode(mode));
          },
        ),
        const SizedBox(height: 6),
        Text(
          text(selected).$2,
          key: const ValueKey('ai-subtitle-file-mode-hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
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
        const SizedBox(width: 4),
        IconButton(
          key: ValueKey('subtitle-language-search:$label'),
          tooltip: '${AppLocalizations.of(context)!.search}: $label',
          icon: const Icon(Icons.search),
          onPressed: options.length < 2
              ? null
              : () async {
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

  /// Decimal units, matching the publisher listing and the docs table.
  static String _size(HuggingFaceModelEntry entry) {
    final bytes = entry.sizeBytes;
    if (bytes == null) return '';
    return bytes >= 1000000000
        ? '${(bytes / 1000000000).toStringAsFixed(2)} GB'
        : '${(bytes / 1000000).round()} MB';
  }

  static String _tierLabel(AppLocalizations l, SubtitleModelTier tier) =>
      switch (tier) {
        SubtitleModelTier.fast => l.aiModelTierFast,
        SubtitleModelTier.balanced => l.aiModelTierBalanced,
        SubtitleModelTier.accurate => l.aiModelTierAccurate,
      };

  Widget _modelChoice(
    AppLocalizations l,
    LocalModelPurpose purpose,
    String selected,
    Future<void> Function(String) changed,
  ) {
    final theme = Theme.of(context);
    final entries = SubtitleModelCatalog.forPurpose(purpose);
    final selectedEntry = entries.where((e) => e.id == selected).firstOrNull;
    final installedIds = {
      for (final m in widget.models.getManagedModels())
        if (m.purpose == purpose) m.catalogId,
    };
    final installed = installedIds.contains(selected);
    final download = widget.downloads[selected];
    final profile = SubtitleModelCatalog.profiles[selected];
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('subtitle-model:${purpose.name}:$selected'),
          initialValue: selectedEntry?.id,
          isExpanded: true,
          decoration: InputDecoration(labelText: modelPurposeLabel(l, purpose)),
          selectedItemBuilder: (_) => [
            for (final e in entries)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(e.displayName, overflow: TextOverflow.ellipsis),
              ),
          ],
          items: [
            for (final e in entries)
              DropdownMenuItem(
                value: e.id,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (installedIds.contains(e.id))
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Icon(
                          Icons.check_circle,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(_size(e), style: muted),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) unawaited(changed(value));
          },
        ),
        if (selectedEntry != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (profile?.recommended == true)
                _tag(l.localModelRecommended, highlight: true),
              if (profile != null) _tag(_tierLabel(l, profile.tier)),
              if (selectedEntry.sizeBytes != null) _tag(_size(selectedEntry)),
              if (selectedEntry.license != null) _tag(selectedEntry.license!),
              if (installed)
                _tag(
                  l.localModelInstalledBadge,
                  highlight: true,
                  icon: Icons.check,
                ),
            ],
          ),
          if (selectedEntry.description != null) ...[
            const SizedBox(height: 6),
            Text(selectedEntry.description!, style: muted),
          ],
          if (!installed) ...[
            const SizedBox(height: 8),
            if (download != null && !download.failed)
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(value: download.progress),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => widget.downloads.cancel(selected),
                    child: Text(l.cancel),
                  ),
                ],
              )
            else
              FilledButton.tonalIcon(
                key: ValueKey('subtitle-model-install:$selected'),
                onPressed: () => widget.downloads.start(selectedEntry),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(
                  '${download?.failed == true ? l.retry : l.installModel} · ${_size(selectedEntry)}',
                ),
              ),
            if (download?.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  download!.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _tag(String label, {bool highlight = false, IconData? icon}) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
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
