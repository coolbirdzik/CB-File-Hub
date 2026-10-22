"""Windows scan UI benchmark; run elevated after opening both benchmark windows.

Requires pywin32 and comtypes. Only invokes scan controls in the two specified
processes; never selects cleanup targets or invokes file operations.
"""
import argparse
import ctypes
from ctypes import wintypes
import json
import pathlib
import statistics
import time

import comtypes.client
import win32con
import win32gui
import win32process


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--treesize-pid', type=int, required=True)
    parser.add_argument('--cb-pid', type=int, required=True)
    parser.add_argument('--completion', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--rounds', type=int, default=5)
    args = parser.parse_args()
    if args.rounds < 3:
        parser.error('Use at least three measured rounds')
    if args.output.exists():
        parser.error('Output must be a new file')
    if not ctypes.windll.shell32.IsUserAnAdmin():
        parser.error('Run elevated to observe the elevated TreeSize window')

    comtypes.client.GetModule('UIAutomationCore.dll')
    from comtypes.gen import UIAutomationClient as automation_types
    automation = comtypes.client.CreateObject(automation_types.CUIAutomation)

    def window(pid, title):
        matches = []
        win32gui.EnumWindows(
            lambda h, _: matches.append(h) if (
                win32gui.IsWindowVisible(h)
                and win32process.GetWindowThreadProcessId(h)[1] == pid
                and win32gui.GetWindowText(h) == title
            ) else None,
            None,
        )
        if len(matches) != 1:
            raise RuntimeError(f'Expected one {title!r} window for PID {pid}')
        return automation.ElementFromHandle(matches[0])

    treesize = window(args.treesize_pid, 'TreeSize Free')
    cb = window(args.cb_pid, 'CB Cleaner benchmark')
    # Keep both visible: occlusion can throttle a window's frame production.
    work_area = wintypes.RECT()
    if not ctypes.windll.user32.SystemParametersInfoW(
            win32con.SPI_GETWORKAREA, 0, ctypes.byref(work_area), 0):
        raise RuntimeError('Could not read monitor work area')
    left, top, right, bottom = work_area.left, work_area.top, work_area.right, work_area.bottom
    width = (right - left) // 2
    for index, root in enumerate([treesize, cb]):
        handle = root.CurrentNativeWindowHandle
        win32gui.ShowWindow(handle, win32con.SW_RESTORE)
        win32gui.MoveWindow(handle, left + index * width, top, width, bottom - top, True)
    time.sleep(0.5)

    def named(root, name):
        condition = automation.CreatePropertyCondition(30005, name)
        matches = root.FindAll(4, condition)
        if matches.Length != 1:
            raise RuntimeError(f'Expected one control named {name!r}: {matches.Length}')
        return matches.GetElement(0)

    def invoke(element):
        element.GetCurrentPattern(10000).QueryInterface(
            automation_types.IUIAutomationInvokePattern
        ).Invoke()

    def marker():
        try:
            return json.loads(args.completion.read_text(encoding='utf8'))
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def tree_result():
        items = treesize.FindAll(
            4, automation.CreatePropertyCondition(30003, 50024)
        )
        for i in range(items.Length):
            name = items.GetElement(i).CurrentName or ''
            if 'Files: 100,000; Folders: 1,110;' in name:
                if 'Size: 12,800,000 Bytes;' not in name:
                    raise RuntimeError('Select logical Size and Values in Byte in TreeSize')
                return name
        raise RuntimeError('TreeSize totals differ from the 100,000-file corpus')

    def run_tree():
        refresh = named(treesize, 'Refresh')
        stop = named(treesize, 'Stop Scan')
        if stop.CurrentIsEnabled:
            raise RuntimeError('TreeSize is already scanning')
        tree_result()
        start = time.perf_counter_ns()
        invoke(refresh)
        invoke_ns = time.perf_counter_ns() - start
        trace = []
        busy_seen = False
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            before = time.perf_counter_ns() - start
            busy = bool(stop.CurrentIsEnabled)
            after = time.perf_counter_ns() - start
            trace.append([before, after, busy])
            busy_seen |= busy
            if busy_seen and not busy:
                elapsed = after
                break
            time.sleep(0.001)
        else:
            raise RuntimeError('TreeSize busy-to-idle transition was not observed')
        last_busy = next(row for row in reversed(trace) if row[2])
        return {
            'application': 'treesize_free',
            'elapsed_ns': elapsed,
            'invoke_ns': invoke_ns,
            'completion_observation_interval_ns': [last_busy[0], elapsed],
            'poll_trace': trace,
            'result': tree_result(),
        }

    def run_cb():
        refresh = named(cb, 'Scan again')
        previous = marker()
        if previous is None:
            raise RuntimeError('Complete the first CB scan before starting this runner')
        generation = previous['generation'] + 1
        start = time.perf_counter_ns()
        invoke(refresh)
        invoke_ns = time.perf_counter_ns() - start
        last_pending = invoke_ns
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            before = time.perf_counter_ns() - start
            result = marker()
            after = time.perf_counter_ns() - start
            if result and result['generation'] == generation:
                elapsed = after
                break
            last_pending = before
            time.sleep(0.001)
        else:
            raise RuntimeError('CB completion marker was not received')
        if (result['files'], result['bytes'], result['partial'],
                result['coverage_issues'], result['mode']) != (
                    100000, 12800000, False, 0, 'full'):
            raise RuntimeError(f'CB returned an incomplete or different inventory: {result}')
        named(cb, 'Scan again')
        return {
            'application': 'cb_cleaner_ui',
            'elapsed_ns': elapsed,
            'invoke_ns': invoke_ns,
            'completion_observation_interval_ns': [last_pending, elapsed],
            'result': result,
        }

    samples = []
    warmups = []
    for round_number in range(args.rounds + 1):
        order = [run_tree, run_cb] if round_number % 2 else [run_cb, run_tree]
        for run in order:
            sample = {'round': round_number, **run()}
            (samples if round_number else warmups).append(sample)
            print(json.dumps({k: v for k, v in sample.items() if k != 'poll_trace'}), flush=True)
            # Outside the timed region: allow the completed UI to settle.
            time.sleep(0.25)
    summaries = {}
    for name in ['cb_cleaner_ui', 'treesize_free']:
        values = [s['elapsed_ns'] for s in samples if s['application'] == name]
        summaries[name] = {
            'median_ns': statistics.median(values),
            'min_ns': min(values),
            'max_ns': max(values),
        }
    report = {
        'schema': 1,
        'date_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'rounds': args.rounds,
        'warmups_per_application': 1,
        'cache': 'warm OS cache; alternating application order; full rescans',
        'window_layout': {'width_each': width, 'height_each': bottom - top, 'both_visible': True},
        'start': 'immediately before UI Automation Invoke on the scan-again control',
        'cb_finish': 'completion file observed after the production Cleaner result frame built',
        'treesize_finish': 'Stop Scan observed disabled after it was observed enabled',
        'summaries': summaries,
        'treesize_over_cb': summaries['treesize_free']['median_ns'] / summaries['cb_cleaner_ui']['median_ns'],
        'warmups': warmups,
        'samples': samples,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf8')


if __name__ == '__main__':
    main()
