# Rust performance measurements

The README highlights CB File Hub's folder-scan workflow compared with TreeSize Free, including the scan technologies behind both applications. This document also retains the internal Rust-versus-Dart measurements. Both experiments were measured on 2026-10-22; their baselines and timing boundaries are described separately below. Neither experiment measures overall application performance.

## Rust versus Dart results

All times below are milliseconds. Speedup is **Dart median / Rust median**, calculated from unrounded microseconds.

| Task | Dart median | Rust median | Speedup | Dart min–max | Rust min–max |
|------|------------:|------------:|--------:|-------------:|-------------:|
| Disk Cleaner full scan | 84.629 | 28.320 | 2.988× | 81.934–90.377 | 26.200–37.472 |
| Recursive filename search | 587.248 | 44.372 | 13.235× | 574.618–629.953 | 42.441–60.252 |
| SHA-256, 256 MiB | 1,660.460 | 146.492 | 11.335× | 1,644.115–1,918.220 | 143.863–151.944 |

[Raw per-run results and environment](benchmarks/2026-10-22-windows-rust-verified.json) · [Benchmark source](../../cb_file_manager/tool/bench_rust.dart)

The internal table above uses the latest complete five-round run, from a fresh AOT build at source revision `5b425ca9e8fa50b934c0bfc9eb65c8e62651f5ed`. An [earlier run on the same date](benchmarks/2026-10-22-windows-rust.json) measured 2.864×, 13.429× and 13.479× respectively. Both reports are retained to show run-to-run variation; the published table is not assembled from the fastest samples across sessions. The benchmark source and native DLL SHA-256 match between these two reports.

## Machine and workload

- Intel Core i5-14600K, 14 cores / 20 logical processors, 63.7 GiB RAM.
- Samsung SSD 980 1TB NVMe; local `L:` volume, NTFS.
- Windows 11 Pro, build 26300; Flutter 3.47.2 / Dart 3.13.2.
- Dart AOT executable built with `dart build cli`, including the native code assets; Rust release library built by the project's hook with rustc 1.91.1, `opt-level=3`, thin LTO and one codegen unit.
- Scan/search corpus: 100,000 files, 128 bytes each (12,800,000 logical bytes), 1,110 subdirectories plus the root. Ten groups × ten branches × ten leaf directories, with 100 files in each leaf. This is a synthetic workload, not an entire drive or a representative mix of all user data.
- Every tenth file is named `Bổ_Não_<n>.txt`; the others are `document_<n>.bin`. The query `bo nao` tests case, accent and separator folding and produces exactly 10,000 matching paths.
- Hash input: 268,435,456 bytes (256 MiB), made by repeating a seeded 1 MiB byte block 256 times. Both engines read and hash the whole file.

## Measurement boundaries and correctness

Each task runs one untimed warm-up **per implementation**, followed by five measured runs per implementation. The order alternates Rust/Dart and Dart/Rust between rounds. Runs are sequential. The OS filesystem cache is warm; no cache flushing, cold-storage claim, saved scan tree, incremental refresh or cached digest is involved. Startup of the executable, compilation and fixture preparation are outside the timed intervals.

The measurements use production native APIs and the following baselines:

| Task | Rust path | Dart baseline | Timed boundary |
|------|-----------|---------------|----------------|
| Disk Cleaner | `spawnFullDiskScan(useNativeScanner: true)` | The same API with `useNativeScanner: false`, using its Win32 directory walker | Isolate startup through receipt of the completed tree, including tree processing and batched transfer. Progress and tree-preview streams are subscribed. |
| Filename search | `NativeSearch.start` / `collect`, default 25 ms polling | A traversal matching `FileNavigationBloc._recursiveSearch`, using the production `TextUtils.matchesSearch` | Start of traversal through collection of all paths; native result decoding included. |
| SHA-256 | `NativeHash.sha256File` | `package:crypto` SHA-256 over `File.openRead()`, as in the production fallback | File read through receipt of the digest, including native job notification. |

Disk scans use default depth 20, 1 MiB display threshold and at most 200 individually retained file rows per directory, with no junk rules. Small files are folded into summary rows by both implementations; **all 100,000 files are still counted**. Both produce 2,111 display nodes, the same folder tree, logical byte totals and file counts, and zero coverage issues. This does not measure arbitrary user cleanup rules, every file as an individual UI row, Flutter frame rendering, or interactive latency.

Parity checks run outside the timed interval: a sorted tree fingerprint (paths, sizes, file counts, folding and junk category), a sorted complete matching-path fingerprint, and the SHA-256 digest. The benchmark aborts on any mismatch or partial scan. Fingerprints include absolute corpus paths, so tree/search fingerprints vary with the checkout location; they compare engines within the same run.

These figures combine the effects of native compilation, worker threads, filesystem traversal and, for SHA-256, the CPU acceleration used by the Rust implementation. They do not isolate the programming language as the only cause. Hardware, storage, directory shape, cache state and build mode affect the results. Other Rust-backed features, including thumbnails, image editing, archives and document extraction, have no multiplier claimed here.

## Reproduce on Windows

Run from the repository root using PowerShell. `dart build cli` bundles the Rust library through the existing build hook. Rust must be installed; the benchmark rejects an unavailable native library instead of silently measuring Dart twice.

```powershell
cd cb_file_manager
dart build cli --target=tool/bench_rust.dart --output=build/benchmarks/cli
.\build\benchmarks\cli\bundle\bin\bench_rust.exe --prepare build\benchmarks\corpus build\benchmarks\hash-256m.bin
.\build\benchmarks\cli\bundle\bin\bench_rust.exe build\benchmarks\corpus build\benchmarks\hash-256m.bin build\benchmarks\results.json 5
```

Preparation creates 100,000 files and a 256 MiB file under the ignored `build/` directory. It requires new paths and refuses to overwrite existing inputs. On subsequent runs, skip `--prepare` and reuse the corpus. The tool prints per-run JSON and writes the full report after all comparisons pass. Keep the bundle's `lib/` directory alongside `bin/` when moving the executable. Record build mode, hardware, toolchain and source revision with any published report.

## Folder scan UI comparison with TreeSize Free

The production Cleaner screen completed this folder-scan workflow in **84.931 ms** median, versus **283.346 ms** for TreeSize Free: **3.336×**, rounded to **3.3×** in the README. This is a measured workflow ratio for this corpus, not a claim that Rust alone causes the difference or that every drive scans this much faster.

| UI workflow | Scan technology | Median | Min–max | Five measured samples, ms |
|-------------|-----------------|-------:|--------:|---------------------------|
| CB File Hub production Cleaner screen in benchmark launcher | Rust workers + Win32 directory enumeration | 84.931 ms | 75.036–86.242 ms | 86.086, 75.036, 86.242, 76.103, 84.931 |
| TreeSize Free 4.8.1.609 | NTFS MFT / two-thread traversal (documented capabilities; actual strategy not instrumented) | 283.346 ms | 272.992–297.996 ms | 297.996, 294.201, 283.346, 272.992, 279.378 |

[Raw samples, polling traces, environment and binary hashes](benchmarks/2026-10-22-windows-treesize-ui.json) · [CB result screenshot](benchmarks/2026-10-22-cb-cleaner-ui.png) · [TreeSize result screenshot](benchmarks/2026-10-22-treesize-ui.png)

### Workload and application setup

- The same machine and unchanged 100,000-file corpus described above; 12,800,000 logical bytes and 1,110 subdirectories. These 128-byte files are NTFS-resident: TreeSize reports zero allocated bytes. The comparison validates **logical size**, not allocated space, and does not exercise file payload reads.
- CB runs a Flutter **release** build of [the benchmark launcher](../../cb_file_manager/tool/bench_cleaner_ui.dart), using the actual `CbAgentCleanerScreen` inside a minimal `MaterialApp`. A service adapter supplies the corpus as the only selectable target and calls the production `spawnFullDiskScan(useNativeScanner: true)` for every rescan. There are no junk rules, saved scan results, incremental refreshes or simulated/E2E data. The launcher does not initialize the rest of the file-manager app.
- CB retains the same 2,111 display nodes as the native/Dart scan experiment. It counts all files while folding small-file rows. TreeSize maintains its own per-file metadata. Both produce the same folder inventory totals; this does not compare identical per-file UI data structures.
- TreeSize is the installed **4.8.1.609** executable, running as Administrator with its existing two-thread setting. CB runs without elevation; the entire corpus is readable by both. TreeSize displays logical **Size**, **Values in Byte**, the root expanded one level, and no treemap. Its result row confirms 100,000 files, 1,110 subdirectories, 12,800,000 bytes and zero exclusions.
- TreeSize documents [MFT and threaded traversal strategies](https://www.jam-software.com/treesize/features.shtml). Its default strategy was neither forced nor disabled; the actual internal MFT/traversal path was **not instrumented**. This is a comparison against TreeSize's observed default behavior on this folder, not a controlled comparison of scan algorithms.
- Both windows remain visible side by side, each 960 × 1,032 pixels, to avoid fully occluding a window and throttling its frame production. Process startup, building, initial folder selection and the first setup scan are excluded.

### Timing and validation

[The local Python/Win32 runner](../../cb_file_manager/tool/bench_scan_ui.py) performs one warm-up per application, then five measured full rescans in alternating application order, with 250 ms of settling time outside each timed interval. OS caches are warm. Compilation was finished before measurement. The Windows Computer Use connection was unavailable; Python/Win32 automation was used with the user's authorization.

Both intervals start immediately before the runner invokes the application's scan-again control through UI Automation. CB finishes when the runner observes a new completion marker written **after the production result frame has finished building**. TreeSize finishes when **Stop Scan** is observed disabled after it was observed enabled. The runner checks result totals after completion and aborts if it does not observe the expected scan transition or a new CB scan generation. These are application readiness signals, not GPU presentation timestamps or engine-only durations. Native UI signaling and CB's frame/file signaling have different overheads; they are recorded explicitly rather than mixing the earlier 28.3 ms CB engine timing with TreeSize's UI completion.

All timing uses local `perf_counter_ns()` around the operation, with 1 ms requested polling intervals. Actual observation intervals are retained in the JSON. The final busy-to-idle observation brackets were **4.14–6.06 ms** for TreeSize and **1.59–1.82 ms** for CB's completion marker. UI Automation calls and marker-file I/O are inside the measured intervals; screenshots and validation are outside them. The ratio is rounded to one decimal place to reflect these limits and the observed variation. CB's marker confirms full scans, zero coverage issues and the exact expected totals on every run.

This measures the scan and result-update workflow, including differences in traversal, retained data, native code and UI handling. It cannot establish a language-only advantage, whole-drive performance, cold-storage speed or performance on other file distributions. Search and SHA-256 multipliers in the preceding table are **against Dart**, not TreeSize.

### Reproduce the UI comparison

Prepare the corpus using the earlier commands, then run from `cb_file_manager/`:

```powershell
flutter build windows --release --target=tool/bench_cleaner_ui.dart
.\build\windows\x64\runner\Release\cb_file_hub.exe "$PWD\build\benchmarks\corpus" "$PWD\build\benchmarks\cb-completion.json"
```

In the CB window, perform the first scan. Open the same corpus in TreeSize, select **Size** and **Values in Byte**, keep **Home** visible, and verify the totals. Install `pywin32` and `comtypes` in your Python environment if needed. Find the PIDs of these specific windows with `Get-Process cb_file_hub,TreeSizeFree`, then run the driver from an elevated terminal so it can observe elevated TreeSize:

```powershell
# Replace these example PIDs with the two intended windows' process IDs.
$treePid = 12345
$cbPid = 23456
python tool\bench_scan_ui.py --treesize-pid $treePid --cb-pid $cbPid --completion build\benchmarks\cb-completion.json --output build\benchmarks\ui-comparison.json
```

The driver resizes both windows, invokes only scan controls, and requires a new output path. Keep the desktop available and avoid interacting with either app during the run. The launcher's window title is **CB Cleaner benchmark**, and its output must have a new generation for each scan. A later normal build without `--target=tool/bench_cleaner_ui.dart` restores the usual app entry point in the local build directory.

These are standalone performance measurements; they do not invoke the project's E2E runner.
