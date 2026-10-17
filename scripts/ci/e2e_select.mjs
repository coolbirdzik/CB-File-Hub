#!/usr/bin/env node
// Picks the Windows E2E suites a change set needs, so CI does not rerun every
// suite for every push. Rules live in cb_file_manager/integration_test/e2e_impact.json.
//
// Three layers, applied in order:
//   1. Scope: pushes/PRs to `main`, `workflow_dispatch` with full_e2e, a PR
//      labelled `e2e:full` or a head commit containing `[e2e full]` select every
//      suite. Other branches diff against the last green run on the branch (or
//      the PR base) and map changed paths to suites.
//   2. Pass markers: a suite that already passed on the exact same source
//      fingerprint (cache key `e2e-pass-<fingerprint>-<suites>`, saved by
//      e2e_run.mjs via actions/cache) is skipped. Forced full runs ignore them.
//   3. Fallback: anything the rules do not know about runs every suite.
//
// CI:     node scripts/ci/e2e_select.mjs        (reads GITHUB_* env, writes outputs)
// Local:  node scripts/ci/e2e_select.mjs [base]  (default base: the branch's
//         upstream, else develop; includes uncommitted and untracked files)

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
export const configPath = path.join(repoRoot, 'cb_file_manager/integration_test/e2e_impact.json');

// Inputs whose content decides whether a recorded E2E pass is still valid.
export const fingerprintPaths = [
  'cb_file_manager',
  'mobile_smb_native',
  '.github/workflows/build-test.yml',
  'scripts/ci',
  'scripts/fetch_llama_runtime.sh',
  'scripts/fetch_aria2_runtime.sh',
];

export const fullRunLabel = 'e2e:full';
export const fullRunCommitTag = '[e2e full]';
export const fullScopeBranches = ['main'];

const changedLines = (diff) => diff.split('\n')
  .filter((line) => /^[+-]/.test(line) && !/^(\+\+\+|---) /.test(line));

/**
 * Content conditions a rule can require with "onlyIf". When the condition does
 * not hold (or no diff is available), the rule is skipped and later rules apply.
 */
export const diffConditions = {
  // Only lines were added: existing strings/behaviour are untouched.
  additions: (diff) => {
    const changed = changedLines(diff);
    return changed.length > 0 && changed.every((line) => line.startsWith('+'));
  },
  // Only the pubspec `version:` line changed (release bump).
  'version-line': (diff) => {
    const changed = changedLines(diff);
    return changed.length > 0 && changed.every((line) => /^[+-]version:/.test(line));
  },
};

export function loadConfig(file = configPath) {
  const config = JSON.parse(fs.readFileSync(file, 'utf8'));
  const known = new Set(Object.keys(config.suites));
  config.rules.forEach((rule, index) => {
    if (!Array.isArray(rule.paths) || rule.paths.length === 0) {
      throw new Error(`e2e_impact.json rule #${index} has no paths`);
    }
    if (rule.onlyIf !== undefined && !diffConditions[rule.onlyIf]) {
      throw new Error(`e2e_impact.json rule #${index}: unknown onlyIf "${rule.onlyIf}"`);
    }
    if (rule.suites === 'all') return;
    if (!Array.isArray(rule.suites)) {
      throw new Error(`e2e_impact.json rule #${index}: suites must be "all" or a list`);
    }
    for (const suite of rule.suites) {
      if (!known.has(suite)) throw new Error(`e2e_impact.json rule #${index}: unknown suite "${suite}"`);
    }
  });
  return config;
}

function globSource(glob) {
  let source = '';
  for (let i = 0; i < glob.length; i++) {
    const char = glob[i];
    if (char === '*' && glob[i + 1] === '*') {
      i++;
      if (glob[i + 1] === '/') {
        i++;
        source += '(?:.*/)?';
      } else {
        source += '.*';
      }
    } else if (char === '*') {
      source += '[^/]*';
    } else if (char === '?') {
      source += '[^/]';
    } else if (char === '{') {
      const close = glob.indexOf('}', i);
      if (close === -1) throw new Error(`Unclosed "{" in glob: ${glob}`);
      const options = glob.slice(i + 1, close).split(',').map(globSource);
      source += `(?:${options.join('|')})`;
      i = close;
    } else {
      source += char.replace(/[.+^${}()|[\]\\]/g, '\\$&');
    }
  }
  return source;
}

/** Converts a repo glob (`**`, `*`, `?`, `{a,b}`) to an anchored RegExp. */
export function globToRegExp(glob) {
  return new RegExp(`^${globSource(glob)}$`);
}

/**
 * Maps changed repo-relative paths to the suites they need. First matching rule
 * wins. [diffOf] returns a file's `git diff -U0` text for "onlyIf" rules.
 */
export function selectSuites(files, config, diffOf = null) {
  const allSuites = Object.keys(config.suites);
  const rules = config.rules.map((rule) => ({ ...rule, patterns: rule.paths.map(globToRegExp) }));
  const selected = new Set();
  const reasons = [];
  for (const file of files) {
    const rule = rules.find((candidate) => candidate.patterns.some((pattern) => pattern.test(file))
      && (!candidate.onlyIf || (diffOf !== null && diffConditions[candidate.onlyIf](diffOf(file)))));
    const suites = !rule || rule.suites === 'all' ? allSuites : rule.suites;
    const why = rule ? rule.why ?? 'Suite source' : 'No rule in e2e_impact.json matches this path';
    suites.forEach((suite) => selected.add(suite));
    reasons.push({ file, suites, why });
  }
  // The smoke suite is a subset of the full app suite.
  if (selected.has('app')) selected.delete('smoke');
  return { suites: allSuites.filter((suite) => selected.has(suite)), reasons };
}

export function markerKeyPrefix(fingerprint) {
  return `e2e-pass-${fingerprint}-`;
}

/**
 * Suites recorded as passed for [fingerprint]. Only markers written by branch
 * pushes (collaborators) or by this same ref (a re-run of this PR) count, so a
 * fork PR cannot mark suites as passed for anyone else.
 */
export function passedSuitesFromCaches(caches, fingerprint, currentRef) {
  const prefix = markerKeyPrefix(fingerprint);
  const passed = new Set();
  for (const cache of caches) {
    if (!cache.key?.startsWith(prefix)) continue;
    if (!(cache.ref?.startsWith('refs/heads/') || cache.ref === currentRef)) continue;
    for (const suite of cache.key.slice(prefix.length).split('.')) {
      if (suite) passed.add(suite);
    }
  }
  return passed;
}

/** Decides from the GitHub event whether to run everything or diff, and whether pass markers count. */
export function planFromEvent({ eventName, payload, refName }) {
  if (eventName === 'workflow_dispatch') {
    const full = payload.inputs?.full_e2e;
    if (full === true || full === 'true') {
      return { mode: 'full', useCache: false, reason: 'Manual run with full_e2e' };
    }
    return { mode: 'diff', diff: 'last-green', useCache: true, reason: `Manual run on ${refName}` };
  }
  if (eventName === 'pull_request') {
    const pr = payload.pull_request ?? {};
    if ((pr.labels ?? []).some((label) => label.name === fullRunLabel)) {
      return { mode: 'full', useCache: false, reason: `PR has the ${fullRunLabel} label` };
    }
    if (fullScopeBranches.includes(pr.base?.ref)) {
      return { mode: 'full', useCache: true, reason: `PR targets ${pr.base.ref}` };
    }
    return { mode: 'diff', diff: 'pr', useCache: true, reason: `PR into ${pr.base?.ref}` };
  }
  if (eventName === 'push') {
    if ((payload.head_commit?.message ?? '').toLowerCase().includes(fullRunCommitTag)) {
      return { mode: 'full', useCache: false, reason: `Head commit contains ${fullRunCommitTag}` };
    }
    if (fullScopeBranches.includes(refName)) {
      return { mode: 'full', useCache: true, reason: `Push to ${refName}` };
    }
    return { mode: 'diff', diff: 'last-green', useCache: true, reason: `Push to ${refName}` };
  }
  return { mode: 'full', useCache: true, reason: `Event ${eventName}` };
}

function git(args, { allowFailure = false } = {}) {
  const result = spawnSync('git', args, { cwd: repoRoot, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) {
    if (allowFailure) return null;
    throw new Error(`git ${args.join(' ')} failed: ${result.stderr.trim()}`);
  }
  return result.stdout.trim();
}

const lines = (text) => (text ? text.split('\n').map((line) => line.trim()).filter(Boolean) : []);

function isAncestor(sha) {
  if (!sha || /^0+$/.test(sha)) return false;
  return spawnSync('git', ['merge-base', '--is-ancestor', sha, 'HEAD'], { cwd: repoRoot }).status === 0;
}

/** Changed files plus a diff reader, from [base] to HEAD (or to the working tree). */
function diffSource(base, { workingTree = false } = {}) {
  const range = workingTree ? [base] : [base, 'HEAD'];
  return {
    files: lines(git(['diff', '--name-only', '--no-renames', ...range])),
    diffOf: (file) => git(['diff', '-U0', '--no-renames', ...range, '--', file], { allowFailure: true }) ?? '',
  };
}

export function sourceFingerprint() {
  const ids = fingerprintPaths.map((p) => `${p}=${git(['rev-parse', `HEAD:${p}`])}`);
  return crypto.createHash('sha256').update(ids.join('\n')).digest('hex').slice(0, 20);
}

async function githubApi(pathname) {
  const api = process.env.GITHUB_API_URL ?? 'https://api.github.com';
  const response = await fetch(`${api}${pathname}`, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN ?? ''}`,
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  if (!response.ok) throw new Error(`GitHub API ${response.status} for ${pathname}`);
  return response.json();
}

const warn = (message) => console.log(`::warning::${message}`);

/** Head SHA of the latest successful push run of this workflow on [branch]. */
async function lastGreenSha(repo, branch) {
  const workflowFile = path.posix.basename((process.env.GITHUB_WORKFLOW_REF ?? '').split('@')[0]);
  if (!workflowFile) return null;
  const query = new URLSearchParams({ branch, event: 'push', status: 'success', per_page: '1' });
  const data = await githubApi(`/repos/${repo}/actions/workflows/${workflowFile}/runs?${query}`);
  return data.workflow_runs?.[0]?.head_sha ?? null;
}

async function recordedPasses(repo, fingerprint, currentRef) {
  const caches = [];
  for (let page = 1; page <= 5; page++) {
    const query = new URLSearchParams({ key: markerKeyPrefix(fingerprint), per_page: '100', page: String(page) });
    const data = await githubApi(`/repos/${repo}/actions/caches?${query}`);
    caches.push(...(data.actions_caches ?? []));
    if ((data.actions_caches ?? []).length < 100) break;
  }
  return passedSuitesFromCaches(caches, fingerprint, currentRef);
}

/** Resolves the diff base for a CI diff plan; null means "unknown, run everything". */
async function resolveBase(plan, payload, repo, refName) {
  if (plan.diff === 'pr') {
    // actions/checkout checks out the PR merge commit: parent 1 is the base tip.
    const parents = lines(git(['rev-list', '--parents', '-n', '1', 'HEAD']).replace(/ /g, '\n'));
    if (parents.length === 3) return { base: 'HEAD^1', label: 'PR merge base (HEAD^1)' };
    const baseSha = payload.pull_request?.base?.sha;
    const mergeBase = baseSha ? git(['merge-base', baseSha, 'HEAD'], { allowFailure: true }) : null;
    return mergeBase ? { base: mergeBase, label: `merge-base with ${baseSha.slice(0, 8)}` } : null;
  }
  try {
    const green = await lastGreenSha(repo, refName);
    if (isAncestor(green)) return { base: green, label: `last green run ${green.slice(0, 8)}` };
    if (green) warn(`Last green commit ${green} is not an ancestor of HEAD; falling back to the push range`);
  } catch (error) {
    warn(`Could not look up the last green run: ${error.message}`);
  }
  if (isAncestor(payload.before)) return { base: payload.before, label: `push range from ${payload.before.slice(0, 8)}` };
  return null;
}

function renderSummary({ plan, baseLabel, fingerprint, config, selection, passed, toRun }) {
  const out = ['## E2E suite selection', '', `- Scope: ${plan.reason} (${plan.mode})`];
  if (baseLabel) out.push(`- Diff base: ${baseLabel}`);
  out.push(`- Source fingerprint: \`${fingerprint}\``, `- Pass markers: ${plan.useCache ? 'used' : 'ignored'}`, '');
  out.push('| Suite | Status |', '| --- | --- |');
  for (const suite of Object.keys(config.suites)) {
    let status = 'not affected';
    if (toRun.includes(suite)) status = '**run**';
    else if (selection.suites.includes(suite) && passed.has(suite)) status = 'already passed on this fingerprint';
    out.push(`| ${suite} | ${status} |`);
  }
  if (selection.reasons.length > 0) {
    out.push('', `<details><summary>${selection.reasons.length} changed file(s)</summary>`, '');
    out.push('| File | Suites | Rule |', '| --- | --- | --- |');
    for (const { file, suites, why } of selection.reasons.slice(0, 300)) {
      out.push(`| \`${file}\` | ${suites.length ? suites.join(', ') : '-'} | ${why} |`);
    }
    if (selection.reasons.length > 300) out.push(`| ... | ${selection.reasons.length - 300} more | |`);
    out.push('', '</details>');
  }
  return `${out.join('\n')}\n`;
}

async function runInCi(config) {
  const eventName = process.env.GITHUB_EVENT_NAME;
  const payload = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const refName = process.env.GITHUB_REF_NAME;
  const repo = process.env.GITHUB_REPOSITORY;
  const allSuites = Object.keys(config.suites);

  let plan = planFromEvent({ eventName, payload, refName });
  let baseLabel = null;
  let selection = { suites: allSuites, reasons: [] };
  if (plan.mode === 'diff') {
    const base = await resolveBase(plan, payload, repo, refName);
    if (base) {
      baseLabel = base.label;
      const { files, diffOf } = diffSource(base.base);
      selection = selectSuites(files, config, diffOf);
    } else {
      plan = { ...plan, mode: 'full', reason: `${plan.reason}; no usable diff base` };
    }
  }

  const fingerprint = sourceFingerprint();
  let passed = new Set();
  if (plan.useCache) {
    try {
      passed = await recordedPasses(repo, fingerprint, process.env.GITHUB_REF);
    } catch (error) {
      warn(`Could not read E2E pass markers: ${error.message}`);
    }
  }
  const toRun = selection.suites.filter((suite) => !passed.has(suite));

  const outputs = { run: String(toRun.length > 0), suites: toRun.join(','), fingerprint };
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(outputs).map(([k, v]) => `${k}=${v}\n`).join(''));
  }
  const summary = renderSummary({ plan, baseLabel, fingerprint, config, selection, passed, toRun });
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
  console.log(summary);
  console.log(`Selected suites: ${toRun.join(', ') || '(none)'}`);
}

function runLocally(config, base) {
  const { files: changed, diffOf } = diffSource(git(['merge-base', base, 'HEAD']), { workingTree: true });
  const untracked = lines(git(['ls-files', '--others', '--exclude-standard']));
  const files = [...new Set([...changed, ...untracked])].sort();
  const selection = selectSuites(files, config, diffOf);
  console.log(`Changes vs ${base} (incl. uncommitted): ${files.length} file(s)\n`);
  for (const { file, suites } of selection.reasons) {
    console.log(`  ${file}\n      -> ${suites.length ? suites.join(', ') : '(no E2E impact)'}`);
  }
  console.log(`\nSuites to run: ${selection.suites.join(', ') || '(none)'}`);
  for (const suite of selection.suites) {
    console.log(`  ${suite}: (cd cb_file_manager && ${config.suites[suite].command.join(' ')})`);
  }
}

const invokedDirectly = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) {
  const config = loadConfig();
  const base = process.argv[2];
  const localBase = () => base ?? git(['rev-parse', '--abbrev-ref', '@{upstream}'], { allowFailure: true }) ?? 'develop';
  const run = process.env.GITHUB_ACTIONS === 'true' && !base
    ? runInCi(config)
    : Promise.resolve().then(() => runLocally(config, localBase()));
  run.catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
