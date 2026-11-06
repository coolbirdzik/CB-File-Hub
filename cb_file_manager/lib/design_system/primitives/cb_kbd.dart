import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_decorations.dart';

/// Keyboard key caps — `Ctrl` `K`, `↵`, `Esc` — shown beside menu items and
/// in the command palette footer.
///
/// Each entry of [keys] is drawn as its own cap, so a chord reads as
/// separate keys the way Raycast shows them, without a `+` between them.
class CbKbd extends StatelessWidget {
  final List<String> keys;

  /// Cap height. 20 suits a list row; 18 a dense footer.
  final double height;

  const CbKbd(this.keys, {super.key, this.height = 20});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final style = CbTypography.labelXs.copyWith(
      color: c.textSecondary,
      height: 1,
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: CbSpacing.xxs + 1),
            Container(
              height: height,
              constraints: BoxConstraints(minWidth: height),
              padding: const EdgeInsets.symmetric(horizontal: CbSpacing.xs + 1),
              alignment: Alignment.center,
              decoration: CbDecorations.kbd(context),
              child: Text(keys[i], style: style),
            ),
          ],
        ],
      ),
    );
  }
}
