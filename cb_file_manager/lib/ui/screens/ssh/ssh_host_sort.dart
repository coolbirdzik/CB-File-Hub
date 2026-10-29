import 'package:flutter/foundation.dart';

import '../../../helpers/core/text_utils.dart';
import '../../../services/ssh/ssh_profile_store.dart';

enum SshHostSortField { name, host, username, group }

/// Sort order of the saved-host collection, persisted like
/// `GridListViewController` persists the view mode. Choosing the active field
/// again flips its direction.
class SshHostSortController extends ChangeNotifier {
  SshHostSortController({this.load, this.save});

  final Future<String?> Function()? load;
  final Future<void> Function(String)? save;

  // Group, then name: the order the workspace used before sorting existed.
  SshHostSortField _field = SshHostSortField.group;
  bool _ascending = true;
  bool _changed = false, _disposed = false, _initialized = false;

  SshHostSortField get field => _field;
  bool get ascending => _ascending;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final restored = await load?.call();
    if (_disposed || _changed || restored == null) return;
    final [name, direction, ...] = '$restored:'.split(':');
    final field = SshHostSortField.values.asNameMap()[name];
    if (field == null) return;
    _field = field;
    _ascending = direction != 'desc';
    notifyListeners();
  }

  Future<void> select(SshHostSortField field) async {
    _changed = true;
    _ascending = field == _field ? !_ascending : true;
    _field = field;
    notifyListeners();
    await save?.call('${_field.name}:${_ascending ? 'asc' : 'desc'}');
  }

  int compare(SshProfile a, SshProfile b) {
    final primary = switch (_field) {
      SshHostSortField.name => 0,
      SshHostSortField.host => _compareAddress(a, b),
      SshHostSortField.username => TextUtils.compareNatural(
        a.username,
        b.username,
      ),
      SshHostSortField.group => TextUtils.compareNatural(a.group, b.group),
    };
    if (primary != 0) return _ascending ? primary : -primary;
    final name = TextUtils.compareNatural(a.name, b.name);
    if (name != 0) {
      return _field == SshHostSortField.name && !_ascending ? -name : name;
    }
    return a.id.compareTo(b.id);
  }

  static int _compareAddress(SshProfile a, SshProfile b) {
    final host = TextUtils.compareNatural(a.host, b.host);
    return host != 0 ? host : a.port.compareTo(b.port);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
