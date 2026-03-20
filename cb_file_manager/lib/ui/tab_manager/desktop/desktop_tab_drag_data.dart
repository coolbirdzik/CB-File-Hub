import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';

class DesktopTabDragData {
  final String tabId;
  final WindowTabPayload tab;

  const DesktopTabDragData({
    required this.tabId,
    required this.tab,
  });
}
