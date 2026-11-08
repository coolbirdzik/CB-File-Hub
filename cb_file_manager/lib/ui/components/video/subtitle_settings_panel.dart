import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../design_system/cb_design_system.dart';
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
        CbSelect<SubtitleFileMode>(
          key: ValueKey('ai-subtitle-file-mode:${selected.name}'),
          value: selected,
          expand: true,
          items: [
            for (final mode in SubtitleFileMode.available)
              CbSelectItem(value: mode, label: text(mode).$1),
          ],
          onChanged: (mode) => unawaited(prefs.setFileMode(mode)),
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
    final l = AppLocalizations.of(context)!;
    return CbSelect<String>(
      key: ValueKey('$label:$selected'),
      label: label,
      value: options.containsKey(selected) ? selected : options.keys.first,
      expand: true,
      searchable: options.length > 8,
      searchPlaceholder: l.search,
      items: [
        for (final e in options.entries)
          // The code is matched by the filter but never shown.
          CbSelectItem(value: e.key, label: e.value, keywords: e.key),
      ],
      onChanged: (value) => unawaited(changed(value)),
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
        CbSelect<String>(
          key: ValueKey('subtitle-model:${purpose.name}:$selected'),
          label: modelPurposeLabel(l, purpose),
          value: selectedEntry?.id,
          expand: true,
          items: [
            for (final e in entries)
              CbSelectItem(
                value: e.id,
                label: e.sizeBytes == null
                    ? e.displayName
                    : '${e.displayName} · ${_size(e)}',
                triggerLabel: e.displayName,
                icon: installedIds.contains(e.id)
                    ? PhosphorIconsLight.checkCircle
                    : null,
              ),
          ],
          onChanged: (value) => unawaited(changed(value)),
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
