import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../config/translation_helper.dart';
import '../../../config/theme_config.dart';
import '../../../providers/theme_provider.dart';

class ThemeOnboardingScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onCompleted;

  const ThemeOnboardingScreen({
    Key? key,
    this.embedded = false,
    this.onCompleted,
  }) : super(key: key);

  @override
  State<ThemeOnboardingScreen> createState() => _ThemeOnboardingScreenState();
}

class _ThemeOnboardingScreenState extends State<ThemeOnboardingScreen> {
  AppThemeType? _selectedTheme;
  bool _saving = false;
  bool _showContent = false;

  @override
  void initState() {
    super.initState();
    final currentTheme = context.read<ThemeProvider>().currentTheme;
    _selectedTheme =
        _isDarkTheme(currentTheme) ? AppThemeType.dark : AppThemeType.light;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _showContent = true);
      }
    });
  }

  bool _isDarkTheme(AppThemeType theme) {
    return theme == AppThemeType.dark;
  }

  Future<void> _previewTheme(AppThemeType themeType) async {
    if (_saving || _selectedTheme == themeType) return;

    setState(() => _selectedTheme = themeType);
    await context.read<ThemeProvider>().setTheme(themeType);
  }

  Future<void> _continue() async {
    if (_selectedTheme == null || _saving) return;
    setState(() => _saving = true);

    final provider = context.read<ThemeProvider>();
    await provider.setTheme(_selectedTheme!);

    if (!mounted) return;
    if (widget.onCompleted != null) {
      widget.onCompleted!();
      return;
    }
    Navigator.of(context).pop();
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final selectedTheme = _selectedTheme ?? AppThemeType.light;
    final isLightSelected = selectedTheme == AppThemeType.light;
    final isDarkSelected = selectedTheme == AppThemeType.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                opacity: _showContent ? 1 : 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  offset: _showContent ? Offset.zero : const Offset(0, 0.04),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 28,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutBack,
                            scale: _showContent ? 1 : 0.92,
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      PhosphorIconsLight.folder,
                                      size: 34,
                                      color: theme.colorScheme.primary,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            context.tr.themeOnboardingTitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            context.tr.themeOnboardingDescription,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 36),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 28,
                            runSpacing: 20,
                            children: [
                              _ThemeCircleOption(
                                label: context.tr.themeOnboardingLightLabel,
                                icon: PhosphorIconsLight.sun,
                                selected: isLightSelected,
                                onTap: () => _previewTheme(AppThemeType.light),
                              ),
                              _ThemeCircleOption(
                                label: context.tr.themeOnboardingDarkLabel,
                                icon: PhosphorIconsLight.moon,
                                selected: isDarkSelected,
                                onTap: () => _previewTheme(AppThemeType.dark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            context.tr.themeOnboardingMoreThemesMessage,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _saving ? null : _continue,
                              child: _saving
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                            context.tr.themeOnboardingContinue),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          PhosphorIconsLight.arrowRight,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody(context);
    }
    return Scaffold(
      body: SafeArea(child: _buildBody(context)),
    );
  }
}

class _ThemeCircleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCircleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: selected ? 1.0 : 0.97,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    icon,
                    size: 44,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: selected ? 1 : 0,
                      child: Icon(
                        PhosphorIconsLight.checkCircle,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
