// Execution planning is shared by local release and CI. Selection may retain
// both app and smoke for cache compatibility; execution never repeats smoke.
export function executionSuites(requested) {
  return [...new Set(requested)].filter(id => id !== 'smoke' || !requested.includes('app'));
}

export function suitePattern(ids) {
  return `^(?:${ids.map(id => id === 'smoke' ? 'app 01 Navigation' : `${id} `).join('|')})`;
}

export function coveredSuites(passed) {
  return passed.includes('app') ? [...new Set([...passed, 'smoke'])] : passed;
}

export function reportResults(content, ids) {
  const tests = new Map();
  let finished = false;
  let terminalSuccess = false;
  let fatal = false;
  let firstTestMs;
  for (const line of content.split(/\r?\n/)) {
    let event;
    try { event = JSON.parse(line); } catch { continue; }
    if (event.type === 'testStart') {
      const name = event.test.name;
      const suite = ids.find(id => name.startsWith(id === 'smoke' ? 'app 01 Navigation ' : `${id} `));
      tests.set(event.test.id, { suite, name, start: event.time, done: false });
      if (suite && !name.includes('(setUpAll)')) firstTestMs ??= event.time;
    }
    if (event.type === 'testDone') {
      const test = tests.get(event.testID);
      if (!test) continue;
      Object.assign(test, { done: true, result: event.result, hidden: event.hidden,
        skipped: event.skipped, milliseconds: event.time - test.start });
      if (!test.suite && ['error', 'failure'].includes(event.result)) fatal = true;
    }
    if (event.type === 'error') {
      const current = tests.get(event.testID);
      if (!current?.suite) fatal = true;
      if (current) current.error = true;
    }
    if (event.type === 'done') {
      finished = true;
      terminalSuccess = event.success === true;
    }
  }
  if (finished && !terminalSuccess && ![...tests.values()].some(test =>
    test.error || ['error', 'failure'].includes(test.result))) fatal = true;
  const results = ids.map(id => {
    const cases = [...tests.values()].filter(test => test.suite === id && !test.name.startsWith('loading '));
    const executed = cases.filter(test => test.done && !test.hidden && !test.skipped);
    const failed = cases.filter(test => !test.done || test.error || ['error', 'failure'].includes(test.result));
    const passed = executed.filter(test => test.result === 'success').length;
    return { id, ok: finished && !fatal && passed > 0 && failed.length === 0,
      passed, failed: failed.length, skipped: cases.filter(test => test.skipped).length,
      seconds: Math.round(cases.reduce((total, test) => total + (test.milliseconds ?? 0), 0) / 1000) };
  });
  return { results, firstTestMs: firstTestMs ?? null, finished, fatal };
}

const ANSI = /\u001b\[[0-9;]*m/g;
const BUILD_ERROR = /\berror (?:C|LNK|MSB|CMake)\w*|CMake Error|Build process failed|: error:/i;
const ERROR_LINE = /\berror\b|exception|\bfailed\b|timed? ?out|unhandled|assert|\[AX-(?:CHURN|ORPHAN)\]/i;
const clip = (text, max = 300) => text.length > max ? `${text.slice(0, max)}…` : text;

// Failure-only view of a run: errors of failing/unfinished tests, compiler
// errors, nothing else. The full output stays in build/e2e-logs and in the
// uploaded diagnostics artifact; compiler warnings and passing-test chatter
// only bury the one line that explains the failure.
export function failureDigest(content, output = '', { maxPrints = 30, tail = 15, maxStack = 30 } = {}) {
  const tests = new Map();
  for (const line of content.split(/\r?\n/)) {
    let event;
    try { event = JSON.parse(line); } catch { continue; }
    if (event.type === 'testStart') {
      tests.set(event.test.id, { name: event.test.name, done: false, prints: [], errors: [] });
    }
    const test = tests.get(event.testID);
    if (!test) continue;
    if (event.type === 'print') test.prints.push(String(event.message).replace(ANSI, '').trim());
    if (event.type === 'error') test.errors.push(event);
    if (event.type === 'testDone') Object.assign(test, { done: true, result: event.result });
  }

  const sections = [];
  for (const test of tests.values()) {
    const failed = test.errors.length > 0 || ['error', 'failure'].includes(test.result);
    if (!failed && test.done) continue;
    const out = [`✖ ${test.name}${test.done ? '' : '  (never finished — hung or killed)'}`];
    for (const item of test.errors) {
      out.push(clip(String(item.error), 2000));
      out.push(...String(item.stackTrace ?? '').split(/\r?\n/).filter(Boolean).slice(0, maxStack).map(l => `    ${l}`));
    }
    const lastLines = test.prints.filter(Boolean).slice(-tail);
    const prints = test.prints.filter(line => line && ERROR_LINE.test(line) && !lastLines.includes(line)).slice(-maxPrints);
    out.push(...prints.map(line => `  ! ${clip(line)}`));
    // A timed-out test is "done" with an error whose stack points at the timer,
    // not at what stalled; the last output names the stalled step.
    if (lastLines.length) {
      out.push(test.done ? '  last output:' : '  last output before it stopped:',
        ...lastLines.map(line => `    ${clip(line)}`));
    }
    sections.push(out.join('\n'));
  }

  const buildErrors = [...new Set(output.replace(ANSI, '').split(/\r?\n/)
    .filter(line => BUILD_ERROR.test(line) && !line.startsWith('{') && !/\bwarning\b/i.test(line))
    .map(line => clip(line.trim())))].slice(0, 20);
  if (buildErrors.length) sections.push(['✖ build errors', ...buildErrors.map(l => `  ${l}`)].join('\n'));

  if (!sections.length) {
    const rest = output.replace(ANSI, '').split(/\r?\n/)
      .filter(line => line.trim() && !line.startsWith('{') && !/\bwarning\b/i.test(line));
    sections.push(['✖ no structured error found; last output:', ...rest.slice(-40).map(l => `  ${clip(l)}`)].join('\n'));
  }
  return sections.join('\n\n');
}
