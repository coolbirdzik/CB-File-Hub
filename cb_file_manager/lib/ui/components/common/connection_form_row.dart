import 'package:material_ui/material_ui.dart';

import '../../../design_system/cb_design_system.dart';

/// Stacks fields on compact windows; desktop forms keep related fields together.
class ConnectionFormRow extends StatelessWidget {
  final Widget first, second;
  final int firstFlex, secondFlex;
  const ConnectionFormRow({
    super.key,
    required this.first,
    required this.second,
    this.firstFlex = 1,
    this.secondFlex = 1,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 520
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: CbSpacing.lg),
              second,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: firstFlex, child: first),
              const SizedBox(width: CbSpacing.xl),
              Expanded(flex: secondFlex, child: second),
            ],
          ),
  );
}
