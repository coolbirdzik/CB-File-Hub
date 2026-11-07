import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_allure_adapter.dart' as allure;
import '../../tool/e2e_dashboard.dart' as dashboard;

void main() {
  Map<String, Object> start(int id, String name, int time) => {
    'type': 'testStart',
    'test': {'id': id, 'name': name},
    'time': time,
  };
  Map<String, Object> end(
    int id, {
    String result = 'success',
    bool skipped = false,
    bool hidden = false,
  }) => {
    'type': 'testDone',
    'testID': id,
    'time': 250,
    'result': result,
    'skipped': skipped,
    'hidden': hidden,
  };
  String log(List<Map<String, Object>> events) =>
      events.map(jsonEncode).join('\n');
  final done = <String, Object>{'type': 'done', 'success': true};

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb_report_parser_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'reports preserve separate error events, skip flags and real elapsed time',
    () {
      final content = log([
        start(0, 'loading fixture.dart', 0),
        end(0, hidden: true),
        start(1, 'app 01 Navigation passed case', 100),
        end(1),
        start(2, 'app 01 Navigation failed case', 150),
        {
          'type': 'error',
          'testID': 2,
          'error': 'Expected bytes to match',
          'stackTrace': 'fixture.dart:42',
        },
        end(2, result: 'failure'),
        start(3, 'app 01 Navigation optional case', 200),
        end(3, skipped: true),
        done,
      ]);
      final a = allure.parseFlutterJsonLog(content, buildDir: root.path);
      expect(a.map((test) => test.status), ['passed', 'failed', 'skipped']);
      expect(a.first.duration, 150);
      expect(a[1].message, 'Expected bytes to match');
      expect(
        a.first.labels.firstWhere((label) => label.name == 'suite').value,
        '01 Navigation',
      );
      final d = dashboard.parseJsonLog(content, root.path, {});
      expect(d.tests.map((test) => test.status), [
        'passed',
        'failed',
        'skipped',
      ]);
      expect(d.passed, 1);
      expect(d.skipped, 1);
      final html = dashboard.generateHtml(d);
      expect(html, contains('SKIPPED'));
      expect(html, contains('data-filter="skipped"'));
    },
  );

  test('started tests in a truncated log never appear passed', () {
    final content = log([start(1, 'app 01 Navigation unfinished', 100)]);
    expect(
      allure.parseFlutterJsonLog(content, buildDir: root.path).single.status,
      'broken',
    );
    expect(dashboard.parseJsonLog(content, root.path, {}).passed, 0);
  });

  test('a hidden setup failure stays visible in the report', () {
    final content = log([
      start(1, 'app (setUpAll)', 100),
      {
        'type': 'error',
        'testID': 1,
        'error': 'Database could not open',
        'stackTrace': 'fixture.dart:1',
      },
      end(1, result: 'error', hidden: true),
      done,
    ]);
    expect(
      allure.parseFlutterJsonLog(content, buildDir: root.path).single.status,
      'failed',
    );
    expect(
      dashboard.parseJsonLog(content, root.path, {}).suiteError,
      contains('Database could not open'),
    );
  });

  test('exact grouped test identity attaches its indexed screenshot', () async {
    const name = 'app 01 Navigation screenshot case';
    final screenshots = Directory('${root.path}/e2e_report/screenshots');
    await screenshots.create(recursive: true);
    await File(
      '${screenshots.path}/001_checkpoint.png',
    ).writeAsBytes([137, 80, 78, 71]);
    await File('${root.path}/e2e_report/manifest.json').writeAsString(
      jsonEncode({
        'entries': [
          {'testName': name, 'filename': '001_checkpoint.png'},
        ],
      }),
    );
    final content = log([start(1, name, 100), end(1), done]);
    expect(
      allure
          .parseFlutterJsonLog(content, buildDir: root.path)
          .single
          .attachments
          .single
          .source,
      '001_checkpoint.png',
    );
  });

  test('global runner failure cannot produce an all-passed Allure report', () {
    final content = log([
      start(1, 'app 01 Navigation done case', 100),
      end(1),
      {'type': 'done', 'success': false},
    ]);
    final results = allure.parseFlutterJsonLog(content, buildDir: root.path);
    expect(results.any((test) => test.status == 'broken'), isTrue);
  });

  test(
    'new Allure conversion removes stale results and retains other metadata',
    () async {
      await File('${root.path}/environment.json').writeAsString('{}');
      await allure.writeAllureResults([
        allure.AllureTestResult(
          uuid: 'aabbccdd-00000001',
          name: 'old pass',
          status: 'passed',
        ),
      ], root.path);
      await allure.writeAllureResults([
        allure.AllureTestResult(
          uuid: 'aabbccdd-00000002',
          name: 'current failure',
          status: 'failed',
        ),
      ], root.path);
      expect(
        await File('${root.path}/aabbccdd-00000001.json').exists(),
        isFalse,
      );
      expect(
        await File('${root.path}/aabbccdd-00000002.json').exists(),
        isTrue,
      );
      expect(await File('${root.path}/environment.json').exists(), isTrue);
    },
  );
  test('combined suite identities replace their legacy dashboard history', () {
    final merged = dashboard.mergeReportResults(
      {
        '01 Navigation case': dashboard.TestResult(
          name: '01 Navigation case',
          status: 'passed',
        ),
      },
      [dashboard.TestResult(name: 'app 01 Navigation case', status: 'failed')],
    );
    expect(merged, hasLength(1));
    expect(merged.values.single.status, 'failed');
  });
}
