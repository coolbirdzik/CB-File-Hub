import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';

/// Registers geometry without rebuilding or measuring each tile every frame.
class SelectionGeometryItem extends SingleChildRenderObjectWidget {
  const SelectionGeometryItem({
    super.key,
    required this.path,
    required this.controller,
    this.isFolder,
    required super.child,
  });
  final String path;
  final bool? isFolder;
  final TabbedFolderDragSelectionController? controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SelectionItemGeometry(path, controller, isFolder);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _SelectionItemGeometry).updateRegistration(
      path,
      controller,
      isFolder,
    );
  }
}

class _SelectionItemGeometry extends RenderProxyBox {
  _SelectionItemGeometry(this._path, this._controller, this._isFolder);
  bool? _isFolder;
  String _path;
  TabbedFolderDragSelectionController? _controller;

  void updateRegistration(
    String path,
    TabbedFolderDragSelectionController? controller,
    bool? isFolder,
  ) {
    if (_path == path &&
        identical(_controller, controller) &&
        _isFolder == isFolder) {
      return;
    }
    if (attached) _controller?.unregisterItemRenderBox(_path, this);
    _path = path;
    _controller = controller;
    _isFolder = isFolder;
    if (attached) {
      _controller?.registerItemRenderBox(_path, this, isFolder: _isFolder);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller?.registerItemRenderBox(_path, this, isFolder: _isFolder);
  }

  @override
  void detach() {
    _controller?.unregisterItemRenderBox(_path, this);
    super.detach();
  }
}
