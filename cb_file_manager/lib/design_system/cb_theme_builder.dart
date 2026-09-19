import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cb_page_transitions.dart';
import 'cb_tokens.dart';
import 'primitives/cb_decorations.dart';
import 'tokens/cb_color_tokens.dart';
import 'tokens/cb_geometry_tokens.dart';
import 'tokens/cb_motion_tokens.dart';
import 'tokens/cb_type_tokens.dart';

/// Projects CoolBird tokens onto Flutter's [ThemeData].
///
/// This is the migration bridge. Most of the app still builds with Material
/// widgets, and rewriting every screen at once is not realistic — so instead
/// of leaving those screens on Material's defaults, every component theme
/// here is derived from the same tokens the CoolBird primitives use. An
/// un-migrated `ElevatedButton` comes out with the CoolBird accent, the
/// CoolBird radius and the CoolBird type ramp; migrating it to [CbButton]
/// later is then a refinement, not a visual change.
///
/// Three Material behaviours are switched off outright, because they are the
/// ones that make an app *read* as Material no matter how it is coloured:
///
///  1. **Surface tint.** M3 tints surfaces with the primary colour as they
///     rise. Every `surfaceTintColor` here is transparent; depth is shadow.
///  2. **Ink ripple.** Replaced with [NoSplash]; feedback is hover/press
///     colour, which is the pointer-driven convention.
///  3. **The `fromSeed` tonal palette.** The [ColorScheme] below is assembled
///     field by field from tokens, so no Material algorithm decides colour.
///
/// And one CoolBird rule is enforced on top: **flat, borderless chrome.**
/// Buttons, cards, chips, inputs, menus, dialogs and tooltips draw no
/// outline. Resting things separate from the page by a step on the fill
/// ramp, floating things by their shadow. The only lines left are dividers
/// (content structure) and focus/error indicators (state).
class CbThemeBuilder {
  const CbThemeBuilder._();

  /// Builds the app theme for [brightness] around the user's [accent].
  ///
  /// [extraExtensions] are appended to the theme's extension list alongside
  /// [CbTokens] — used to carry component themes that live outside the design
  /// system.
  static ThemeData build({
    required Brightness brightness,
    required Color accent,
    Color? textColor,
    Iterable<ThemeExtension> extraExtensions = const <ThemeExtension>[],
  }) {
    var tokens = CbTokens.of(brightness, accent);
    if (textColor != null) {
      final muted = _deriveMutedText(textColor, brightness);
      final tertiary = _deriveTertiaryText(textColor, brightness);
      tokens = tokens.copyWith(
        colors: tokens.colors.copyWith(
          textPrimary: textColor,
          textSecondary: muted,
          textTertiary: tertiary,
          icon: muted,
          iconSubtle: tertiary,
        ),
      );
    }
    final c = tokens.colors;
    final bool isDark = tokens.isDark;

    final colorScheme = _colorScheme(c, brightness);
    final textTheme = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryColor: c.accent.base,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.surface,
      dividerColor: c.stroke,
      shadowColor: c.shadow,
      fontFamily: CbTypography.uiFamily,
      fontFamilyFallback: CbTypography.uiFallback,

      // (2) No ink. A file manager is a grid of clickable rows; a ripple on
      // each one is noise rather than feedback.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: c.surfaceHover,
      focusColor: c.focusRing.withValues(alpha: 0.12),

      visualDensity: VisualDensity.compact,

      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: CbTypography.headingMd.copyWith(color: c.textPrimary),
        iconTheme: IconThemeData(color: c.icon, size: CbSizes.iconLg),
        actionsIconTheme: IconThemeData(color: c.icon, size: CbSizes.iconLg),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),

      iconTheme: IconThemeData(color: c.icon, size: CbSizes.iconMd),
      primaryIconTheme: IconThemeData(color: c.accent.base),

      dividerTheme: DividerThemeData(
        color: c.stroke,
        thickness: CbStrokes.hairline,
        space: CbStrokes.hairline,
      ),

      // ─── Buttons ─────────────────────────────────────────────────────────
      // Mirrors CbButton: 32px tall, 5px radius, label type, no elevation,
      // no outline. `OutlinedButton` keeps its name but renders as the
      // tonal secondary button — the outline was the only thing separating
      // it from a text button, and a fill does that job without a border.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _filledStyle(c, c.accent, isDark),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _filledStyle(c, c.accent, isDark),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _tonalStyle(c)),
      textButtonTheme: TextButtonThemeData(
        style: _baseButtonStyle(c).copyWith(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.textDisabled;
            return c.accent.text;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return c.surfacePressed;
            if (states.contains(WidgetState.hovered)) return c.surfaceHover;
            return Colors.transparent;
          }),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          iconSize: const WidgetStatePropertyAll(CbSizes.iconMd),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.textDisabled;
            if (states.contains(WidgetState.hovered)) return c.textPrimary;
            return c.icon;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return c.surfacePressed;
            if (states.contains(WidgetState.hovered)) return c.surfaceHover;
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: CbRadii.smAll),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(CbSpacing.xs)),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent.base,
        foregroundColor: c.accent.onBase,
        elevation: 0,
        hoverElevation: 0,
        focusElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: CbRadii.lgAll),
      ),

      // ─── Containers ──────────────────────────────────────────────────────
      // A card is a flat tonal block (same recipe as CbSurface.flat): the
      // translucent fill separates it on the canvas, inside a dialog and on
      // the acrylic backdrop alike, with no outline and no shadow.
      cardTheme: CardThemeData(
        color: c.fillSubtle,
        surfaceTintColor: Colors.transparent, // (1) no tinted elevation
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: CbRadii.mdAll),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        shadowColor: c.shadow,
        elevation: _floatingElevation,
        barrierColor: c.scrim,
        titleTextStyle: CbTypography.headingLg.copyWith(color: c.textPrimary),
        contentTextStyle: CbTypography.body.copyWith(color: c.textSecondary),
        shape: const RoundedRectangleBorder(borderRadius: CbRadii.xlAll),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceOverlay,
        modalBackgroundColor: c.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.strokeStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(CbRadii.xl)),
        ),
      ),

      // ─── Menus and popovers ──────────────────────────────────────────────
      // Floating layers: no outline, so the shadow carries the separation.
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: _floatingElevation,
        shadowColor: c.shadow,
        labelTextStyle: WidgetStatePropertyAll(
          CbTypography.body.copyWith(color: c.textPrimary),
        ),
        shape: const RoundedRectangleBorder(borderRadius: CbRadii.lgAll),
      ),

      menuTheme: MenuThemeData(style: _menuStyle(c)),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: _menuStyle(c),
        textStyle: CbTypography.body.copyWith(color: c.textPrimary),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size.fromHeight(CbSizes.controlMd),
          ),
          textStyle: WidgetStatePropertyAll(CbTypography.body),
          foregroundColor: WidgetStatePropertyAll(c.textPrimary),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return c.surfaceHover;
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: CbRadii.smAll),
          ),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        waitDuration: CbDurations.slow,
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.sm,
          vertical: CbSpacing.xs + 2,
        ),
        textStyle: CbTypography.bodySm.copyWith(color: c.textPrimary),
        decoration: BoxDecoration(
          color: c.surfaceOverlay,
          borderRadius: CbRadii.smAll,
          boxShadow: tokens.shadowLevel3,
        ),
      ),

      // ─── Inputs ──────────────────────────────────────────────────────────
      // Kept in step with CbTextField (CbDecorations.field): a tonal fill
      // with no outline, and a bottom indicator that turns accent on focus
      // and danger on error. Underline borders — not outline ones — so a
      // floating label sits inside the fill instead of cutting its edge.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.fillSubtle;
          return c.fill;
        }),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.sm + 2,
          vertical: CbSpacing.sm,
        ),
        hintStyle: CbTypography.body.copyWith(color: c.textTertiary),
        labelStyle: CbTypography.labelSm.copyWith(color: c.textSecondary),
        floatingLabelStyle: CbTypography.labelSm.copyWith(color: c.textPrimary),
        helperStyle: CbTypography.caption.copyWith(color: c.textTertiary),
        errorStyle: CbTypography.caption.copyWith(color: c.status.danger),
        border: _inputBorder(null),
        enabledBorder: _inputBorder(null),
        disabledBorder: _inputBorder(null),
        focusedBorder: _inputBorder(c.accent.base),
        errorBorder: _inputBorder(c.status.danger),
        focusedErrorBorder: _inputBorder(c.status.danger),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent.base,
        selectionColor: c.accent.base.withValues(alpha: 0.28),
        selectionHandleColor: c.accent.base,
      ),

      // ─── Selection controls ──────────────────────────────────────────────
      // Flat toggles: the unchecked box and the unselected radio are solid
      // fill steps, like the switch's off track — not stroked outlines. The
      // side is a WidgetStateBorderSide because a plain BorderSide only
      // applies while unselected; Material swaps in its own 2px ring once
      // the control is on.
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => _toggleFill(c, states),
        ),
        checkColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.surface;
          return c.accent.onBase;
        }),
        side: _noToggleSide,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbRadii.xs),
        ),
        splashRadius: 0,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      // Fluent radio: an accent disc with an on-accent dot that grows under
      // the pointer and shrinks while pressed, instead of Material's ring
      // around a same-colour dot.
      radioTheme: RadioThemeData(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => _toggleFill(c, states),
        ),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.surface;
          return c.accent.onBase;
        }),
        innerRadius: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return 3.5;
          if (states.contains(WidgetState.hovered)) return 5.0;
          return 4.25;
        }),
        side: _noToggleSide,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
        visualDensity: VisualDensity.compact,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.textDisabled;
          if (states.contains(WidgetState.selected)) return c.accent.onBase;
          return c.textSecondary;
        }),
        // Flat switch: the off track is a fill step, not an outlined pill.
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.fillSubtle;
          if (states.contains(WidgetState.selected)) return c.accent.base;
          if (states.contains(WidgetState.hovered)) return c.fillPressed;
          return c.fillHover;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent.base,
        inactiveTrackColor: c.fillPressed,
        thumbColor: c.accent.base,
        overlayColor: c.accent.base.withValues(alpha: 0.12),
        trackHeight: CbStrokes.emphasis * 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent.base,
        linearTrackColor: c.fillHover,
        circularTrackColor: c.fillHover,
        linearMinHeight: CbStrokes.emphasis,
      ),

      // ─── Lists, chips, tabs ──────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: c.icon,
        textColor: c.textPrimary,
        selectedColor: c.accent.text,
        selectedTileColor: c.surfaceSelected,
        titleTextStyle: CbTypography.body.copyWith(color: c.textPrimary),
        subtitleTextStyle: CbTypography.bodySm.copyWith(color: c.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
        minVerticalPadding: CbSpacing.xs,
        horizontalTitleGap: CbSpacing.md,
        shape: const RoundedRectangleBorder(borderRadius: CbRadii.smAll),
        visualDensity: VisualDensity.compact,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.fill,
        selectedColor: c.accent.tintStrong,
        disabledColor: c.fillSubtle,
        surfaceTintColor: Colors.transparent,
        labelStyle: CbTypography.labelSm.copyWith(color: c.textPrimary),
        secondaryLabelStyle: CbTypography.labelSm.copyWith(
          color: c.accent.text,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.sm,
          vertical: CbSpacing.xxs,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        elevation: 0,
        pressElevation: 0,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: _tonalStyle(c).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.fillSubtle;
            if (states.contains(WidgetState.selected)) {
              return states.contains(WidgetState.hovered)
                  ? c.accent.tintStrong
                  : c.surfaceSelected;
            }
            if (states.contains(WidgetState.pressed)) return c.fillPressed;
            if (states.contains(WidgetState.hovered)) return c.fillHover;
            return c.fill;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.textDisabled;
            if (states.contains(WidgetState.selected)) return c.accent.text;
            return c.textPrimary;
          }),
          fixedSize: const WidgetStatePropertyAll(null),
        ),
      ),

      toggleButtonsTheme: ToggleButtonsThemeData(
        color: c.textPrimary,
        selectedColor: c.accent.text,
        disabledColor: c.textDisabled,
        fillColor: c.surfaceSelected,
        hoverColor: c.surfaceHover,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderColor: Colors.transparent,
        selectedBorderColor: Colors.transparent,
        disabledBorderColor: Colors.transparent,
        borderRadius: CbRadii.smAll,
        borderWidth: 0,
      ),

      expansionTileTheme: ExpansionTileThemeData(
        iconColor: c.icon,
        collapsedIconColor: c.icon,
        textColor: c.textPrimary,
        collapsedTextColor: c.textPrimary,
        // Material draws divider lines above and below an expanded tile;
        // giving both shapes explicitly is what turns them off.
        shape: const RoundedRectangleBorder(borderRadius: CbRadii.smAll),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: CbRadii.smAll,
        ),
      ),

      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return c.fillHover;
          return c.fill;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide.none),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textSecondary,
        labelStyle: CbTypography.label,
        unselectedLabelStyle: CbTypography.body,
        indicatorSize: TabBarIndicatorSize.label,
        // Flat: the accent indicator marks the active tab; no full-width
        // rule under the whole bar.
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return c.surfaceHover;
          return Colors.transparent;
        }),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(
            color: c.accent.base,
            width: CbStrokes.emphasis,
          ),
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.canvas,
        indicatorColor: c.surfaceSelected,
        selectedIconTheme: IconThemeData(
          color: c.accent.text,
          size: CbSizes.iconLg,
        ),
        unselectedIconTheme: IconThemeData(color: c.icon, size: CbSizes.iconLg),
        selectedLabelTextStyle: CbTypography.labelSm.copyWith(
          color: c.textPrimary,
        ),
        unselectedLabelTextStyle: CbTypography.labelSm.copyWith(
          color: c.textSecondary,
        ),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceOverlay,
        contentTextStyle: CbTypography.body.copyWith(color: c.textPrimary),
        actionTextColor: c.accent.text,
        behavior: SnackBarBehavior.floating,
        elevation: _floatingElevation,
        shape: const RoundedRectangleBorder(borderRadius: CbRadii.lgAll),
      ),

      // ─── Scrollbar ───────────────────────────────────────────────────────
      // A neutral thumb that only picks up the accent while dragging; an
      // always-accent scrollbar competes with the content for attention.
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 11.0;
          }
          return 7.0;
        }),
        radius: const Radius.circular(CbRadii.full),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) return c.accent.base;
          if (states.contains(WidgetState.hovered)) return c.textTertiary;
          return isDark
              ? Colors.white.withValues(alpha: 0.20)
              : Colors.black.withValues(alpha: 0.20);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return c.surfaceHover;
          return Colors.transparent;
        }),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        minThumbLength: 40,
        crossAxisMargin: 2,
        mainAxisMargin: 2,
        interactive: true,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          // Phones draw edge-to-edge; every page is kept clear of the
          // system bars. Zoom is the transition these platforms already
          // fell back to.
          TargetPlatform.android: CbSafePageTransitionsBuilder(
            ZoomPageTransitionsBuilder(),
          ),
          TargetPlatform.iOS: CbSafePageTransitionsBuilder(
            ZoomPageTransitionsBuilder(),
          ),
        },
      ),
    ).copyWith(
      extensions: <ThemeExtension>[tokens].followedBy(extraExtensions),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  /// Material elevation for floating layers (menus, dialogs, snackbars).
  /// With no outline to separate them, a light-mode white menu over a white
  /// page is only distinguishable by its shadow.
  static const double _floatingElevation = 6;

  static ButtonStyle _baseButtonStyle(CbColorTokens c) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, CbSizes.controlMd)),
      fixedSize: const WidgetStatePropertyAll(
        Size.fromHeight(CbSizes.controlMd),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: CbSpacing.md),
      ),
      textStyle: WidgetStatePropertyAll(CbTypography.label),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      // Material derives its own overlay from the foreground colour; leaving
      // it non-transparent would reintroduce the ripple wash on top of the
      // explicit background states resolved below.
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      iconSize: const WidgetStatePropertyAll(CbSizes.iconMd),
      splashFactory: NoSplash.splashFactory,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: CbRadii.smAll),
      ),
      side: const WidgetStatePropertyAll(BorderSide.none),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.textDisabled;
        return c.textPrimary;
      }),
    );
  }

  static ButtonStyle _filledStyle(
    CbColorTokens c,
    CbAccentRamp accent,
    bool isDark,
  ) {
    return _baseButtonStyle(c).copyWith(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.textDisabled;
        return accent.onBase;
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.textDisabled;
        return accent.onBase;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.fillSubtle;
        if (states.contains(WidgetState.pressed)) return accent.pressed;
        if (states.contains(WidgetState.hovered)) return accent.hover;
        return accent.base;
      }),
    );
  }

  /// The neutral tonal button — CbButtonVariant.secondary for Material.
  static ButtonStyle _tonalStyle(CbColorTokens c) {
    return _baseButtonStyle(c).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return c.fillSubtle;
        if (states.contains(WidgetState.pressed)) return c.fillPressed;
        if (states.contains(WidgetState.hovered)) return c.fillHover;
        return c.fill;
      }),
    );
  }

  static MenuStyle _menuStyle(CbColorTokens c) {
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(c.surfaceOverlay),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(c.shadow),
      elevation: const WidgetStatePropertyAll(8),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: CbSpacing.xs),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: CbRadii.lgAll),
      ),
    );
  }

  static UnderlineInputBorder _inputBorder(Color? indicator) =>
      CbDecorations.inputBorder(indicator);

  /// Body of a checkbox or radio. Off is a solid neutral step — one heavier
  /// than the switch's off track, since the glyph is small and has nothing
  /// drawn inside it — and on is the accent; both step with hover and press.
  static Color _toggleFill(CbColorTokens c, Set<WidgetState> states) {
    final bool selected = states.contains(WidgetState.selected);
    if (states.contains(WidgetState.disabled)) {
      return selected ? c.textDisabled : c.fillSubtle;
    }
    if (selected) {
      if (states.contains(WidgetState.pressed)) return c.accent.pressed;
      if (states.contains(WidgetState.hovered)) return c.accent.hover;
      return c.accent.base;
    }
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.hovered)) {
      return c.strokeStrong;
    }
    return c.fillPressed;
  }

  /// No outline on a checkbox or radio in any state.
  static final WidgetStateBorderSide _noToggleSide =
      WidgetStateBorderSide.resolveWith((_) => BorderSide.none);

  static TextTheme _textTheme(CbColorTokens c) {
    Color primary(TextStyle s) => c.textPrimary;
    TextStyle on(TextStyle s, Color color) => s.copyWith(color: color);

    // Material's slot names are mapped onto the CoolBird ramp so that
    // `Theme.of(context).textTheme.bodyMedium` — used all over the app —
    // resolves to CoolBird metrics rather than Roboto's defaults.
    return TextTheme(
      displayLarge: on(CbTypography.displayLg, c.textPrimary),
      displayMedium: on(CbTypography.displayLg, c.textPrimary),
      displaySmall: on(CbTypography.displaySm, c.textPrimary),
      headlineLarge: on(CbTypography.displaySm, c.textPrimary),
      headlineMedium: on(CbTypography.headingLg, c.textPrimary),
      headlineSmall: on(CbTypography.headingMd, c.textPrimary),
      titleLarge: on(CbTypography.headingMd, c.textPrimary),
      titleMedium: on(CbTypography.headingSm, c.textPrimary),
      titleSmall: on(CbTypography.label, c.textPrimary),
      bodyLarge: on(CbTypography.bodyLg, c.textPrimary),
      // `bodyMedium` is Flutter's default for a bare `Text`, so it must be
      // the app's default UI size.
      bodyMedium: on(CbTypography.body, primary(CbTypography.body)),
      bodySmall: on(CbTypography.bodySm, c.textSecondary),
      labelLarge: on(CbTypography.label, c.textPrimary),
      labelMedium: on(CbTypography.labelSm, c.textSecondary),
      labelSmall: on(CbTypography.labelXs, c.textTertiary),
    );
  }

  /// Softens [primary] into secondary body copy for the active brightness.
  static Color _deriveMutedText(Color primary, Brightness brightness) {
    final hsl = HSLColor.fromColor(primary);
    if (brightness == Brightness.dark) {
      return hsl
          .withSaturation((hsl.saturation * 0.55).clamp(0.0, 1.0))
          .withLightness((hsl.lightness * 0.78).clamp(0.48, 0.78))
          .toColor();
    }
    return hsl
        .withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + 0.18).clamp(0.32, 0.58))
        .toColor();
  }

  /// Softer still — captions / tertiary labels.
  static Color _deriveTertiaryText(Color primary, Brightness brightness) {
    final hsl = HSLColor.fromColor(primary);
    if (brightness == Brightness.dark) {
      return hsl
          .withSaturation((hsl.saturation * 0.40).clamp(0.0, 1.0))
          .withLightness((hsl.lightness * 0.62).clamp(0.38, 0.68))
          .toColor();
    }
    return hsl
        .withSaturation((hsl.saturation * 0.35).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + 0.28).clamp(0.40, 0.66))
        .toColor();
  }

  /// Assembles the [ColorScheme] field by field from tokens.
  ///
  /// Deliberately *not* `ColorScheme.fromSeed`: that runs Material's tonal
  /// palette algorithm, which rotates hue, clamps chroma and picks its own
  /// contrast targets. Those decisions are the ones this design system exists
  /// to own. The scheme still has to be complete and coherent, because ~150
  /// un-migrated widgets read from it.
  static ColorScheme _colorScheme(CbColorTokens c, Brightness brightness) {
    return ColorScheme(
      brightness: brightness,
      primary: c.accent.base,
      onPrimary: c.accent.onBase,
      primaryContainer: c.accent.tint,
      onPrimaryContainer: c.accent.text,
      secondary: c.textSecondary,
      onSecondary: c.textInverse,
      secondaryContainer: Color.alphaBlend(c.fillHover, c.surface),
      onSecondaryContainer: c.textPrimary,
      tertiary: c.accent.text,
      onTertiary: c.textInverse,
      tertiaryContainer: c.accent.tintStrong,
      onTertiaryContainer: c.accent.text,
      error: c.status.danger,
      onError: c.textInverse,
      errorContainer: c.status.dangerSurface,
      onErrorContainer: c.status.danger,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      // The container ladder is the fill ramp laid over `surface`, so every
      // step is a visible tone rather than another white. Un-migrated
      // widgets paint cards as `surfaceContainerHighest.withValues(...)`;
      // with a white top step those cards only showed because of their
      // outline, and removing the outline would have erased them.
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: Color.alphaBlend(c.fillSubtle, c.surface),
      surfaceContainer: Color.alphaBlend(c.fill, c.surface),
      surfaceContainerHigh: Color.alphaBlend(c.fillHover, c.surface),
      surfaceContainerHighest: Color.alphaBlend(c.fillPressed, c.surface),
      surfaceDim: c.canvas,
      surfaceBright: c.surfaceRaised,
      // Opaque equivalents: `outline` is consumed by widgets that paint it on
      // unknown backgrounds, where a translucent stroke token would read
      // inconsistently.
      outline: Color.alphaBlend(c.strokeStrong, c.surface),
      outlineVariant: Color.alphaBlend(c.stroke, c.surface),
      shadow: c.shadow,
      scrim: c.scrim,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.surface,
      inversePrimary: c.accent.tint,
      // (1) The single field that drives M3's tinted elevation everywhere.
      surfaceTint: Colors.transparent,
    );
  }
}
