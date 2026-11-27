import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// One reading of the machine's load. Any value is null when the platform
/// does not report it.
class SystemResourceSample {
  /// Busy fraction of all CPU cores, 0..1.
  final double? cpu;
  final int? ramTotal, ramAvailable;

  /// Busiest GPU engine type (3D, compute, copy...), 0..1.
  final double? gpu;
  final int? vramTotal, vramUsed;

  /// Busy fraction of the busiest physical disk, 0..1, and its name.
  final double? diskBusy;
  final String? diskName;

  /// Private resident bytes of selected processes (not total machine RAM).
  final int? processRamUsed;

  /// Process read/write throughput, including non-disk I/O.
  final double? ioBytesPerSecond;

  const SystemResourceSample({
    this.cpu,
    this.ramTotal,
    this.ramAvailable,
    this.gpu,
    this.vramTotal,
    this.vramUsed,
    this.diskBusy,
    this.diskName,
    this.processRamUsed,
    this.ioBytesPerSecond,
  });

  int? get ramUsed => switch ((ramTotal, ramAvailable)) {
    (final total?, final available?) => math.max(0, total - available),
    _ => null,
  };

  int? get vramFree => switch ((vramTotal, vramUsed)) {
    (final total?, final used?) => math.max(0, total - used),
    _ => null,
  };
}

typedef SystemResourceSampler = Future<SystemResourceSample?> Function();

/// Samples CPU, memory, GPU and disk load while someone listens.
///
/// Sampling runs in a short-lived isolate (it waits a second between two
/// counter readings), so the UI thread never blocks on it.
class SystemResourceMonitor extends ChangeNotifier {
  static final instance = SystemResourceMonitor();

  final SystemResourceSampler? sampler;
  final Duration interval;

  SystemResourceMonitor({SystemResourceSampler? sampler, Duration? interval})
    : sampler = sampler ?? defaultSampler(),
      interval = interval ?? const Duration(seconds: 3);

  static SystemResourceSampler? defaultSampler() {
    if (Platform.isWindows) {
      return () => Isolate.run(_windowsSample);
    }
    if (Platform.isLinux) {
      return () => Isolate.run(_linuxSample);
    }
    return null;
  }

  /// Separate monitor for explicit process IDs. Never substitutes global load
  /// for measurements the platform cannot attribute to these processes.
  static SystemResourceSampler? processSampler(
    Future<List<int>> Function() ids,
  ) {
    if (!Platform.isWindows && !Platform.isLinux) return null;
    return () async {
      final targets = (await ids()).toSet();
      return _sampleProcessIds(targets);
    };
  }

  bool get supported => sampler != null;
  SystemResourceSample? latest;

  int _users = 0;
  Timer? _timer;
  bool _sampling = false;
  bool _disposed = false;

  /// Starts sampling for one more user. Pair with [release].
  void acquire() {
    if (!supported || _disposed) return;
    _users++;
    if (_users == 1) {
      _timer = Timer.periodic(interval, (_) => unawaited(sampleNow()));
      unawaited(sampleNow());
    }
  }

  void release() {
    if (_users == 0) return;
    _users--;
    if (_users == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> sampleNow() async {
    final sample = sampler;
    if (sample == null || _sampling || _disposed) return;
    _sampling = true;
    try {
      final value = await sample();
      if (_disposed || value == null) return;
      latest = value;
      notifyListeners();
    } catch (e) {
      debugPrint('System resources: $e');
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

Future<SystemResourceSample> _sampleProcessIds(Set<int> targets) => Isolate.run(
  () => Platform.isWindows
      ? _windowsProcessSample(targets)
      : _linuxProcessSample(targets),
);

// ---------------------------------------------------------------- Windows

const _pdhMoreData = 0x800007D2;
const _pdhFmtDouble = 0x00000200;
const _pdhFmtNoCap100 = 0x00008000;
const _hkeyLocalMachine = 0x80000002;
const _rrfRtAny = 0x0000ffff;
const _displayClass =
    r'SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}';

typedef _PdhOpenC = Uint32 Function(Pointer<Utf16>, IntPtr, Pointer<IntPtr>);
typedef _PdhOpen = int Function(Pointer<Utf16>, int, Pointer<IntPtr>);
typedef _PdhAddC =
    Uint32 Function(IntPtr, Pointer<Utf16>, IntPtr, Pointer<IntPtr>);
typedef _PdhAdd = int Function(int, Pointer<Utf16>, int, Pointer<IntPtr>);
typedef _PdhHandleC = Uint32 Function(IntPtr);
typedef _PdhHandle = int Function(int);
typedef _PdhArrayC =
    Uint32 Function(
      IntPtr,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint8>,
    );
typedef _PdhArray =
    int Function(int, int, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>);
typedef _SystemTimesC =
    Int32 Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _SystemTimes =
    int Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _MemoryStatusC = Int32 Function(Pointer<Uint8>);
typedef _MemoryStatus = int Function(Pointer<Uint8>);
typedef _OpenProcessC = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcess = int Function(int, int, int);
typedef _ProcessTimesC =
    Int32 Function(
      IntPtr,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _ProcessTimes =
    int Function(
      int,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _ProcessIoC = Int32 Function(IntPtr, Pointer<Uint64>);
typedef _ProcessIo = int Function(int, Pointer<Uint64>);
typedef _ProcessMemoryC = Int32 Function(IntPtr, Pointer<Uint8>, Uint32);
typedef _ProcessMemory = int Function(int, Pointer<Uint8>, int);
typedef _CloseHandleC = Int32 Function(IntPtr);
typedef _CloseHandle = int Function(int);
typedef _RegGetValueC =
    Int32 Function(
      IntPtr,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint8>,
      Pointer<Uint32>,
    );
typedef _RegGetValue =
    int Function(
      int,
      Pointer<Utf16>,
      Pointer<Utf16>,
      int,
      Pointer<Uint32>,
      Pointer<Uint8>,
      Pointer<Uint32>,
    );

SystemResourceSample _windowsSample() {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final systemTimes = kernel32.lookupFunction<_SystemTimesC, _SystemTimes>(
    'GetSystemTimes',
  );
  final memoryStatus = kernel32.lookupFunction<_MemoryStatusC, _MemoryStatus>(
    'GlobalMemoryStatusEx',
  );

  (int, int)? times() {
    final idle = calloc<Uint64>(), kernel = calloc<Uint64>();
    final user = calloc<Uint64>();
    try {
      if (systemTimes(idle, kernel, user) == 0) return null;
      // Kernel time includes idle time.
      return (idle.value, kernel.value + user.value);
    } finally {
      calloc
        ..free(idle)
        ..free(kernel)
        ..free(user);
    }
  }

  final pdh = _Pdh.open();
  final before = times();
  pdh?.collect();
  sleep(const Duration(seconds: 1));
  pdh?.collect();
  final after = times();

  double? cpu;
  if (before != null && after != null && after.$2 > before.$2) {
    final idle = after.$1 - before.$1;
    final total = after.$2 - before.$2;
    cpu = (1 - idle / total).clamp(0.0, 1.0);
  }

  int? ramTotal, ramAvailable;
  final status = calloc<Uint8>(64);
  try {
    status.cast<Uint32>().value = 64;
    if (memoryStatus(status) != 0) {
      ramTotal = Pointer<Uint64>.fromAddress(status.address + 8).value;
      ramAvailable = Pointer<Uint64>.fromAddress(status.address + 16).value;
    }
  } finally {
    calloc.free(status);
  }

  double? gpu, diskBusy;
  int? vramUsed;
  String? diskName;
  if (pdh != null) {
    try {
      // Sum the engines of one type across processes; the busiest type is
      // what the GPU is limited by.
      final engines = <String, double>{};
      for (final MapEntry(:key, :value) in pdh.values(pdh.gpuEngine).entries) {
        final type = key.split('engtype_').last;
        engines[type] = (engines[type] ?? 0) + value;
      }
      if (engines.isNotEmpty) {
        gpu = (engines.values.reduce(math.max) / 100).clamp(0.0, 1.0);
      }
      final memory = pdh.values(pdh.gpuMemory).values;
      if (memory.isNotEmpty) vramUsed = memory.reduce(math.max).round();
      for (final MapEntry(:key, :value) in pdh.values(pdh.diskIdle).entries) {
        if (key == '_Total') continue;
        final busy = (1 - value / 100).clamp(0.0, 1.0);
        if (diskBusy == null || busy > diskBusy) {
          diskBusy = busy;
          diskName = key;
        }
      }
    } finally {
      pdh.close();
    }
  }

  return SystemResourceSample(
    cpu: cpu,
    ramTotal: ramTotal,
    ramAvailable: ramAvailable,
    gpu: gpu,
    vramTotal: _windowsVramTotal(),
    vramUsed: vramUsed,
    diskBusy: diskBusy,
    diskName: diskName,
  );
}

/// Attribute counters to the registered PIDs, not process names or all GPUs.
SystemResourceSample _windowsProcessSample(Set<int> targets) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final memoryStatus = kernel32.lookupFunction<_MemoryStatusC, _MemoryStatus>(
    'GlobalMemoryStatusEx',
  );
  int? ramTotal;
  final status = calloc<Uint8>(64);
  try {
    status.cast<Uint32>().value = 64;
    if (memoryStatus(status) != 0) {
      ramTotal = Pointer<Uint64>.fromAddress(status.address + 8).value;
    }
  } finally {
    calloc.free(status);
  }
  final vramTotal = _windowsVramTotal();
  if (targets.isEmpty) {
    return SystemResourceSample(
      cpu: 0,
      ramTotal: ramTotal,
      processRamUsed: 0,
      gpu: 0,
      vramTotal: vramTotal,
      vramUsed: 0,
      ioBytesPerSecond: 0,
    );
  }
  final openProcess = kernel32.lookupFunction<_OpenProcessC, _OpenProcess>(
    'OpenProcess',
  );
  final closeHandle = kernel32.lookupFunction<_CloseHandleC, _CloseHandle>(
    'CloseHandle',
  );
  final getTimes = kernel32.lookupFunction<_ProcessTimesC, _ProcessTimes>(
    'GetProcessTimes',
  );
  final getIo = kernel32.lookupFunction<_ProcessIoC, _ProcessIo>(
    'GetProcessIoCounters',
  );
  final getMemory = kernel32.lookupFunction<_ProcessMemoryC, _ProcessMemory>(
    'K32GetProcessMemoryInfo',
  );
  final handles = <int, int>{};
  final times = calloc<Uint64>(4), ioCounters = calloc<Uint64>(6);
  // PROCESS_MEMORY_COUNTERS_EX2: PrivateWorkingSetSize, not committed bytes.
  final memorySize = 8 + 10 * sizeOf<IntPtr>() + 8;
  final memory = calloc<Uint8>(memorySize);
  (int?, int?) read(int handle) {
    final cpu = getTimes(handle, times, times + 1, times + 2, times + 3) != 0
        ? times[2] + times[3]
        : null;
    final io = getIo(handle, ioCounters) != 0
        ? ioCounters[3] + ioCounters[4]
        : null;
    return (cpu, io);
  }

  final pdh = _Pdh.open(processes: true);
  try {
    for (final id in targets) {
      // Retain the process handle throughout sampling; PID reuse cannot
      // change the underlying process midway through a measurement.
      final handle = openProcess(0x1010, 0, id);
      if (handle != 0) handles[id] = handle;
    }
    final before = {for (final e in handles.entries) e.key: read(e.value)};
    final clock = Stopwatch()..start();
    pdh?.collect();
    sleep(const Duration(seconds: 1));
    int ticks = 0, bytes = 0, ram = 0;
    var cpuKnown = false, ioKnown = false, ramKnown = false;
    for (final e in handles.entries) {
      final previous = before[e.key]!, current = read(e.value);
      if (previous.$1 != null && current.$1 != null) {
        cpuKnown = true;
        ticks += math.max(0, current.$1! - previous.$1!);
      }
      if (previous.$2 != null && current.$2 != null) {
        ioKnown = true;
        bytes += math.max(0, current.$2! - previous.$2!);
      }
      memory.cast<Uint32>().value = memorySize;
      if (getMemory(e.value, memory, memorySize) != 0) {
        ramKnown = true;
        ram += Pointer<UintPtr>.fromAddress(
          memory.address + 8 + 9 * sizeOf<IntPtr>(),
        ).value;
      }
    }
    final seconds = clock.elapsedMicroseconds / 1000000;
    pdh?.collect();
    final gpuCounters = pdh?.values(pdh.gpuEngine) ?? const <String, double>{};
    final memoryCounters =
        pdh?.values(pdh.gpuMemory) ?? const <String, double>{};
    final gpu = aggregateProcessGpu(
      handles.keys.toSet(),
      gpuCounters,
      memoryCounters,
    );
    return SystemResourceSample(
      cpu: cpuKnown
          ? (ticks / (seconds * 10000000 * Platform.numberOfProcessors)).clamp(
              0.0,
              1.0,
            )
          : null,
      ramTotal: ramTotal,
      processRamUsed: ramKnown ? ram : null,
      gpu: gpuCounters.isNotEmpty ? gpu.$1 : null,
      vramTotal: vramTotal,
      vramUsed: memoryCounters.isNotEmpty ? gpu.$2 : null,
      ioBytesPerSecond: ioKnown ? bytes / seconds : null,
    );
  } finally {
    pdh?.close();
    for (final handle in handles.values) {
      closeHandle(handle);
    }
    calloc
      ..free(times)
      ..free(ioCounters)
      ..free(memory);
  }
}

/// GPU Engine instance names are `pid_<pid>_luid_..._eng_<id>_engtype_...`
/// Sum selected processes on the same physical engine, then use the busiest.
/// Dedicated usage is per process/adapter, so each counter is counted once.
@visibleForTesting
(double, int) aggregateProcessGpu(
  Set<int> targets,
  Map<String, double> engines,
  Map<String, double> memory,
) {
  final prefix = RegExp(r'^pid_(\d+)_', caseSensitive: false);
  bool owns(String name) =>
      targets.contains(int.tryParse(prefix.firstMatch(name)?.group(1) ?? ''));
  final loads = <String, double>{};
  for (final entry in engines.entries) {
    if (!owns(entry.key)) continue;
    final engine = entry.key.replaceFirst(prefix, '').toLowerCase();
    loads[engine] = (loads[engine] ?? 0) + math.max(0, entry.value);
  }
  final utilization = loads.isEmpty
      ? 0.0
      : (loads.values.reduce(math.max) / 100).clamp(0.0, 1.0);
  final bytes = memory.entries
      .where((e) => owns(e.key))
      .fold<double>(0, (sum, e) => sum + math.max(0, e.value));
  return (utilization, bytes.round());
}

/// Dedicated memory of the largest display adapter, from its driver key.
int? _windowsVramTotal() {
  final advapi = DynamicLibrary.open('advapi32.dll');
  final get = advapi.lookupFunction<_RegGetValueC, _RegGetValue>(
    'RegGetValueW',
  );
  int? best;
  final data = calloc<Uint8>(8);
  final size = calloc<Uint32>();
  final type = calloc<Uint32>();
  try {
    for (var i = 0; i < 10; i++) {
      final key = '$_displayClass\\${i.toString().padLeft(4, '0')}'
          .toNativeUtf16();
      try {
        for (final name in [
          'HardwareInformation.qwMemorySize',
          'HardwareInformation.MemorySize',
        ]) {
          final value = name.toNativeUtf16();
          try {
            size.value = 8;
            for (var b = 0; b < 8; b++) {
              data[b] = 0;
            }
            if (get(
                  _hkeyLocalMachine,
                  key,
                  value,
                  _rrfRtAny,
                  type,
                  data,
                  size,
                ) !=
                0) {
              continue;
            }
            final bytes = size.value >= 8
                ? data.cast<Uint64>().value
                : data.cast<Uint32>().value;
            if (bytes > 0 && (best == null || bytes > best)) best = bytes;
            break;
          } finally {
            calloc.free(value);
          }
        }
      } finally {
        calloc.free(key);
      }
    }
  } finally {
    calloc
      ..free(data)
      ..free(size)
      ..free(type);
  }
  return best;
}

/// Performance counters, queried by their English names so localized
/// Windows installations work too.
class _Pdh {
  final _PdhHandle _collect, _close;
  final _PdhArray _array;
  final int query, gpuEngine, gpuMemory, diskIdle;

  _Pdh._(
    this._collect,
    this._close,
    this._array,
    this.query,
    this.gpuEngine,
    this.gpuMemory,
    this.diskIdle,
  );

  static _Pdh? open({bool processes = false}) {
    try {
      final lib = DynamicLibrary.open('pdh.dll');
      final openQuery = lib.lookupFunction<_PdhOpenC, _PdhOpen>(
        'PdhOpenQueryW',
      );
      final add = lib.lookupFunction<_PdhAddC, _PdhAdd>(
        'PdhAddEnglishCounterW',
      );
      final handle = calloc<IntPtr>();
      try {
        if (openQuery(nullptr, 0, handle) != 0) return null;
        final query = handle.value;
        int counter(String path) {
          final native = path.toNativeUtf16();
          try {
            return add(query, native, 0, handle) == 0 ? handle.value : 0;
          } finally {
            calloc.free(native);
          }
        }

        return _Pdh._(
          lib.lookupFunction<_PdhHandleC, _PdhHandle>('PdhCollectQueryData'),
          lib.lookupFunction<_PdhHandleC, _PdhHandle>('PdhCloseQuery'),
          lib.lookupFunction<_PdhArrayC, _PdhArray>(
            'PdhGetFormattedCounterArrayW',
          ),
          query,
          counter(r'\GPU Engine(*)\Utilization Percentage'),
          counter(
            processes
                ? r'\GPU Process Memory(*)\Dedicated Usage'
                : r'\GPU Adapter Memory(*)\Dedicated Usage',
          ),
          processes ? 0 : counter(r'\PhysicalDisk(*)\% Idle Time'),
        );
      } finally {
        calloc.free(handle);
      }
    } catch (_) {
      return null;
    }
  }

  void collect() => _collect(query);
  void close() => _close(query);

  /// Values of a wildcard counter by instance name.
  Map<String, double> values(int counter) {
    if (counter == 0) return const {};
    final size = calloc<Uint32>(), count = calloc<Uint32>();
    try {
      const format = _pdhFmtDouble | _pdhFmtNoCap100;
      if (_array(counter, format, size, count, nullptr) != _pdhMoreData) {
        return const {};
      }
      final buffer = calloc<Uint8>(size.value);
      try {
        if (_array(counter, format, size, count, buffer) != 0) return const {};
        // PDH_FMT_COUNTERVALUE_ITEM_W on x64: name pointer, CStatus, padding,
        // then the double.
        final result = <String, double>{};
        for (var i = 0; i < count.value; i++) {
          final item = buffer.address + i * 24;
          final status = Pointer<Uint32>.fromAddress(item + 8).value;
          if (status > 1) continue; // Neither valid nor new data.
          final name = Pointer<Utf16>.fromAddress(
            Pointer<IntPtr>.fromAddress(item).value,
          ).toDartString();
          final value = Pointer<Double>.fromAddress(item + 16).value;
          result[name] = (result[name] ?? 0) + value;
        }
        return result;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc
        ..free(size)
        ..free(count);
    }
  }
}

// ------------------------------------------------------------------ Linux

SystemResourceSample _linuxSample() {
  (int, int)? times() {
    try {
      final line = File('/proc/stat').readAsLinesSync().first;
      final values = line
          .split(RegExp(r'\s+'))
          .skip(1)
          .where((v) => v.isNotEmpty)
          .map(int.parse)
          .toList();
      final idle = values[3] + (values.length > 4 ? values[4] : 0);
      return (idle, values.fold<int>(0, (a, b) => a + b));
    } catch (_) {
      return null;
    }
  }

  final before = times();
  sleep(const Duration(seconds: 1));
  final after = times();
  double? cpu;
  if (before != null && after != null && after.$2 > before.$2) {
    cpu = (1 - (after.$1 - before.$1) / (after.$2 - before.$2)).clamp(0.0, 1.0);
  }
  int? total, available;
  try {
    for (final line in File('/proc/meminfo').readAsLinesSync()) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final kb = int.tryParse(parts[1]);
      if (kb == null) continue;
      if (parts[0] == 'MemTotal:') total = kb * 1024;
      if (parts[0] == 'MemAvailable:') available = kb * 1024;
    }
  } catch (_) {}
  return SystemResourceSample(
    cpu: cpu,
    ramTotal: total,
    ramAvailable: available,
  );
}

SystemResourceSample _linuxProcessSample(Set<int> targets) {
  int? totalRam;
  try {
    final line = File(
      '/proc/meminfo',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('MemTotal:'));
    totalRam = int.parse(line.split(RegExp(r'\s+'))[1]) * 1024;
  } catch (_) {}
  if (targets.isEmpty) {
    return SystemResourceSample(
      cpu: 0,
      ramTotal: totalRam,
      processRamUsed: 0,
      ioBytesPerSecond: 0,
    );
  }

  int? systemTicks() {
    try {
      final values = File('/proc/stat')
          .readAsLinesSync()
          .first
          .split(RegExp(r'\s+'))
          .skip(1)
          .map(int.parse)
          .toList();
      return values.take(8).fold<int>(0, (a, b) => a + b);
    } catch (_) {
      return null;
    }
  }

  // Start time protects against a PID being reused between readings.
  (int, int, int?)? process(int id) {
    try {
      final stat = File('/proc/$id/stat').readAsStringSync();
      final fields = stat
          .substring(stat.lastIndexOf(')') + 2)
          .trim()
          .split(RegExp(r'\s+'));
      int? io;
      try {
        final lines = File('/proc/$id/io').readAsLinesSync();
        io = lines
            .where((l) => l.startsWith('rchar:') || l.startsWith('wchar:'))
            .fold<int>(
              0,
              (sum, l) => sum + int.parse(l.split(':').last.trim()),
            );
      } catch (_) {}
      return (
        int.parse(fields[19]),
        int.parse(fields[11]) + int.parse(fields[12]),
        io,
      );
    } catch (_) {
      return null;
    }
  }

  final before = {for (final id in targets) id: process(id)};
  final ticksBefore = systemTicks();
  final clock = Stopwatch()..start();
  sleep(const Duration(seconds: 1));
  final ticksAfter = systemTicks();
  int usedTicks = 0, bytes = 0, ram = 0;
  var cpuKnown = false, ioKnown = false, ramKnown = false;
  for (final id in targets) {
    final previous = before[id], current = process(id);
    if (previous == null || current == null || previous.$1 != current.$1) {
      continue;
    }
    cpuKnown = true;
    usedTicks += math.max(0, current.$2 - previous.$2);
    if (previous.$3 != null && current.$3 != null) {
      ioKnown = true;
      bytes += math.max(0, current.$3! - previous.$3!);
    }
    try {
      final lines = File('/proc/$id/smaps_rollup').readAsLinesSync();
      final private = lines.where(
        (l) => l.startsWith('Private_Clean:') || l.startsWith('Private_Dirty:'),
      );
      ram += private.fold(
        0,
        (sum, l) => sum + int.parse(l.split(RegExp(r'\s+'))[1]) * 1024,
      );
      ramKnown = true;
    } catch (_) {}
  }
  return SystemResourceSample(
    cpu:
        cpuKnown &&
            ticksBefore != null &&
            ticksAfter != null &&
            ticksAfter > ticksBefore
        ? (usedTicks / (ticksAfter - ticksBefore)).clamp(0.0, 1.0)
        : null,
    ramTotal: totalRam,
    processRamUsed: ramKnown ? ram : null,
    ioBytesPerSecond: ioKnown
        ? bytes / (clock.elapsedMicroseconds / 1000000)
        : null,
  );
}
