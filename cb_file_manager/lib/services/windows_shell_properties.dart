import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart' as win32;

/// Windows Shell properties (the ones Explorer shows as Details columns),
/// read through `IShellItem2` and formatted with `PSFormatForDisplayAlloc`,
/// so values look exactly like Explorer's ("1920 x 1080", "128kbps", ...).
///
/// Property handlers may open the file, so every read runs on one worker
/// isolate. Requests made within a frame are sent as one batch, results are
/// cached per path and property.
class WindowsShellProperties {
  WindowsShellProperties._();

  static final instance = WindowsShellProperties._();

  static bool get isSupported => Platform.isWindows;

  static const _maxCacheSize = 6000;
  final Map<String, String> _cache = {};
  final Map<String, Completer<String>> _pending = {};
  final Map<String, Set<String>> _queued = {};
  Future<SendPort>? _worker;
  Timer? _flush;
  Future<List<SystemPropertyColumn>>? _systemColumns;
  Map<String, String> _systemLabels = const {};

  /// The display text of [property] (a [ShellProperty] name) of [path];
  /// empty when the file has no such value.
  Future<String> get(String path, String property) {
    if (!isSupported) return Future.value('');
    final key = '$property\u0000$path';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    final pending = _pending[key];
    if (pending != null) return pending.future;
    final completer = _pending[key] = Completer<String>();
    (_queued[path] ??= {}).add(property);
    _flush ??= Timer(
      property.startsWith('sort:')
          ? Duration.zero
          : const Duration(milliseconds: 16),
      _send,
    );
    return completer.future;
  }

  /// Cached text, without starting a read.
  ///
  /// Sort requests use canonical numeric/time values from the same worker.
  Future<String> getSortKey(String path, String property) =>
      get(path, 'sort:$property');

  /// Cached display text, without starting a read.
  String? peek(String path, String property) => _cache['$property\u0000$path'];

  void invalidate(String path) =>
      _cache.removeWhere((key, _) => key.endsWith('\u0000$path'));

  /// Every property Windows offers as a Details column (what Explorer's
  /// "Choose Details" lists), sorted by label, without the ones a built-in
  /// column already shows ([ShellProperty.builtIn]). Empty off Windows.
  Future<List<SystemPropertyColumn>> systemColumns() {
    if (!isSupported) return Future.value(const []);
    return _systemColumns ??= () async {
      try {
        final columns = await Isolate.run(
          _enumerateSystemColumns,
          debugName: 'shell-property-catalog',
        );
        _systemLabels = {for (final c in columns) c.name: c.label};
        return columns;
      } catch (e) {
        debugPrint('WindowsShellProperties.systemColumns: $e');
        _systemColumns = null;
        return const <SystemPropertyColumn>[];
      }
    }();
  }

  /// The Windows label of the system column [name], once [systemColumns]
  /// has loaded.
  String? systemLabel(String name) => _systemLabels[name];

  Future<void> _send() async {
    _flush = null;
    final batch = {
      for (final entry in _queued.entries) entry.key: entry.value.toList(),
    };
    _queued.clear();
    Map<String, String> results = const {};
    try {
      final worker = await (_worker ??= _spawn());
      final reply = ReceivePort();
      worker.send((batch, reply.sendPort));
      results = (await reply.first as Map).cast<String, String>();
      reply.close();
    } catch (e) {
      debugPrint('WindowsShellProperties: $e');
      _worker = null;
    }
    for (final entry in batch.entries) {
      for (final property in entry.value) {
        final key = '$property\u0000${entry.key}';
        final text = results[key] ?? '';
        if (_cache.length >= _maxCacheSize) _cache.remove(_cache.keys.first);
        _cache[key] = text;
        _pending.remove(key)?.complete(text);
      }
    }
  }

  static Future<SendPort> _spawn() async {
    final ready = ReceivePort();
    await Isolate.spawn(
      _shellPropertyWorker,
      ready.sendPort,
      debugName: 'shell-properties',
    );
    final port = await ready.first as SendPort;
    ready.close();
    return port;
  }
}

/// A property Windows can show as a Details column, by canonical name such as
/// `System.Music.Composer`.
@immutable
class SystemPropertyColumn {
  const SystemPropertyColumn(this.name, this.label);

  final String name;

  /// Display name, in the language of Windows.
  final String label;
}

/// A Shell property key (`System.*` canonical name in the comment).
class ShellProperty {
  const ShellProperty(this.fmtid, this.pid);

  final String fmtid;
  final int pid;

  static const _summary = 'F29F85E0-4FF9-1068-AB91-08002B27B3D9';
  static const _music = '56A3372E-CE9C-11D2-9F0E-006097C686F6';
  static const _photo = '14B81DA1-0135-4D31-96D9-6CBFC9671A99';
  static const _image = '6444048F-4C8B-11D1-8B70-080036B11A03';
  static const _media = '64440490-4C8B-11D1-8B70-080036B11A03';
  static const _video = '64440491-4C8B-11D1-8B70-080036B11A03';
  static const _version = '0CEF7D53-FA64-11D1-A203-0000F81FEDEE';

  /// Property names the Details view asks for, each read from the first key
  /// that has a value.
  static const byName = <String, List<ShellProperty>>{
    // System.FileOwner
    'owner': [ShellProperty('9B174B34-40FF-11D2-A27E-00C04FC30871', 4)],
    // System.Author
    'authors': [ShellProperty(_summary, 4)],
    // System.Title
    'title': [ShellProperty(_summary, 2)],
    // System.Comment
    'comments': [ShellProperty(_summary, 6)],
    // System.Document.PageCount
    'pageCount': [ShellProperty(_summary, 14)],
    // System.Rating
    'rating': [ShellProperty('64440492-4C8B-11D1-8B70-080036B11A03', 9)],
    // System.Photo.DateTaken
    'dateTaken': [ShellProperty(_photo, 36867)],
    // System.Photo.CameraModel
    'cameraModel': [ShellProperty(_photo, 272)],
    // System.Image.Dimensions; videos use their frame size (see worker).
    'dimensions': [ShellProperty(_image, 13)],
    // System.Media.Duration
    'duration': [ShellProperty(_media, 3)],
    // System.Video.FrameRate
    'frameRate': [ShellProperty(_video, 6)],
    // System.Audio.EncodingBitrate, then System.Video.TotalBitrate
    'bitRate': [ShellProperty(_media, 4), ShellProperty(_video, 43)],
    // System.Music.Artist
    'artist': [ShellProperty(_music, 2)],
    // System.Music.AlbumTitle
    'album': [ShellProperty(_music, 4)],
    // System.Music.Genre
    'genre': [ShellProperty(_music, 11)],
    // System.Media.Year
    'year': [ShellProperty(_music, 5)],
    // System.Company
    'company': [ShellProperty('D5CDD502-2E9C-101B-9397-08002B2CF9AE', 15)],
    // System.FileDescription
    'fileDescription': [ShellProperty(_version, 3)],
    // System.FileVersion
    'fileVersion': [ShellProperty(_version, 4)],
    // System.Software.ProductName
    'productName': [ShellProperty(_version, 7)],
  };

  /// The [WindowsShellProperties.get] name of the system property column
  /// [canonicalName] (a [SystemPropertyColumn.name]).
  static String system(String canonicalName) => 'sys:$canonicalName';

  /// Canonical names of the properties the built-in Details columns show.
  static const builtIn = {
    'System.ItemNameDisplay',
    'System.FileName',
    'System.ItemPathDisplay',
    'System.ItemFolderPathDisplay',
    'System.ItemTypeText',
    'System.Size',
    'System.DateModified',
    'System.DateCreated',
    'System.DateAccessed',
    'System.FileAttributes',
    'System.FileExtension',
    'System.FileOwner',
    'System.Author',
    'System.Title',
    'System.Comment',
    'System.Document.PageCount',
    'System.Rating',
    'System.Photo.DateTaken',
    'System.Photo.CameraModel',
    'System.Image.Dimensions',
    'System.Media.Duration',
    'System.Video.FrameRate',
    'System.Audio.EncodingBitrate',
    'System.Music.Artist',
    'System.Music.AlbumTitle',
    'System.Music.Genre',
    'System.Media.Year',
    'System.Company',
    'System.FileDescription',
    'System.FileVersion',
    'System.Software.ProductName',
  };

  // System.Video.FrameWidth / FrameHeight
  static const frameWidth = ShellProperty(_video, 3);
  static const frameHeight = ShellProperty(_video, 4);
  static const imageWidth = ShellProperty(_image, 3);
  static const imageHeight = ShellProperty(_image, 4);
}

typedef _FormatNative =
    Int32 Function(
      Pointer<win32.PROPERTYKEY>,
      Pointer<win32.PROPVARIANT>,
      Int32,
      Pointer<Pointer<Utf16>>,
    );
typedef _FormatDart =
    int Function(
      Pointer<win32.PROPERTYKEY>,
      Pointer<win32.PROPVARIANT>,
      int,
      Pointer<Pointer<Utf16>>,
    );

typedef _KeyFromNameNative =
    Int32 Function(Pointer<Utf16>, Pointer<win32.PROPERTYKEY>);
typedef _KeyFromNameDart =
    int Function(Pointer<Utf16>, Pointer<win32.PROPERTYKEY>);
typedef _EnumNative =
    Int32 Function(Int32, Pointer<win32.GUID>, Pointer<Pointer>);
typedef _EnumDart = int Function(int, Pointer<win32.GUID>, Pointer<Pointer>);
typedef _ReleaseNative = Uint32 Function(Pointer);
typedef _GetCountNative = Int32 Function(Pointer, Pointer<Uint32>);
typedef _GetAtNative =
    Int32 Function(Pointer, Uint32, Pointer<win32.GUID>, Pointer<Pointer>);
typedef _GetStringNative = Int32 Function(Pointer, Pointer<Pointer<Utf16>>);

/// The function in vtable slot [slot] of the COM object [object].
Pointer<NativeFunction<T>> _vtable<T extends Function>(
  Pointer object,
  int slot,
) => object.cast<Pointer<Pointer<NativeFunction<T>>>>().value[slot];

/// Lists the property descriptions Windows marks as columns, then the
/// viewable ones, through `PSEnumeratePropertyDescriptions`. Runs on its own
/// isolate; win32 has no `IPropertyDescription`, so this calls its vtable.
List<SystemPropertyColumn> _enumerateSystemColumns() {
  // PDEF_COLUMN, then PDEF_VIEWABLE.
  const filters = [6, 3];
  // IPropertyDescription::GetCanonicalName / GetDisplayName.
  const canonicalNameSlot = 4, displayNameSlot = 6;
  win32.CoInitializeEx(win32.COINIT(win32.COINIT_MULTITHREADED));
  final enumerate = DynamicLibrary.open(
    'propsys.dll',
  ).lookupFunction<_EnumNative, _EnumDart>('PSEnumeratePropertyDescriptions');
  final listIid = win32.IID_IPropertyDescriptionList.toNative();
  final descriptionIid = win32
      .GUID('6F79D558-3E96-4549-A1D1-7D75D2288814')
      .toNative();
  final out = calloc<Pointer>();
  final text = calloc<Pointer<Utf16>>();
  final count = calloc<Uint32>();
  final columns = <String, SystemPropertyColumn>{};

  void release(Pointer object) => _vtable<_ReleaseNative>(
    object,
    2,
  ).asFunction<int Function(Pointer)>()(object);

  String? string(Pointer description, int slot) {
    final get = _vtable<_GetStringNative>(
      description,
      slot,
    ).asFunction<int Function(Pointer, Pointer<Pointer<Utf16>>)>();
    text.value = nullptr;
    if (get(description, text) < 0 || text.value == nullptr) return null;
    final result = text.value.toDartString().trim();
    win32.CoTaskMemFree(text.value);
    return result.isEmpty ? null : result;
  }

  try {
    for (final filter in filters) {
      out.value = nullptr;
      if (enumerate(filter, listIid, out) < 0 || out.value == nullptr) {
        continue;
      }
      final list = out.value;
      try {
        final getCount = _vtable<_GetCountNative>(
          list,
          3,
        ).asFunction<int Function(Pointer, Pointer<Uint32>)>();
        final getAt = _vtable<_GetAtNative>(list, 4)
            .asFunction<
              int Function(Pointer, int, Pointer<win32.GUID>, Pointer<Pointer>)
            >();
        if (getCount(list, count) < 0) continue;
        for (var i = 0; i < count.value; i++) {
          out.value = nullptr;
          if (getAt(list, i, descriptionIid, out) < 0 || out.value == nullptr) {
            continue;
          }
          final description = out.value;
          try {
            final name = string(description, canonicalNameSlot);
            if (name == null ||
                columns.containsKey(name) ||
                ShellProperty.builtIn.contains(name)) {
              continue;
            }
            // Properties without a label are not meant to be shown.
            final label = string(description, displayNameSlot);
            if (label != null) {
              columns[name] = SystemPropertyColumn(name, label);
            }
          } finally {
            release(description);
          }
        }
      } finally {
        release(list);
      }
    }
  } finally {
    calloc.free(out);
    calloc.free(text);
    calloc.free(count);
    win32.free(listIid);
    win32.free(descriptionIid);
    win32.CoUninitialize();
  }
  return columns.values.toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
}

void _shellPropertyWorker(SendPort ready) {
  win32.CoInitializeEx(win32.COINIT(win32.COINIT_MULTITHREADED));
  final propsys = DynamicLibrary.open('propsys.dll');
  final format = propsys.lookupFunction<_FormatNative, _FormatDart>(
    'PSFormatForDisplayAlloc',
  );
  final keyFromName = propsys
      .lookupFunction<_KeyFromNameNative, _KeyFromNameDart>(
        'PSGetPropertyKeyFromName',
      );
  final key = calloc<win32.PROPERTYKEY>();
  // Keys of system property columns by canonical name, null when Windows
  // does not know the name. Bounded by the catalog, so never freed.
  final systemKeys = <String, Pointer<win32.PROPERTYKEY>?>{};

  void setKey(ShellProperty property) {
    key.ref.fmtid.setGUID(property.fmtid);
    key.ref.pid = property.pid;
  }

  Pointer<win32.PROPERTYKEY>? systemKey(String name) =>
      systemKeys.putIfAbsent(name, () {
        final native = name.toNativeUtf16();
        final resolved = calloc<win32.PROPERTYKEY>();
        try {
          if (keyFromName(native, resolved) >= 0) return resolved;
          calloc.free(resolved);
          return null;
        } finally {
          calloc.free(native);
        }
      });

  String displayKey(win32.IShellItem2 item, Pointer<win32.PROPERTYKEY> key) {
    final Pointer<win32.PROPVARIANT> value;
    try {
      value = item.getProperty(key);
    } on win32.WindowsException {
      return '';
    }
    final text = calloc<Pointer<Utf16>>();
    try {
      if (format(key, value, 0, text) < 0 || text.value == nullptr) return '';
      // Explorer wraps some values (dimensions, dates) in bidi marks.
      final result = text.value
          .toDartString()
          .replaceAll(RegExp('[\u200e\u200f\u202a-\u202e]'), '')
          .trim();
      win32.CoTaskMemFree(text.value);
      return result;
    } finally {
      calloc.free(text);
      win32.PropVariantClear(value);
      win32.free(value);
    }
  }

  String display(win32.IShellItem2 item, ShellProperty property) {
    setKey(property);
    return displayKey(item, key);
  }

  int? uint32(win32.IShellItem2 item, ShellProperty property) {
    setKey(property);
    try {
      final value = item.getUInt32(key);
      return value > 0 ? value : null;
    } on win32.WindowsException {
      return null;
    }
  }

  final port = ReceivePort();
  String sortKey(win32.IShellItem2 item, String name) {
    if (name == 'dimensions') {
      final width =
          uint32(item, ShellProperty.frameWidth) ??
          uint32(item, ShellProperty.imageWidth);
      final height =
          uint32(item, ShellProperty.frameHeight) ??
          uint32(item, ShellProperty.imageHeight);
      return width == null || height == null ? '' : '$width,$height';
    }
    for (final property
        in ShellProperty.byName[name] ?? const <ShellProperty>[]) {
      setKey(property);
      try {
        if (name == 'duration') return '${item.getUInt64(key)}';
        if (name == 'pageCount') return '${item.getInt32(key)}';
        if (name == 'dateTaken') {
          final value = item.getFileTime(key);
          try {
            return '${(value.ref.dwHighDateTime << 32) | value.ref.dwLowDateTime}';
          } finally {
            win32.free(value);
          }
        }
        if (const {'rating', 'frameRate', 'bitRate', 'year'}.contains(name)) {
          return '${item.getUInt32(key)}';
        }
        final text = display(item, property);
        if (text.isNotEmpty) return text;
      } on win32.WindowsException {
        /* Try the next canonical property. */
      }
    }
    return '';
  }

  ready.send(port.sendPort);
  port.listen((message) {
    final (batch, reply) = message as (Map<String, List<String>>, SendPort);
    final results = <String, String>{};
    for (final entry in batch.entries) {
      final pathPtr = entry.key.toNativeUtf16();
      win32.IShellItem2? item;
      try {
        final attributes = win32.GetFileAttributes(win32.PCWSTR(pathPtr)).value;
        final cloudOnly =
            attributes != 0xFFFFFFFF &&
            attributes & (0x1000 | 0x40000 | 0x400000) != 0;
        // Sorting a folder must not hydrate cloud-only file contents.
        if (cloudOnly &&
            entry.value.every((name) => name.startsWith('sort:'))) {
          continue;
        }
        item = win32.SHCreateItemFromParsingName<win32.IShellItem2>(
          win32.PCWSTR(pathPtr),
          null,
        );
        for (final name in entry.value) {
          if (name.startsWith('sys:')) {
            final key = systemKey(name.substring(4));
            results['$name\u0000${entry.key}'] = key == null
                ? ''
                : displayKey(item, key);
            continue;
          }
          if (name.startsWith('sort:')) {
            if (cloudOnly) continue;
            results['$name\u0000${entry.key}'] = sortKey(
              item,
              name.substring(5),
            );
            continue;
          }
          var text = '';
          for (final property in ShellProperty.byName[name] ?? const []) {
            text = display(item, property);
            if (text.isNotEmpty) break;
          }
          if (text.isEmpty && name == 'dimensions') {
            final width = uint32(item, ShellProperty.frameWidth);
            final height = uint32(item, ShellProperty.frameHeight);
            if (width != null && height != null) text = '$width x $height';
          }
          results['$name\u0000${entry.key}'] = text;
        }
      } on win32.WindowsException {
        // No Shell item (deleted, offline share): every value stays empty.
      } finally {
        item?.release();
        calloc.free(pathPtr);
      }
    }
    reply.send(results);
  });
}
