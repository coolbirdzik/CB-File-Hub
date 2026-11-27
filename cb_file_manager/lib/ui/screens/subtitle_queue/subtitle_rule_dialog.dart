import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../models/local_ai/local_ai_advisor_model.dart';
import '../../../models/objectbox/video_library.dart';
import '../../../services/local_ai/local_ai_advisor_service.dart';
import '../../../services/local_ai/subtitle_model_catalog.dart';
import '../../../services/media/subtitle_batch/subtitle_batch_models.dart';
import '../../../services/media/subtitle_preferences.dart';
import '../../../services/video_library_service.dart';

/// Label of a batch output mode.
String subtitleOutputModeLabel(AppLocalizations l, SubtitleFileMode mode) =>
    switch (mode) {
      SubtitleFileMode.appOnly => l.aiSubtitleFileAppOnly,
      SubtitleFileMode.askWhenDone => l.aiSubtitleFileAsk,
      SubtitleFileMode.subsFolder => l.aiSubtitleFileSubs,
      SubtitleFileMode.besideHidden => l.aiSubtitleFileHidden,
    };

String subtitleOutputModeHint(AppLocalizations l, SubtitleFileMode mode) =>
    switch (mode) {
      SubtitleFileMode.appOnly => l.aiSubtitleFileAppOnlyHint,
      SubtitleFileMode.askWhenDone => l.aiSubtitleFileAskHint,
      SubtitleFileMode.subsFolder => l.aiSubtitleFileSubsHint,
      SubtitleFileMode.besideHidden => l.aiSubtitleFileHiddenHint,
    };

/// Creates or edits a rule. The common choices (sources, languages, where
/// files go) come first; models and filters sit in a collapsed section.
class SubtitleRuleDialog extends StatefulWidget {
  final SubtitleBatchRule rule;
  final LocalAiAdvisorService models;
  final bool isNew;

  const SubtitleRuleDialog({
    super.key,
    required this.rule,
    required this.models,
    this.isNew = false,
  });

  @override
  State<SubtitleRuleDialog> createState() => _SubtitleRuleDialogState();
}

/// Opens the rule editor; completes with the edited rule, or null.
Future<SubtitleBatchRule?> showSubtitleRuleDialog(
  BuildContext context, {
  required SubtitleBatchRule rule,
  required LocalAiAdvisorService models,
  bool isNew = false,
}) => showDialog<SubtitleBatchRule>(
  context: context,
  barrierDismissible: false,
  barrierColor: context.cbColors.scrim,
  builder: (_) => SubtitleRuleDialog(rule: rule, models: models, isNew: isNew),
);

class _SubtitleRuleDialogState extends State<SubtitleRuleDialog> {
  late SubtitleBatchRule _rule = widget.rule;
  late final _name = TextEditingController(text: widget.rule.name);
  late final _extensions = TextEditingController(
    text: widget.rule.extensions.join(', '),
  );
  late final _pattern = TextEditingController(text: widget.rule.namePattern);
  List<VideoLibrary> _libraries = const [];
  bool _showSourceError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLibraries());
  }

  Future<void> _loadLibraries() async {
    try {
      final libraries = await VideoLibraryService().getAllLibraries();
      if (mounted) setState(() => _libraries = libraries);
    } catch (_) {
      // Folders still work without the library list.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _extensions.dispose();
    _pattern.dispose();
    super.dispose();
  }

  void _update(SubtitleBatchRule rule) => setState(() => _rule = rule);

  Future<void> _addFolder() async {
    final folder = await FilePicker.getDirectoryPath();
    if (folder == null || _rule.folders.contains(folder)) return;
    setState(() {
      _rule = _rule.copyWith(folders: [..._rule.folders, folder]);
      _showSourceError = false;
    });
  }

  void _addLibrary(int id) => setState(() {
    _rule = _rule.copyWith(libraryIds: [..._rule.libraryIds, id]);
    _showSourceError = false;
  });

  void _save() {
    if (!_rule.hasSources) {
      setState(() => _showSourceError = true);
      return;
    }
    final l = AppLocalizations.of(context)!;
    final name = _name.text.trim();
    Navigator.of(context).pop(
      _rule.copyWith(
        name: name.isEmpty ? l.subtitleRuleDefaultName : name,
        extensions: SubtitleBatchRule.parseExtensions(_extensions.text),
        namePattern: _pattern.text.trim(),
      ),
    );
  }

  Set<String> _installed(LocalModelPurpose purpose) => {
    for (final m in widget.models.getManagedModels())
      if (m.purpose == purpose) m.catalogId,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final missingModels =
        !_installed(LocalModelPurpose.speech).contains(_rule.speechModel) ||
        !_installed(
          LocalModelPurpose.translation,
        ).contains(_rule.translationModel);
    return CbDialog(
      title: widget.isNew ? l.subtitleRuleNew : l.subtitleRuleEdit,
      icon: PhosphorIconsLight.subtitles,
      width: 600,
      showCloseButton: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CbTextField(
            key: const ValueKey('subtitle-rule-name'),
            controller: _name,
            label: l.subtitleRuleName,
            placeholder: l.subtitleRuleDefaultName,
          ),
          _section(l.subtitleRuleSources),
          ..._sources(l),
          _section(l.aiSubtitleLanguagesSection),
          _pair(
            _languageChoice(l.aiSubtitleSource, _rule.sourceLanguage, {
              if (subtitleModelDetectsLanguage(_rule.speechModel))
                'auto': l.subtitleRuleAutoDetect,
              ...subtitleSourceLanguagesFor(_rule.speechModel),
            }, (v) => _update(_rule.copyWith(sourceLanguage: v))),
            _languageChoice(l.aiSubtitleTarget, _rule.targetLanguage, {
              SubtitlePreferences.followApp: l.subtitleRuleFollowApp,
              ...subtitleTargetLanguages,
            }, (v) => _update(_rule.copyWith(targetLanguage: v))),
          ),
          _switchRow(
            l.aiSubtitleBilingual,
            _rule.bilingual,
            (v) => _update(_rule.copyWith(bilingual: v)),
          ),
          _section(l.aiSubtitleFilesSection),
          CbSelect<SubtitleFileMode>(
            key: ValueKey('subtitle-rule-output:${_rule.outputMode.name}'),
            value: _rule.outputMode,
            expand: true,
            items: [
              for (final mode in subtitleBatchOutputModes)
                CbSelectItem(
                  value: mode,
                  label: subtitleOutputModeLabel(l, mode),
                ),
            ],
            onChanged: (mode) => _update(_rule.copyWith(outputMode: mode)),
          ),
          const SizedBox(height: CbSpacing.xs),
          _hint(subtitleOutputModeHint(l, _rule.outputMode)),
          _switchRow(
            l.subtitleRuleSkipExisting,
            _rule.skipExisting,
            (v) => _update(_rule.copyWith(skipExisting: v)),
          ),
          if (missingModels) ...[
            const SizedBox(height: CbSpacing.sm),
            _warning(l.subtitleRuleModelMissing),
          ],
          const SizedBox(height: CbSpacing.md),
          CbExpander(
            key: const ValueKey('subtitle-rule-advanced'),
            leading: const Icon(PhosphorIconsLight.slidersHorizontal),
            title: Text(l.advancedSettings),
            expanded: missingModels && !widget.isNew,
            headerPadding: const EdgeInsets.symmetric(
              horizontal: CbSpacing.md,
              vertical: CbSpacing.sm,
            ),
            contentPadding: const EdgeInsets.all(CbSpacing.md),
            children: [
              _modelChoice(
                l,
                LocalModelPurpose.speech,
                l.aiModelSpeech,
                _rule.speechModel,
                _setSpeechModel,
              ),
              const SizedBox(height: CbSpacing.md),
              _modelChoice(
                l,
                LocalModelPurpose.translation,
                l.aiModelTranslation,
                _rule.translationModel,
                (id) => _update(_rule.copyWith(translationModel: id)),
              ),
              const SizedBox(height: CbSpacing.lg),
              _pair(
                CbTextField(
                  controller: _extensions,
                  label: l.subtitleRuleExtensions,
                  placeholder: 'mp4, mkv',
                  helperText: l.subtitleRuleExtensionsHint,
                ),
                CbTextField(
                  controller: _pattern,
                  label: l.subtitleRuleNamePattern,
                  placeholder: '*S01E*',
                  helperText: l.subtitleRuleNamePatternHint,
                ),
              ),
              _switchRow(
                l.subtitleRuleEnabled,
                _rule.enabled,
                (v) => _update(_rule.copyWith(enabled: v)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        CbButton(
          onPressed: () => Navigator.of(context).pop(),
          label: l.cancel,
          variant: CbButtonVariant.ghost,
        ),
        CbButton(
          key: const ValueKey('subtitle-rule-save'),
          onPressed: _save,
          // Saving always rescans the rule, so new videos are queued too.
          icon: PhosphorIconsLight.magnifyingGlass,
          label: l.subtitleRuleSaveAndScan,
          variant: CbButtonVariant.primary,
        ),
      ],
    );
  }

  void _setSpeechModel(String id) {
    final languages = subtitleSourceLanguagesFor(id);
    final keepSource =
        languages.containsKey(_rule.sourceLanguage) ||
        (_rule.sourceLanguage == 'auto' && subtitleModelDetectsLanguage(id));
    _update(
      _rule.copyWith(
        speechModel: id,
        sourceLanguage: keepSource
            ? _rule.sourceLanguage
            : subtitleModelDetectsLanguage(id)
            ? 'auto'
            : languages.keys.first,
      ),
    );
  }

  List<Widget> _sources(AppLocalizations l) {
    final c = context.cbColors;
    final libraryNames = {for (final lib in _libraries) lib.id: lib.name};
    final available = _libraries
        .where((lib) => !_rule.libraryIds.contains(lib.id))
        .toList();
    final buttons = Wrap(
      spacing: CbSpacing.sm,
      runSpacing: CbSpacing.sm,
      alignment: WrapAlignment.center,
      children: [
        CbButton(
          key: const ValueKey('subtitle-rule-add-folder'),
          onPressed: () => unawaited(_addFolder()),
          icon: PhosphorIconsLight.folderPlus,
          label: l.subtitleRuleAddFolder,
          size: CbButtonSize.sm,
        ),
        if (available.isNotEmpty)
          PopupMenuButton<int>(
            tooltip: l.subtitleRuleAddLibrary,
            popUpAnimationStyle: CbPopoverTransition.menuStyleOf(context),
            onSelected: _addLibrary,
            itemBuilder: (_) => [
              for (final lib in available)
                PopupMenuItem(value: lib.id, child: Text(lib.name)),
            ],
            child: IgnorePointer(
              child: CbButton(
                onPressed: () {},
                icon: PhosphorIconsLight.filmStrip,
                label: l.subtitleRuleAddLibrary,
                size: CbButtonSize.sm,
              ),
            ),
          ),
      ],
    );
    if (!_rule.hasSources) {
      return [
        Container(
          padding: const EdgeInsets.all(CbSpacing.lg),
          decoration: BoxDecoration(
            color: c.fillSubtle,
            borderRadius: BorderRadius.circular(CbRadii.lg),
            border: Border.all(
              color: _showSourceError ? c.status.danger : c.strokeSubtle,
            ),
          ),
          child: Column(
            children: [
              Icon(PhosphorIconsLight.folders, size: 28, color: c.iconSubtle),
              const SizedBox(height: CbSpacing.sm),
              Text(
                _showSourceError
                    ? l.subtitleRuleNoSources
                    : l.subtitleRuleSourcesHint,
                textAlign: TextAlign.center,
                style: CbTypography.bodySm.copyWith(
                  color: _showSourceError ? c.status.danger : c.textSecondary,
                ),
              ),
              const SizedBox(height: CbSpacing.md),
              buttons,
            ],
          ),
        ),
      ];
    }
    return [
      for (final folder in _rule.folders)
        _sourceRow(
          PhosphorIconsLight.folder,
          folder,
          () => _update(
            _rule.copyWith(folders: [..._rule.folders]..remove(folder)),
          ),
        ),
      for (final id in _rule.libraryIds)
        _sourceRow(
          PhosphorIconsLight.filmStrip,
          '${l.videoLibrary}: ${libraryNames[id] ?? '#$id'}',
          () => _update(
            _rule.copyWith(libraryIds: [..._rule.libraryIds]..remove(id)),
          ),
        ),
      const SizedBox(height: CbSpacing.xs),
      Row(children: [buttons, const Spacer()]),
      _switchRow(
        l.subtitleRuleIncludeSubfolders,
        _rule.recursive,
        (v) => _update(_rule.copyWith(recursive: v)),
      ),
    ];
  }

  Widget _sourceRow(IconData icon, String text, VoidCallback onRemove) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: CbSpacing.xs),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          CbSpacing.md,
          CbSpacing.xs,
          CbSpacing.xs,
          CbSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: c.fillSubtle,
          borderRadius: BorderRadius.circular(CbRadii.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: CbSizes.iconMd, color: c.iconSubtle),
            const SizedBox(width: CbSpacing.sm),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: CbTypography.body.copyWith(color: c.textPrimary),
              ),
            ),
            CbButton.icon(
              onPressed: onRemove,
              icon: PhosphorIconsLight.x,
              tooltip: AppLocalizations.of(context)!.remove,
              size: CbButtonSize.xs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelChoice(
    AppLocalizations l,
    LocalModelPurpose purpose,
    String label,
    String selected,
    ValueChanged<String> changed,
  ) {
    final entries = SubtitleModelCatalog.forPurpose(purpose);
    final installed = _installed(purpose);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CbSelect<String>(
          key: ValueKey('subtitle-rule-model:${purpose.name}:$selected'),
          label: label,
          value: entries.any((e) => e.id == selected) ? selected : null,
          expand: true,
          items: [
            for (final e in entries)
              CbSelectItem(
                value: e.id,
                label: e.displayName,
                icon: installed.contains(e.id)
                    ? PhosphorIconsLight.checkCircle
                    : null,
              ),
          ],
          onChanged: changed,
        ),
        if (selected == SubtitleModelCatalog.nemotronId &&
            entries.any((entry) => entry.id == selected)) ...[
          const SizedBox(height: CbSpacing.xs),
          _hint(
            entries.firstWhere((entry) => entry.id == selected).description!,
          ),
        ],
        if (!installed.contains(selected)) ...[
          const SizedBox(height: CbSpacing.xs),
          _hint(
            l.subtitleRuleModelMissing,
            color: context.cbColors.status.warning,
          ),
        ],
      ],
    );
  }

  Widget _languageChoice(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> changed,
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
          CbSelectItem(value: e.key, label: e.value, keywords: e.key),
      ],
      onChanged: changed,
    );
  }

  /// Two controls side by side, stacked when the dialog is narrow.
  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 440
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: CbSpacing.lg),
              Expanded(child: b),
            ],
          )
        : Column(
            children: [
              a,
              const SizedBox(height: CbSpacing.md),
              b,
            ],
          ),
  );

  Widget _switchRow(String label, bool value, ValueChanged<bool> changed) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.only(top: CbSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: CbTypography.body.copyWith(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: CbSpacing.md),
          Switch.adaptive(
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: changed,
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: CbSpacing.xl, bottom: CbSpacing.sm),
    child: Text(
      title,
      style: CbTypography.headingSm.copyWith(
        color: context.cbColors.textPrimary,
      ),
    ),
  );

  Widget _hint(String text, {Color? color}) => Text(
    text,
    style: CbTypography.bodySm.copyWith(
      color: color ?? context.cbColors.textSecondary,
    ),
  );

  Widget _warning(String text) {
    final c = context.cbColors;
    return Container(
      padding: const EdgeInsets.all(CbSpacing.md),
      decoration: BoxDecoration(
        color: c.status.warningSurface,
        borderRadius: BorderRadius.circular(CbRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsLight.warning,
            size: CbSizes.iconMd,
            color: c.status.warning,
          ),
          const SizedBox(width: CbSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: CbTypography.bodySm.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
