import 'dart:async';

import 'package:cb_file_manager/services/device_media_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

class FakeDeviceMediaAccess extends DeviceMediaAccess {
  bool supported = true;
  PermissionState state = PermissionState.authorized;
  final requests = <(RequestType, bool)>[];
  List<AssetPathEntity> paths = [];
  Future<List<AssetPathEntity>> Function()? loadSources;
  Future<List<AssetEntity>> Function(AssetPathEntity, int, int)? loadPage;
  ValueChanged<MethodCall>? callback;

  @override
  bool get isSupported => supported;

  @override
  Future<PermissionState> permission(
    RequestType type, {
    bool request = false,
  }) async {
    requests.add((type, request));
    return state;
  }

  @override
  Future<List<AssetPathEntity>> sources(RequestType type) async =>
      loadSources != null ? loadSources!() : paths;

  @override
  Future<List<AssetEntity>> page(
    AssetPathEntity source,
    int page,
    int size,
  ) async => loadPage != null ? loadPage!(source, page, size) : [];

  @override
  void watch(ValueChanged<MethodCall> callback) => this.callback = callback;

  @override
  void unwatch(ValueChanged<MethodCall> callback) => this.callback = null;
}

AssetEntity asset(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 100, height: 100);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native requests include All and use matching scoped permissions and media type',
    () async {
      const channel = MethodChannel('com.fluttercandies/photo_manager');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getAssetPathList') return {'data': []};
            return PermissionState.authorized.index;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final access = DeviceMediaAccess();
      for (final type in [RequestType.image, RequestType.video]) {
        await access.permission(type, request: true);
        await access.permission(type);
        await access.sources(type);
        final batch = calls.sublist(calls.length - 3);
        expect(batch.map((call) => call.method), [
          'requestPermissionExtend',
          'getPermissionState',
          'getAssetPathList',
        ]);
        for (final call in batch.take(2)) {
          expect(call.arguments['androidPermission'], {
            'type': type.value,
            'mediaLocation': false,
          });
        }
        expect(batch.last.arguments['hasAll'], isTrue);
        expect(batch.last.arguments['type'], type.value);
      }
    },
  );

  test(
    'images and videos request their own permission and reuse OS albums',
    () async {
      for (final type in [RequestType.image, RequestType.video]) {
        final access = FakeDeviceMediaAccess()
          ..paths = [
            AssetPathEntity(id: 'camera', name: 'Camera', type: type),
            AssetPathEntity(id: 'all', name: 'Recent', isAll: true, type: type),
            AssetPathEntity(id: 'camera', name: 'Camera', type: type),
          ];
        final library = DeviceMediaLibrary(type, access: access);
        await library.refresh(requestPermission: true);
        expect(access.requests, [(type, true)]);
        expect(library.sources.map((source) => source.id), ['all', 'camera']);
        expect(access.callback, isNotNull);
        library.dispose();
        expect(access.callback, isNull);
      }
    },
  );

  test(
    'limited access loads permitted albums, revocation clears cached sources',
    () async {
      final access = FakeDeviceMediaAccess()
        ..state = PermissionState.limited
        ..paths = [AssetPathEntity(id: 'all', name: 'Recent', isAll: true)];
      final library = DeviceMediaLibrary(RequestType.image, access: access);
      addTearDown(library.dispose);
      await library.refresh();
      expect(library.sources, hasLength(1));
      access.state = PermissionState.denied;
      await library.refresh();
      expect(library.sources, isEmpty);
      expect(access.requests.every((request) => !request.$2), isTrue);
    },
  );

  test(
    'late album listing cannot restore sources after permission revocation',
    () async {
      final oldListing = Completer<List<AssetPathEntity>>();
      final access = FakeDeviceMediaAccess()
        ..loadSources = () => oldListing.future;
      final library = DeviceMediaLibrary(RequestType.video, access: access);
      addTearDown(library.dispose);
      final oldRefresh = library.refresh();
      await Future<void>.delayed(Duration.zero);
      access.state = PermissionState.denied;
      await library.refresh();
      oldListing.complete([
        AssetPathEntity(id: 'all', name: 'Recent', isAll: true),
      ]);
      await oldRefresh;
      expect(library.permission, PermissionState.denied);
      expect(library.sources, isEmpty);
      expect(library.loading, isFalse);
    },
  );

  test(
    'page failure retries the same page and duplicate IDs are removed',
    () async {
      final calls = <int>[];
      var fail = true;
      final access = FakeDeviceMediaAccess()
        ..loadPage = (_, page, size) async {
          calls.add(page);
          if (page == 0) return [asset('a'), asset('b')];
          if (fail) {
            fail = false;
            throw StateError('temporarily unavailable');
          }
          return [asset('b')];
        };
      final pager = DeviceMediaPager(access, pageSize: 2);
      addTearDown(pager.dispose);
      await pager.reset(
        AssetPathEntity(id: 'all', name: 'Recent', isAll: true),
      );
      await pager.loadMore();
      expect(pager.error, isNotNull);
      await pager.loadMore();
      expect(calls, [0, 1, 1]);
      expect(pager.assets.map((asset) => asset.id), ['a', 'b']);
      expect(pager.hasMore, isFalse);
      expect(pager.error, isNull);
    },
  );

  test(
    'reset discards in-flight media when an album changes or access is revoked',
    () async {
      final pending = Completer<List<AssetEntity>>();
      final access = FakeDeviceMediaAccess()
        ..loadPage = (_, _, _) => pending.future;
      final pager = DeviceMediaPager(access);
      addTearDown(pager.dispose);
      final first = pager.reset(AssetPathEntity(id: 'old', name: 'Old'));
      await pager.reset(null);
      pending.complete([asset('private')]);
      await first;
      expect(pager.assets, isEmpty);
      expect(pager.hasMore, isFalse);
      expect(pager.loading, isFalse);
    },
  );

  test('a completion after disposal does not notify listeners', () async {
    final pending = Completer<List<AssetEntity>>();
    final access = FakeDeviceMediaAccess()
      ..loadPage = (_, _, _) => pending.future;
    final pager = DeviceMediaPager(access);
    final first = pager.reset(AssetPathEntity(id: 'old', name: 'Old'));
    pager.dispose();
    pending.complete([asset('a')]);
    await first;
  });
}
