import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import {
  globToRegExp,
  loadConfig,
  markerKeyPrefix,
  passedSuitesFromCaches,
  planFromEvent,
  repoRoot,
  selectSuites,
} from '../ci/e2e_select.mjs';

const config = loadConfig();
const allSuites = Object.keys(config.suites);
const select = (...files) => selectSuites(files, config).suites;
const trackedFiles = spawnSync('git', ['ls-files'], { cwd: repoRoot, encoding: 'utf8' })
  .stdout.split('\n').filter(Boolean);

test('every E2E test file is either a CI suite or explicitly left out', () => {
  const testDir = path.join(repoRoot, 'cb_file_manager/integration_test');
  const suiteFiles = new Set(Object.values(config.suites).map((suite) => suite.file));
  for (const file of suiteFiles) {
    assert.ok(fs.existsSync(path.join(repoRoot, 'cb_file_manager', file)), file);
  }
  for (const name of fs.readdirSync(testDir).filter((n) => n.endsWith('_e2e_test.dart'))) {
    const file = `integration_test/${name}`;
    assert.ok(suiteFiles.has(file) || config.notInCi[file],
      `${file} must be added to e2e_impact.json "suites" or "notInCi"`);
  }
});

test('globs match path segments the way the rules expect', () => {
  assert.ok(globToRegExp('**/*.md').test('README.md'));
  assert.ok(globToRegExp('**/*.md').test('cb_file_manager/lib/helpers/README.md'));
  assert.ok(globToRegExp('docs/**').test('docs/features/10-torrent-library.md'));
  assert.ok(!globToRegExp('scripts/*.mjs').test('scripts/ci/e2e_select.mjs'));
  assert.ok(globToRegExp('cb_file_manager/pubspec.{yaml,lock}').test('cb_file_manager/pubspec.lock'));
  assert.ok(globToRegExp('lib/models/{a.dart,objectbox/**}').test('lib/models/objectbox/x/y.dart'));
  assert.ok(!globToRegExp('lib/core/**').test('lib/core_extra/a.dart'));
});

test('changes map to the suites that exercise them', () => {
  assert.deepEqual(select('docs/features/10-torrent-library.md', 'store/listing.json'), []);
  assert.deepEqual(select('cb_file_manager/test/widget_test.dart'), []);
  assert.deepEqual(select('cb_file_manager/lib/ui/components/video/video_player/video_player.dart'),
    ['media_kit_playback']);
  assert.deepEqual(select('cb_file_manager/lib/services/torrent/aria2_engine.dart'), ['torrent_library']);
  assert.deepEqual(select('cb_file_manager/lib/ui/components/common/breadcrumb_address_bar.dart'),
    ['app', 'breadcrumb_address_bar_overflow']);
  assert.deepEqual(select('cb_file_manager/lib/services/ssh/ssh_client.dart'), ['smoke']);
  assert.deepEqual(select('cb_file_manager/lib/services/ssh/ssh_client.dart',
    'cb_file_manager/lib/ui/dialogs/create_file_dialog.dart'), ['app']);
});

test('content conditions narrow version bumps and new translation keys', () => {
  const pubspec = 'cb_file_manager/pubspec.yaml';
  const english = 'cb_file_manager/lib/config/languages/english_localizations.dart';
  const diffs = {
    [pubspec]: '--- a/x\n+++ b/x\n@@ -4 +4 @@\n-version: 1.1.17+3\n+version: 1.1.18+1\n',
    [english]: '--- a/x\n+++ b/x\n@@ -90,0 +91,2 @@\n+  @override\n+  String get newKey => \'New\';\n',
  };
  assert.deepEqual(selectSuites([pubspec, english], config, (file) => diffs[file]).suites, ['smoke']);

  const everything = allSuites.filter((suite) => suite !== 'smoke');
  const edited = { [english]: '@@ -91 +91 @@\n-  String get delete => \'Delete\';\n+  String get delete => \'Remove\';\n' };
  assert.deepEqual(selectSuites([english], config, (file) => edited[file]).suites, everything);
  const dependency = { [pubspec]: '@@ -40,0 +41 @@\n+  path: ^1.9.0\n' };
  assert.deepEqual(selectSuites([pubspec], config, (file) => dependency[file]).suites, everything);
  // Without diff content the conditional rules never apply.
  assert.deepEqual(select(pubspec), everything);
});

test('shared inputs and unknown paths run every suite except the redundant smoke run', () => {
  const everything = allSuites.filter((suite) => suite !== 'smoke');
  assert.deepEqual(select('cb_file_manager/pubspec.lock'), everything);
  assert.deepEqual(select('cb_file_manager/lib/main.dart'), everything);
  assert.deepEqual(select('cb_file_manager/windows/runner/main.cpp'), everything);
  assert.deepEqual(select('some_new_top_level_dir/thing.dart'), everything);
  assert.equal(selectSuites(['some_new_top_level_dir/thing.dart'], config).reasons[0].why,
    'No rule in e2e_impact.json matches this path');
});

test('every tracked Dart source in lib/ is covered by an explicit rule', () => {
  const rules = config.rules.map((rule) => rule.paths.map(globToRegExp));
  const uncovered = trackedFiles
    .filter((file) => file.startsWith('cb_file_manager/lib/'))
    .filter((file) => !rules.some((patterns) => patterns.some((pattern) => pattern.test(file))));
  assert.deepEqual(uncovered, []);
});

test('main is a full gate, other branches diff, and full runs can be forced', () => {
  assert.equal(planFromEvent({ eventName: 'push', refName: 'main', payload: {} }).mode, 'full');
  assert.equal(planFromEvent({ eventName: 'push', refName: 'main', payload: {} }).useCache, true);
  assert.deepEqual(planFromEvent({ eventName: 'push', refName: 'develop', payload: {} }).diff, 'last-green');
  assert.equal(planFromEvent({
    eventName: 'pull_request', refName: '12/merge', payload: { pull_request: { base: { ref: 'main' } } },
  }).mode, 'full');
  assert.equal(planFromEvent({
    eventName: 'pull_request', refName: '12/merge', payload: { pull_request: { base: { ref: 'develop' } } },
  }).diff, 'pr');

  const forced = [
    planFromEvent({ eventName: 'push', refName: 'develop', payload: { head_commit: { message: 'fix: x [E2E full]' } } }),
    planFromEvent({
      eventName: 'pull_request',
      refName: '12/merge',
      payload: { pull_request: { base: { ref: 'develop' }, labels: [{ name: 'e2e:full' }] } },
    }),
    planFromEvent({ eventName: 'workflow_dispatch', refName: 'develop', payload: { inputs: { full_e2e: 'true' } } }),
  ];
  for (const plan of forced) assert.deepEqual([plan.mode, plan.useCache], ['full', false]);
});

test('pass markers only count for this fingerprint and trusted refs', () => {
  const fp = 'abc123';
  const caches = [
    { key: `${markerKeyPrefix(fp)}app.media_kit_playback`, ref: 'refs/heads/develop' },
    { key: `${markerKeyPrefix(fp)}torrent_library`, ref: 'refs/pull/7/merge' },
    { key: `${markerKeyPrefix(fp)}smoke`, ref: 'refs/pull/9/merge' },
    { key: `${markerKeyPrefix('other')}file_drag_drop`, ref: 'refs/heads/develop' },
  ];
  assert.deepEqual([...passedSuitesFromCaches(caches, fp, 'refs/pull/9/merge')].sort(),
    ['app', 'media_kit_playback', 'smoke']);
});
