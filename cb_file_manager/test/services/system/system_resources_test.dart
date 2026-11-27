import 'dart:io';

import 'package:cb_file_manager/services/system/system_resources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queue sample counts only selected processes, and idle is zero', () async {
    final idle = await SystemResourceMonitor.processSampler(() async => [])!();
    expect(idle!.cpu, 0);
    expect(idle.processRamUsed, 0);
    expect(idle.ioBytesPerSecond, 0);
    final active = await SystemResourceMonitor.processSampler(
      () async => [pid],
    )!();
    expect(active, isNotNull);
    expect(active!.cpu, inInclusiveRange(0, 1));
    expect(active.processRamUsed, greaterThan(0));
    expect(active.processRamUsed, lessThan(active.ramTotal!));
    expect(active.ramAvailable, isNull, reason: 'not a machine-wide sample');
    expect(active.ioBytesPerSecond, greaterThanOrEqualTo(0));
    print(
      'queue CPU ${active.cpu} RAM ${active.processRamUsed} GPU ${active.gpu} VRAM ${active.vramUsed} I/O ${active.ioBytesPerSecond}',
    );
  }, skip: !(Platform.isWindows || Platform.isLinux));

  test(
    'GPU aggregation excludes other processes and combines shared engines',
    () {
      final (gpu, vram) = aggregateProcessGpu(
        {42, 43},
        {
          'pid_42_luid_a_phys_0_eng_1_engtype_Compute': 25,
          'pid_43_luid_a_phys_0_eng_1_engtype_Compute': 35,
          'pid_42_luid_a_phys_0_eng_2_engtype_Copy': 10,
          'pid_99_luid_a_phys_0_eng_1_engtype_Compute': 40,
          'pid_420_luid_a_phys_0_eng_1_engtype_Compute': 100,
          'pid_43_luid_b_phys_0_eng_1_engtype_Compute': 50,
        },
        {
          'pid_42_luid_a_phys_0': 200,
          'pid_43_luid_a_phys_0': 300,
          'pid_99_luid_a_phys_0': 900,
        },
      );
      expect(gpu, .60);
      expect(vram, 500);
    },
  );

  test('reads the load of this machine', () async {
    final sample = await SystemResourceMonitor.defaultSampler()!();
    expect(sample, isNotNull);
    expect(sample!.cpu, inInclusiveRange(0, 1));
    expect(sample.ramTotal, greaterThan(0));
    expect(sample.ramAvailable, lessThanOrEqualTo(sample.ramTotal!));
    // ignore: avoid_print
    print(
      'cpu ${sample.cpu} ram ${sample.ramUsed}/${sample.ramTotal} '
      'gpu ${sample.gpu} vram ${sample.vramUsed}/${sample.vramTotal} '
      'disk ${sample.diskBusy} ${sample.diskName}',
    );
  }, skip: !(Platform.isWindows || Platform.isLinux));

  test('a monitor samples only while someone listens', () async {
    var calls = 0;
    final monitor = SystemResourceMonitor(
      sampler: () async {
        calls++;
        return const SystemResourceSample(cpu: .5);
      },
      interval: const Duration(milliseconds: 20),
    );
    addTearDown(monitor.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, 0);
    monitor.acquire();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(monitor.latest?.cpu, .5);
    monitor.release();
    final stopped = calls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, stopped);
  });

  test('free memory is derived from total and use', () {
    const sample = SystemResourceSample(
      ramTotal: 32,
      ramAvailable: 12,
      vramTotal: 16,
      vramUsed: 14,
    );
    expect(sample.ramUsed, 20);
    expect(sample.vramFree, 2);
    expect(const SystemResourceSample().vramFree, isNull);
  });
}
