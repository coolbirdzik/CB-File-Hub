import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import { loadConfig, repoRoot, fingerprintPaths } from '../ci/e2e_select.mjs';
import { coveredSuites, executionSuites, reportResults, suitePattern } from '../ci/e2e_plan.mjs';

const start = (id, name, time = 100) => ({ type: 'testStart', test: { id, name }, time });
const end = (id, overrides = {}) => ({ type: 'testDone', testID: id, result: 'success',
  hidden: false, skipped: false, time: 200, ...overrides });
const done = { type: 'done', success: true };
const report = (...events) => ['Building Windows application...', ...events.map(event => JSON.stringify(event))].join('\n');

test('every configured suite is registered in the shared desktop entrypoint', () => {
  const source = fs.readFileSync(path.join(repoRoot, 'cb_file_manager/integration_test/desktop_e2e_test.dart'), 'utf8');
  for (const id of Object.keys(loadConfig().suites).filter(id => id !== 'smoke')) {
    assert.ok(source.includes(`group('${id}',`), id);
  }
  assert.ok(fingerprintPaths.includes('cb_native'), 'Rust changes must invalidate cached E2E passes');
});

test('app covers smoke without dropping any other selected suite', () => {
  assert.deepEqual(executionSuites(['smoke', 'app', 'app', 'torrent_library']), ['app', 'torrent_library']);
  assert.deepEqual(executionSuites(['smoke']), ['smoke']);
  assert.deepEqual(coveredSuites(['app']), ['app', 'smoke']);
});

test('combined entrypoint filters select exact suite boundaries', () => {
  const selected = new RegExp(suitePattern(['app', 'torrent_library']));
  assert.ok(selected.test('app 01 Navigation lists a folder'));
  assert.ok(selected.test('torrent_library Torrent Library opens'));
  assert.ok(!selected.test('video_thumbnails Video Thumbnails opens'));
  assert.ok(!selected.test('application unrelated'));
  const smoke = new RegExp(suitePattern(['smoke']));
  assert.ok(smoke.test('app 01 Navigation opens'));
  assert.ok(!smoke.test('app 02 File Operations opens'));
});

test('report requires executed assertions and terminal event for each suite', () => {
  for (const content of ['', report(done), report(start(1, 'app case'), end(1)),
    report(start(1, 'app case'), end(1, { skipped: true }), done)]) {
    assert.equal(reportResults(content, ['app']).results[0].ok, false);
  }
  const parsed = reportResults(report(start(1, 'app case'), end(1), done), ['app', 'torrent_library']);
  assert.equal(parsed.results[0].ok, true);
  assert.equal(parsed.results[0].passed, 1);
  assert.equal(parsed.results[1].ok, false);
  assert.equal(parsed.firstTestMs, 100);
});

test('failed setup and unfinished tests invalidate a suite', () => {
  for (const failure of [end(2, { result: 'error', hidden: true }), null]) {
    const content = report(start(1, 'app case'), end(1), start(2, 'app (tearDownAll)'),
      ...(failure ? [failure] : []), done);
    assert.equal(reportResults(content, ['app']).results[0].ok, false);
  }
});

test('root setup failure invalidates all selected suites', () => {
  const parsed = reportResults(report(start(1, 'app case'), end(1),
    start(2, '(tearDownAll)'), end(2, { result: 'error', hidden: true }), done), ['app']);
  assert.equal(parsed.results[0].ok, false);
});

test('one failing suite does not discard another fully completed suite', () => {
  const parsed = reportResults(report(start(1, 'app case'), end(1),
    start(2, 'torrent_library case'), end(2, { result: 'failure' }),
    { type: 'done', success: false }), ['app', 'torrent_library']);
  assert.equal(parsed.results[0].ok, true);
  assert.equal(parsed.results[1].ok, false);
});

test('global errors or an unexplained unsuccessful footer cannot seed pass caches', () => {
  for (const extra of [[], [{ type: 'error', error: 'runner failed', testID: null }]]) {
    const parsed = reportResults(report(start(1, 'app case'), end(1),
      ...extra, { type: 'done', success: false }), ['app']);
    assert.equal(parsed.results[0].ok, false);
  }
});
