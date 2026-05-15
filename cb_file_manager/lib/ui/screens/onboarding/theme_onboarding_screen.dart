import 'dart:ui';

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

  Widget _buildContinueButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: _saving ? null : _continue,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _saving
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr.themeOnboardingContinue,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(PhosphorIconsLight.arrowRight, size: 18),
                ],
              ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final selectedTheme = _selectedTheme ?? AppThemeType.light;
    final isLightSelected = selectedTheme == AppThemeType.light;
    final isDarkSelected = selectedTheme == AppThemeType.dark;
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      opacity: _showContent ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        offset: _showContent ? Offset.zero : const Offset(0, 0.04),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 28),
                          AnimatedScale(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutBack,
                            scale: _showContent ? 1 : 0.92,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(44),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 20,
                                  sigmaY: 20,
                                ),
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(44),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.white.withValues(alpha: 0.7),
                                      width: 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      width: 64,
                                      height: 64,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
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
                          Column(
                            children: [
                              _ThemeCardOption(
                                label: context.tr.themeOnboardingLightLabel,
                                icon: PhosphorIconsLight.sun,
                                selected: isLightSelected,
                                onTap: () => _previewTheme(AppThemeType.light),
                              ),
                              const SizedBox(height: 12),
                              _ThemeCardOption(
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
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 8, 48, 24),
              child: _buildContinueButton(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.embedded) {
      final bg = (theme.dialogTheme.backgroundColor ??
              theme.colorScheme.surfaceContainerHigh)
          .withValues(alpha: 1);
      return ColoredBox(color: bg, child: _buildBody(context));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Acrylic glass background
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                color: isDark
                    ? theme.colorScheme.surface.withValues(alpha: 0.72)
                    : theme.colorScheme.surface.withValues(alpha: 0.82),
              ),
            ),
          ),
          SafeArea(child: _buildBody(context)),
        ],
      ),
    );
  }
}

class _ThemeCardOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCardOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.10)
              : isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: selected ? 1.0 : 0.0,
              child: Icon(
                PhosphorIconsLight.checkCircle,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
