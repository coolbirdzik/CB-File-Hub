import 'package:cb_file_manager/bloc/cleaner_app_leftovers/cleaner_app_leftovers.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_finder.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

const _mib = 1024 * 1024;

void main() {
  final now = DateTime(2026, 10, 1);

  AppLeftoverReport report() {
    return AppLeftoverReport(
      drivePath: r'C:\',
      generatedAt: now,
      candidates: const <AppLeftoverCandidate>[
        AppLeftoverCandidate(
          path: r'C:\Data\OldGame',
          displayName: 'OldGame',
          location: AppLeftoverLocation.localAppData,
          reason: AppLeftoverReason.noInstalledApp,
          sizeBytes: 0,
        ),
        AppLeftoverCandidate(
          path: r'C:\Data\Vendor\Product',
          displayName: r'Vendor\Product',
          location: AppLeftoverLocation.localAppData,
          reason: AppLeftoverReason.olderVersion,
          sizeBytes: 0,
          relatedAppName: 'Product 2',
        ),
        AppLeftoverCandidate(
          path: r'C:\Data\Busy',
          displayName: 'Busy',
          location: AppLeftoverLocation.roamingAppData,
          reason: AppLeftoverReason.noInstalledApp,
          sizeBytes: 0,
        ),
        AppLeftoverCandidate(
          path: r'C:\Data\Tiny',
          displayName: 'Tiny',
          location: AppLeftoverLocation.roamingAppData,
          reason: AppLeftoverReason.noInstalledApp,
          sizeBytes: 0,
        ),
      ],
    );
  }

  AppLeftoverMeasurement measured(int mib, {int daysAgo = 400}) {
    return AppLeftoverMeasurement(
      sizeBytes: mib * _mib,
      fileCount: 3,
      lastModified: now.subtract(Duration(days: daysAgo)),
    );
  }

  Map<String, AppLeftoverMeasurement> allMeasured() =>
      <String, AppLeftoverMeasurement>{
        r'C:\Data\OldGame': measured(300),
        r'C:\Data\Vendor\Product': measured(100, daysAgo: 120),
        r'C:\Data\Busy': measured(50, daysAgo: 3),
        r'C:\Data\Tiny': const AppLeftoverMeasurement(
          sizeBytes: 10,
          fileCount: 1,
        ),
      };

  CleanerAppLeftoversCubit scanningCubit() {
    return CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(report(), scanning: true);
  }

  test('lists folders as they are measured, largest first', () {
    final cubit = scanningCubit();
    addTearDown(cubit.close);

    expect(cubit.state.visibleCandidates, isEmpty);
    expect(cubit.state.totalCount, 4);

    cubit.addMeasurement(r'C:\Data\Vendor\Product', measured(100));
    expect(cubit.state.measuredCount, 1);
    expect(cubit.state.visibleCandidates.single.sizeBytes, 100 * _mib);

    cubit.addMeasurement(r'C:\Data\OldGame', measured(300));
    expect(cubit.state.visibleCandidates.map((c) => c.displayName), <String>[
      'OldGame',
      r'Vendor\Product',
    ]);

    // Folders under the size floor are measured but never listed.
    cubit.addMeasurement(r'C:\Data\Tiny', allMeasured()[r'C:\Data\Tiny']!);
    expect(cubit.state.measuredCount, 3);
    expect(cubit.state.visibleCandidates, hasLength(2));

    cubit.finishScan();
    expect(cubit.state.isScanning, isFalse);
  });

  test('marks folders the walk could not finish as partial', () {
    final cubit = scanningCubit();
    addTearDown(cubit.close);

    cubit.addMeasurement(
      r'C:\Data\OldGame',
      const AppLeftoverMeasurement(
        sizeBytes: 5 * _mib,
        fileCount: 1,
        isComplete: false,
      ),
    );
    expect(cubit.state.visibleCandidates.single.isPartial, isTrue);
  });

  test('hides recently changed folders behind the inactivity filter', () {
    final cubit = scanningCubit()..addMeasurements(allMeasured());
    addTearDown(cubit.close);

    expect(cubit.state.inactiveDays, defaultCleanerLeftoverInactiveDays);
    expect(cubit.state.visibleCandidates.map((c) => c.displayName), <String>[
      'OldGame',
      r'Vendor\Product',
    ]);
    expect(cubit.state.hiddenByActivityCount, 1);

    cubit.setInactiveDays(180);
    expect(cubit.state.visibleCandidates.map((c) => c.displayName), <String>[
      'OldGame',
    ]);

    cubit.setInactiveDays(0);
    expect(cubit.state.visibleCandidates, hasLength(3));
    expect(cubit.state.hiddenByActivityCount, 0);
  });

  test('searches names, paths and the related app', () {
    final cubit = scanningCubit()
      ..addMeasurements(allMeasured())
      ..setInactiveDays(0);
    addTearDown(cubit.close);

    cubit.setSearchQuery('oldgame');
    expect(cubit.state.visibleCandidates.map((c) => c.displayName), <String>[
      'OldGame',
    ]);
    cubit.setSearchQuery('product 2');
    expect(cubit.state.visibleCandidates.map((c) => c.displayName), <String>[
      r'Vendor\Product',
    ]);
  });

  test('selection never covers hidden folders', () {
    final cubit = scanningCubit()
      ..addMeasurements(allMeasured())
      ..setInactiveDays(0);
    addTearDown(cubit.close);

    cubit.selectAllVisible();
    expect(cubit.state.selectedPaths, hasLength(3));
    expect(cubit.state.selectedBytes, 450 * _mib);

    cubit.setInactiveDays(180);
    expect(cubit.state.selectedPaths, <String>{r'C:\Data\OldGame'});

    // Hidden folders cannot be selected directly either.
    cubit.toggleSelected(r'C:\Data\Busy');
    expect(cubit.state.selectedPaths, <String>{r'C:\Data\OldGame'});

    cubit.toggleSelected(r'C:\Data\OldGame');
    expect(cubit.state.selectedPaths, isEmpty);
  });

  test('checks and unchecks a group, skipping hidden folders', () {
    final cubit = scanningCubit()..addMeasurements(allMeasured());
    addTearDown(cubit.close);

    // Busy is hidden by the default inactivity filter.
    cubit.setSelected(<String>[r'C:\Data\OldGame', r'C:\Data\Busy'], true);
    expect(cubit.state.selectedPaths, <String>{r'C:\Data\OldGame'});

    cubit.setSelected(<String>[r'C:\Data\OldGame'], false);
    expect(cubit.state.selectedPaths, isEmpty);
  });

  test('removes deleted folders, their measurement and selection', () {
    final cubit = scanningCubit()
      ..addMeasurements(allMeasured())
      ..setInactiveDays(0)
      ..selectAllVisible();
    addTearDown(cubit.close);

    cubit.removePaths(<String>[r'c:\data\vendor']);

    expect(cubit.state.visibleCandidates.map((c) => c.displayName), <String>[
      'OldGame',
      'Busy',
    ]);
    expect(
      cubit.state.measurements.keys,
      isNot(contains(r'C:\Data\Vendor\Product')),
    );
    expect(cubit.state.selectedPaths, <String>{
      r'C:\Data\OldGame',
      r'C:\Data\Busy',
    });
  });

  test('a new report resets measurements and selection', () {
    final cubit = scanningCubit()
      ..addMeasurements(allMeasured())
      ..selectAllVisible()
      ..setReport(report());

    addTearDown(cubit.close);
    expect(cubit.state.measurements, isEmpty);
    expect(cubit.state.selectedPaths, isEmpty);
    expect(cubit.state.status, CleanerAppLeftoversStatus.ready);
  });
}
