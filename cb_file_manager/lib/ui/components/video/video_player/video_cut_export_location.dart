import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/translation_helper.dart';
import '../../../../design_system/cb_design_system.dart';

enum VideoCutExportLocation { besideSource, otherFolder }

Future<VideoCutExportLocation?> chooseVideoCutExportLocation(
  BuildContext context,
  String source,
) => showDialog<VideoCutExportLocation>(
  context: context,
  builder: (dialogContext) => CbDialog(
    title: dialogContext.tr.cutOutputFolder,
    icon: PhosphorIconsLight.folderOpen,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(dialogContext.tr.cutInPlaceHint),
        const SizedBox(height: CbSpacing.sm),
        SelectableText(
          p.dirname(p.absolute(source)),
          style: CbTypography.bodySm,
        ),
        const SizedBox(height: CbSpacing.lg),
        CbButton(
          label: dialogContext.tr.cutInPlace,
          icon: PhosphorIconsLight.folder,
          expand: true,
          variant: CbButtonVariant.primary,
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(VideoCutExportLocation.besideSource),
        ),
        const SizedBox(height: CbSpacing.sm),
        CbButton(
          label: dialogContext.tr.cutChooseOtherFolder,
          icon: PhosphorIconsLight.folderOpen,
          expand: true,
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(VideoCutExportLocation.otherFolder),
        ),
      ],
    ),
    actions: [
      CbButton(
        label: dialogContext.tr.cancel,
        variant: CbButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  ),
);
