#!/usr/bin/env node
// Runs the Windows E2E suites chosen by e2e_select.mjs, one `flutter test`
// process per suite. Flutter desktop integration_test cannot run several test
// files in one invocation (the second app launch loses its debug connection),
// so stray cb_file_hub.exe processes are killed before and after each suite.
//
// Every suite runs even when an earlier one fails, so one CI run reports all
// regressions. Passed suite ids are written to the `passed` step output; the
// workflow saves them as an `e2e-pass-<fingerprint>-<passed>` cache marker.
//
// Usage: node scripts/ci/e2e_run.mjs --suites app,media_kit_playback

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { loadConfig, repoRoot } from './e2e_select.mjs';

const projectDir = path.join(repoRoot, 'cb_file_manager');

function killApp() {
  if (process.platform !== 'win32') return;
  spawnSync('taskkill', ['/F', '/IM', 'cb_file_hub.exe', '/T'], { stdio: 'ignore' });
}

// flutter/dart are .bat shims on Windows, so they must go through the shell.
const quote = (arg) => (/[\s"]/.test(arg) ? `"${arg.replace(/"/g, '\\"')}"` : arg);

function parseSuites(argv) {
  const index = argv.indexOf('--suites');
  const value = index === -1 ? '' : argv[index + 1] ?? '';
  return value.split(',').map((suite) => suite.trim()).filter(Boolean);
}

const config = loadConfig();
const requested = parseSuites(process.argv.slice(2));
const unknown = requested.filter((suite) => !config.suites[suite]);
if (unknown.length > 0) {
  console.error(`Unknown E2E suite(s): ${unknown.join(', ')}`);
  process.exit(2);
}
if (requested.length === 0) {
  console.log('No E2E suites requested.');
  process.exit(0);
}

const results = [];
for (const [id, suite] of Object.entries(config.suites)) {
  if (!requested.includes(id)) continue;
  const commandLine = suite.command.map(quote).join(' ');
  console.log(`::group::E2E ${id}: ${commandLine}`);
  killApp();
  const started = Date.now();
  const result = spawnSync(commandLine, { cwd: projectDir, stdio: 'inherit', shell: true });
  killApp();
  const seconds = Math.round((Date.now() - started) / 1000);
  console.log('::endgroup::');
  const ok = result.status === 0;
  if (!ok) console.log(`::error::E2E suite ${id} failed (exit ${result.status ?? result.signal})`);
  results.push({ id, ok, seconds });
}

const passed = results.filter((r) => r.ok).map((r) => r.id);
const failed = results.filter((r) => !r.ok).map((r) => r.id);

if (process.env.GITHUB_OUTPUT) {
  fs.appendFileSync(process.env.GITHUB_OUTPUT, `passed=${passed.join('.')}\nfailed=${failed.join(',')}\n`);
}
const summary = [
  '## E2E results',
  '',
  '| Suite | Result | Time |',
  '| --- | --- | --- |',
  ...results.map((r) => `| ${r.id} | ${r.ok ? 'passed' : '**failed**'} | ${r.seconds}s |`),
  '',
].join('\n');
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
console.log(summary);

process.exit(failed.length > 0 ? 1 : 0);
