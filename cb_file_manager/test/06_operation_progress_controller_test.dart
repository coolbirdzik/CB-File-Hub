import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('06.01 tracks multiple concurrent entries', () {
    final controller = OperationProgressController();

    final copyId = controller.begin(
      title: 'Copying files',
      total: 4,
      kind: OperationProgressKind.copy,
    );
    final deleteId = controller.begin(
      title: 'Deleting files',
      total: 2,
      kind: OperationProgressKind.delete,
    );

    expect(
        controller.runningEntries.map((entry) => entry.id), contains(copyId));
    expect(
        controller.runningEntries.map((entry) => entry.id), contains(deleteId));
    expect(controller.runningEntries, hasLength(2));
  });

  test('06.02 computes aggregate progress across determinate tasks', () {
    final controller = OperationProgressController();

    final first = controller.begin(title: 'First', total: 4);
    final second = controller.begin(title: 'Second', total: 6);
    controller.update(first, completed: 2);
    controller.update(second, completed: 3);

    final aggregate = controller.aggregateProgress;

    expect(aggregate.hasRunning, isTrue);
    expect(aggregate.isIndeterminate, isFalse);
    expect(aggregate.fraction, 0.5);
    expect(aggregate.runningCount, 2);
  });

  test('06.03 keeps success and failure entries in history', () {
    final controller = OperationProgressController();

    final success = controller.begin(title: 'Success', total: 1);
    final failure = controller.begin(title: 'Failure', total: 1);
    controller.succeed(success, detail: 'Done');
    controller.fail(failure, detail: 'Failed');

    expect(controller.runningEntries, isEmpty);
    expect(controller.finishedEntries, hasLength(2));
    expect(
      controller.finishedEntries.map((entry) => entry.status),
      containsAll(<OperationProgressStatus>[
        OperationProgressStatus.success,
        OperationProgressStatus.error,
      ]),
    );
  });

  test(
      '06.04 dismiss removes a single entry and dismissFinished clears history',
      () {
    final controller = OperationProgressController();

    final running = controller.begin(title: 'Running', total: 1);
    final finished = controller.begin(title: 'Finished', total: 1);
    controller.succeed(finished);

    controller.dismiss(finished);

    expect(controller.entries.map((entry) => entry.id), contains(running));
    expect(
        controller.entries.map((entry) => entry.id), isNot(contains(finished)));

    controller.succeed(running);
    controller.dismissFinished();

    expect(controller.entries, isEmpty);
  });

  test('06.05 indeterminate tasks make aggregate indeterminate', () {
    final controller = OperationProgressController();

    controller.begin(title: 'Scan', total: 0, isIndeterminate: true);

    final aggregate = controller.aggregateProgress;

    expect(aggregate.hasRunning, isTrue);
    expect(aggregate.isIndeterminate, isTrue);
    expect(aggregate.fraction, isNull);
  });

  test(
      '06.06 markAllSeen clears notification badge count without removing entries',
      () {
    final controller = OperationProgressController();

    final first = controller.begin(title: 'First', total: 1);
    final second = controller.begin(title: 'Second', total: 1);

    expect(controller.unseenCount, 2);

    controller.markAllSeen();

    expect(controller.unseenCount, 0);
    expect(controller.entries.map((entry) => entry.id), contains(first));
    expect(controller.entries.map((entry) => entry.id), contains(second));

    controller.begin(title: 'Third', total: 1);

    expect(controller.unseenCount, 1);
  });
}
