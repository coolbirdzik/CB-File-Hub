import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

/// Reads the OS media index instead of recursively scanning shared storage.
/// Albums stay in Photos/MediaStore; nothing is imported into the app database.
class DeviceMediaAccess {
  static int _watchers = 0;
  static Future<void> _notifications = Future.value();

  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  PermissionRequestOption _options(RequestType type) => PermissionRequestOption(
    androidPermission: AndroidPermission(type: type, mediaLocation: false),
  );

  Future<PermissionState> permission(
    RequestType type, {
    bool request = false,
  }) => request
      ? PhotoManager.requestPermissionExtend(requestOption: _options(type))
      : PhotoManager.getPermissionState(requestOption: _options(type));

  Future<List<AssetPathEntity>> sources(RequestType type) =>
      PhotoManager.getAssetPathList(
        type: type,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate)],
        ),
      );

  Future<List<AssetEntity>> page(AssetPathEntity source, int page, int size) =>
      source.getAssetListPaged(page: page, size: size);

  Future<void> settings() => PhotoManager.openSetting();

  Future<void> selectMore(RequestType type) async {
    await PhotoManager.presentLimited(type: type);
  }

  void watch(ValueChanged<MethodCall> callback) {
    PhotoManager.addChangeCallback(callback);
    _watchers++;
    _updateNotifications();
  }

  void unwatch(ValueChanged<MethodCall> callback) {
    PhotoManager.removeChangeCallback(callback);
    _watchers--;
    _updateNotifications();
  }

  void _updateNotifications() {
    // Serialize native observer updates: closing one tab must not stop another,
    // and a late start must not leave observers running after the last tab closes.
    _notifications = _notifications
        .then((_) async {
          if (_watchers > 0) {
            await PhotoManager.startChangeNotify();
          } else {
            await PhotoManager.stopChangeNotify();
          }
        })
        .catchError((Object _) {});
  }
}

class DeviceMediaLibrary extends ChangeNotifier {
  DeviceMediaLibrary(this.type, {DeviceMediaAccess? access})
    : access = access ?? DeviceMediaAccess();

  final RequestType type;
  final DeviceMediaAccess access;
  List<AssetPathEntity> sources = [];
  PermissionState permission = PermissionState.notDetermined;
  bool loading = false;
  Object? error;
  int _generation = 0;
  bool _disposed = false;
  bool _watching = false;
  bool _requesting = false;
  Timer? _refreshTimer;

  Future<void> refresh({bool requestPermission = false}) async {
    if (_disposed || _requesting) return;
    final generation = ++_generation;
    _requesting = requestPermission;
    loading = true;
    error = null;
    // Clear previously accessible data immediately when rechecking permissions.
    sources = [];
    notifyListeners();
    try {
      final state = await access.permission(type, request: requestPermission);
      if (!_current(generation)) return;
      permission = state;
      if (state.hasAccess) {
        final paths = await access.sources(type);
        if (!_current(generation)) return;
        final ids = <String>{};
        sources = paths.where((path) => ids.add(path.id)).toList()
          ..sort((a, b) {
            if (a.isAll != b.isAll) return a.isAll ? -1 : 1;
            return a.name.compareTo(b.name);
          });
        if (!_watching) {
          _watching = true;
          access.watch(_onChange);
        }
      }
    } catch (e) {
      if (_current(generation)) error = e;
    } finally {
      if (_current(generation)) {
        _requesting = false;
        loading = false;
        notifyListeners();
      }
    }
  }

  bool _current(int generation) => !_disposed && _generation == generation;

  void _onChange(MethodCall _) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 300), refresh);
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    if (_watching) access.unwatch(_onChange);
    super.dispose();
  }
}

/// Bounded, lazy asset loading. Refresh invalidates any in-flight older page.
class DeviceMediaPager extends ChangeNotifier {
  DeviceMediaPager(this.access, {this.pageSize = 60});

  final DeviceMediaAccess access;
  final int pageSize;
  List<AssetEntity> assets = [];
  bool loading = false;
  bool hasMore = true;
  Object? error;
  AssetPathEntity? _source;
  int _page = 0;
  int _generation = 0;
  bool _disposed = false;

  Future<void> reset(AssetPathEntity? source) async {
    ++_generation;
    _source = source;
    _page = 0;
    assets = [];
    loading = false;
    error = null;
    hasMore = source != null;
    notifyListeners();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore || _source == null) return;
    final generation = _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await access.page(_source!, _page, pageSize);
      if (_disposed || generation != _generation) return;
      final ids = assets.map((asset) => asset.id).toSet();
      assets = [...assets, ...page.where((asset) => ids.add(asset.id))];
      hasMore = page.length == pageSize;
      _page++;
    } catch (e) {
      if (!_disposed && generation == _generation) error = e;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
