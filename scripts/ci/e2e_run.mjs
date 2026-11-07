#!/usr/bin/env node
// One build/launch for selected desktop suites. Scoped groups preserve hooks;
// native/focus tests remain sequential on the real desktop.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { loadConfig, repoRoot } from './e2e_select.mjs';
import { coveredSuites, executionSuites, reportResults, suitePattern } from './e2e_plan.mjs';

const projectDir = path.join(repoRoot, 'cb_file_manager');
const logDir = path.join(projectDir, 'build/e2e-logs');
const reportFile = path.join(logDir, 'desktop.jsonl');
const config = loadConfig();
const index = process.argv.indexOf('--suites');
const previousFile = path.join(logDir, 'summary.json');
const previous = process.argv.includes('--failed') && fs.existsSync(previousFile)
  ? JSON.parse(fs.readFileSync(previousFile, 'utf8')) : null;
const requested = process.argv.includes('--all') ? Object.keys(config.suites)
  : process.argv.includes('--failed') ? (previous?.results ?? []).filter(item => !item.ok).map(item => item.id)
  : index < 0 ? [] : (process.argv[index + 1] ?? '').split(',').map(s => s.trim()).filter(Boolean);
const unknown = requested.filter(id => !config.suites[id]);
if (unknown.length) {
  console.error(`Unknown E2E suite(s): ${unknown.join(', ')}`);
  process.exit(2);
}
if (!requested.length) {
  console.log('No E2E suites requested.');
  process.exit(0);
}
const suites = executionSuites(requested);
const args = ['test', 'integration_test/desktop_e2e_test.dart', '--no-pub', '-d', 'windows',
  '--dart-define=CB_E2E=true', '--dart-define=CB_E2E_FAST=true',
  '--reporter', 'json', '--file-reporter', `json:${reportFile}`, '--name', suitePattern(suites)];

function killApp() {
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/F', '/IM', 'cb_file_hub.exe', '/T'], { stdio: 'ignore' });
  }
}

fs.mkdirSync(logDir, { recursive: true });
fs.rmSync(reportFile, { force: true });
killApp();
const started = Date.now();
let result;
try {
  // flutter is a .bat shim on Windows. Quote all arguments: the regex's pipes
  // must be passed to Flutter, never interpreted by cmd.exe.
  const quoted = args.map(arg => `"${arg.replaceAll('"', '\\"')}"`).join(' ');
  result = process.platform === 'win32'
    ? spawnSync(`flutter ${quoted}`, { cwd: projectDir, encoding: 'utf8', maxBuffer: 1024 ** 3, shell: true })
    : spawnSync('flutter', args, { cwd: projectDir, encoding: 'utf8', maxBuffer: 1024 ** 3 });
} finally {
  killApp();
}
const seconds = Math.round((Date.now() - started) / 1000);
const output = `${result.stdout ?? ''}${result.stderr ?? ''}${result.error ?? ''}`;
fs.writeFileSync(path.join(logDir, 'desktop.log'), output);
const report = fs.existsSync(reportFile) ? fs.readFileSync(reportFile, 'utf8') : '';
fs.writeFileSync(path.join(projectDir, 'build/e2e_report.jsonl'), report);
const parsed = reportResults(report, suites);
if (result.status === null || (result.status !== 0 && parsed.results.every(item => item.ok))) {
  for (const item of parsed.results) item.ok = false;
}
const passed = coveredSuites(parsed.results.filter(item => item.ok).map(item => item.id));
const failed = parsed.results.filter(item => !item.ok).map(item => item.id);
fs.writeFileSync(path.join(logDir, 'summary.json'), JSON.stringify({
  seconds, firstTestMs: parsed.firstTestMs, exitCode: result.status, results: parsed.results,
}, null, 2));
for (const item of parsed.results) {
  fs.writeFileSync(path.join(logDir, `${item.id}.log`), output);
  console.log(`E2E ${item.id}: ${item.ok ? 'passed' : 'FAILED'} (${item.passed} passed, ${item.failed} failed, ${item.skipped} skipped, ${item.seconds}s tests)`);
}
console.log(`E2E total: ${seconds}s; first test after ${parsed.firstTestMs == null ? 'unknown' : `${(parsed.firstTestMs / 1000).toFixed(1)}s`}.`);
if (failed.length || result.status !== 0) console.log(output);
if (process.env.GITHUB_OUTPUT) {
  fs.appendFileSync(process.env.GITHUB_OUTPUT, `passed=${passed.join('.')}\nfailed=${failed.join(',')}\n`);
}
const summary = ['## E2E results', '', '| Suite | Result | Passed | Skipped | Test time |',
  '| --- | --- | --- | --- | --- |',
  ...parsed.results.map(r => `| ${r.id} | ${r.ok ? 'passed' : '**failed**'} | ${r.passed} | ${r.skipped} | ${r.seconds}s |`),
  '', `Total build/startup/tests: ${seconds}s.`, ''].join('\n');
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
console.log(summary);
process.exit(failed.length > 0 || result.status !== 0 ? 1 : 0);
