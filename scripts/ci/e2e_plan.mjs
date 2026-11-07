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
