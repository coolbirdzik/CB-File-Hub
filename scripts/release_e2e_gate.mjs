#!/usr/bin/env node
// Release gate: every CI E2E suite must pass locally on the exact commit that
// is about to be released. scripts/release.sh runs this before it bumps the
// version, so a failing suite stops the release before any commit or tag.
//
// It runs the same suites, the same way, as the `e2e-windows` CI job on main
// (scripts/ci/e2e_run.mjs, one shared desktop entrypoint for pending suites).
//
// A pass is recorded per suite under cb_file_manager/build/release-e2e/<fingerprint>/,
// where <fingerprint> is the CI source fingerprint of HEAD (e2e_select.mjs),
// including both native packages and the pinned build configuration. Rerunning
// the gate on the same source only runs the suites that have not passed yet. Any
// change to the fingerprinted sources starts over, and `flutter clean` clears them.
//
// The working tree must be clean: the fingerprint hashes HEAD, so uncommitted
// changes would be released untested (or tested but not released).
//
// Usage:
//   node scripts/release_e2e_gate.mjs           # run missing suites, exit 1 on failure
//   node scripts/release_e2e_gate.mjs --status  # show recorded passes, run nothing

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { loadConfig, repoRoot, sourceFingerprint } from './ci/e2e_select.mjs';
import { coveredSuites } from './ci/e2e_plan.mjs';

const projectDir = path.join(repoRoot, 'cb_file_manager');
const statusOnly = process.argv.includes('--status');

function fail(message) {
  console.error(`\n[release-e2e] ${message}`);
  process.exit(1);
}

function run(command, args, { cwd = repoRoot, shell = false } = {}) {
  const result = spawnSync(command, args, { cwd, stdio: 'inherit', shell });
  if (result.status !== 0) {
    fail(`'${[command, ...args].join(' ')}' failed (exit ${result.status ?? result.error ?? result.signal}).`);
  }
}

function gitStatus() {
  const result = spawnSync('git', ['status', '--porcelain'], { cwd: repoRoot, encoding: 'utf8' });
  if (result.status !== 0) fail(`git status failed: ${result.stderr.trim()}`);
  return result.stdout.trimEnd();
}

// Same edit as the "Patch pdfx CMake compatibility" CI step.
function patchPdfxCmake() {
  const dir = path.join(projectDir, 'windows/flutter/ephemeral/.plugin_symlinks/pdfx/windows');
  if (!fs.existsSync(dir)) return;
  const walk = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (/\.(cmake|txt|in)$/.test(entry.name)) {
        const text = fs.readFileSync(full, 'utf8');
        const patched = text.replace(/cmake_minimum_required\(VERSION [0-9.]+\)/g, 'cmake_minimum_required(VERSION 3.14)');
        if (patched !== text) fs.writeFileSync(full, patched);
      }
    }
  };
  walk(dir);
}

const dirty = gitStatus();
if (dirty) {
  fail(`Working tree is not clean. Commit or stash these changes first, so the E2E run tests exactly what gets released:\n${dirty}`);
}

const releaseFingerprint = sourceFingerprint;

const suites = Object.keys(loadConfig().suites);
const fingerprint = releaseFingerprint();
const markerDir = path.join(projectDir, 'build', 'release-e2e', fingerprint);
const markerFile = (suite) => path.join(markerDir, `${suite}.passed`);
const pending = suites.filter((suite) => !fs.existsSync(markerFile(suite)));

console.log(`[release-e2e] Source fingerprint ${fingerprint}`);
for (const suite of suites) {
  console.log(`  ${pending.includes(suite) ? 'pending' : 'passed '}  ${suite}`);
}

if (statusOnly) process.exit(0);

if (pending.length === 0) {
  console.log('[release-e2e] Every E2E suite already passed on this source. Continuing.');
  process.exit(0);
}

if (process.platform !== 'win32') {
  fail('The CI E2E suites run on Windows only (-d windows). Release from Windows so they can pass locally first.');
}

// Prerequisites of the e2e-windows CI job.
console.log('\n[release-e2e] Preparing (pub get, llama.cpp + aria2 runtimes)...');
run('flutter', ['pub', 'get'], { cwd: projectDir, shell: true });
patchPdfxCmake();
run('bash', ['scripts/fetch_llama_runtime.sh']);
run('bash', ['scripts/fetch_aria2_runtime.sh']);
const dirtyAfterPrep = gitStatus();
if (dirtyAfterPrep) {
  fail(`Preparing the E2E run changed tracked files (e.g. pubspec.lock). Commit them first:\n${dirtyAfterPrep}`);
}

// Batch pending suites through one desktop build/launch. Preserve individual
// passes after an ordinary assertion failure, but never cache a crashed run.
const summaryPath = path.join(projectDir, 'build/e2e-logs/summary.json');
fs.rmSync(summaryPath, { force: true });
const result = spawnSync(process.execPath,
  ['scripts/ci/e2e_run.mjs', '--suites', pending.join(',')],
  { cwd: repoRoot, stdio: 'inherit' });
if (gitStatus() || releaseFingerprint() !== fingerprint) {
  fail('Sources changed during E2E. No passes were recorded; commit the final sources and rerun.');
}
const summary = fs.existsSync(summaryPath)
  ? JSON.parse(fs.readFileSync(summaryPath, 'utf8')) : null;
const passed = coveredSuites(summary && result.status !== null
  ? summary.results.filter(item => item.ok).map(item => item.id) : []);
fs.mkdirSync(markerDir, { recursive: true });
for (const suite of pending.filter(id => passed.includes(id))) {
  fs.writeFileSync(markerFile(suite), `${new Date().toISOString()}\n`);
}
const failed = pending.filter(suite => !passed.includes(suite));

if (failed.length > 0 || result.status !== 0) {
  fail(
    `E2E failed: ${failed.join(', ')}. Release blocked.\n` +
    'Logs: cb_file_manager/build/e2e-logs/<suite>.log. Fix and commit, then rerun the release ' +
    '(suites that passed on unchanged source are not rerun).',
  );
}

console.log('\n[release-e2e] All E2E suites passed. Continuing with the release.');
