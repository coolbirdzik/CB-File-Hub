import 'package:flutter/material.dart';
import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';

/// Asks for a file or folder name and pops it trimmed.
class SftpNameDialog extends StatefulWidget {
  const SftpNameDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.action,
    required this.placeholder,
    required this.initial,
  });
  final String title, action, placeholder, initial;
  final IconData icon;

  @override
  State<SftpNameDialog> createState() => _SftpNameDialogState();
}

class _SftpNameDialogState extends State<SftpNameDialog> {
  // The extension stays out of the selection, so typing replaces the name.
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.lastIndexOf('.') > 0
          ? widget.initial.lastIndexOf('.')
          : widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) => CbDialog(
    title: widget.title,
    icon: widget.icon,
    width: 420,
    content: CbTextField(
      key: const ValueKey('sftp-transfer-name'),
      controller: _controller,
      placeholder: widget.placeholder,
      autofocus: true,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      CbButton(
        label: context.tr.cancel,
        onPressed: () => Navigator.pop(context),
      ),
      CbButton(
        label: widget.action,
        variant: CbButtonVariant.primary,
        onPressed: _submit,
      ),
    ],
  );
}
