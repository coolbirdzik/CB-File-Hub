# Torrent library

Open **Torrent / Torrents** in the sidebar (`#torrents`). The library indexes
`.torrent` files by the SHA-1 of their original v1 `info` dictionary. Different
paths and tracker lists for the same torrent share one library entry. Vietnamese
and English are supported.

## Windows default app and magnet links

In **Torrent → Settings → Choose Windows defaults**, select **CB File Hub**
for `.torrent` and `MAGNET`. The app registers both choices for portable builds
when first launched. EXE/MSI installers advertise the handlers at installation;
MSIX declares the file type and protocol in its manifest. Existing Windows
defaults remain selected until the user changes them in Default apps.

Opening a `.torrent` or `magnet:` link launches the Torrent tab and shows a
dialog with the payload destination and a **Start downloading immediately**
checkbox. The folder can be typed or chosen with Browse; the last confirmed
folder and immediate-start choice are remembered. Unchecking the box adds a
paused task, which stays paused after restart until resumed. Cancelling starts no download. The same dialog is
used when opening an indexed torrent or choosing **Download to…**.

In **Torrent → Settings → When opening torrents**, **Show download options when
opening a torrent** is enabled by default. Turn it off to use the saved payload
folder and immediate-start preference for file/magnet/URL imports and library-row
opens. The same settings section lets users type/save or browse for that folder
and choose immediate start. With no valid saved/suggested absolute folder, the
app still opens the chooser once; saving it enables subsequent opens without
that chooser. Existing active/waiting/paused/completed tasks retain their state.
The explicit **Download to…** command always opens options, and duplicate-merge
and source-cleanup confirmations remain required. These preferences survive
restart (`torrent.showDownloadDialog`, `torrent.lastDownloadDirectory`,
`torrent.startImmediately`).

Opening a local `.torrent` from the file browser (including its shared Open
action) routes directly to the queued Torrent dialog inside CB File Hub. It does
not depend on the Windows default application. Selecting one file in **Import
→ Import .torrent** uses this same destination/start dialog; multiple-file
selection remains a bulk library import. Individual imports notify open library
tabs after the index commit. The unfiltered newest-first view returns to its
first page immediately so the new row is visible without F5; explicit searches
and filters are retained.

If an app window is already running, the request is sent to it (preferring the
download engine owner). Existing active/queued/paused tasks reuse their recorded
destination and the checkbox controls pause/resume without creating another task.
Paused tasks allow a new destination; confirming replaces the paused task while
retaining files at the old location. Active/queued tasks keep their destination
locked until paused or stopped. Completed entries default to unchecked.
Transient activation links are not replayed by workspace restore.

Opening a Windows magnet or `.torrent` association reuses an existing Torrent
tab (preferring the active one) and focuses it. A tab is created only if none is
open. Requests are queued per tab, including repeated links and startup batches;
each destination/merge dialog finishes before the next request is handled.

Opening a `.torrent` from the OS temporary directory (for example, a browser's
private-session download) captures its validated metainfo before waiting for a
merge dialog. It keeps a durable copy in the chosen torrent library, or in the
app's `torrent/opened-torrents` folder in Index mode. The browser-managed original
is retained even in Move mode, so read-only sources need no delete permission and
browser cleanup does not break subsequent downloads. Normal folder scans and
imports continue to use the selected index/copy/move mode.

The **Add torrent from link** button accepts HTTP/HTTPS metainfo URLs (including
redirects and URLs without a `.torrent` extension) and v1/hybrid `urn:btih` magnet
links, including base32 hashes. HTTP fetches have timeouts, a five-redirect limit
and a 16 MiB metainfo limit. The downloaded bytes are validated before a hash-named
metainfo file is saved; HTML/error responses are rejected in the editable dialog.
Payload destination and immediate-start choices are shown after adding the link.
Magnets are indexed offline by info-hash; peers are contacted only after the user
confirms immediate start or resumes the paused task. The original URI is persisted,
and aria2 metadata tasks are followed to their payload GIDs so pause/resume/stop act
on the actual download. Metainfo downloads alone never start payload transfers.

**Import** is a toolbar dropdown with `.torrent` file selection and client
imports. qBittorrent keeps its dedicated backup/recovery and confirmed cleanup
flow. µTorrent and BitTorrent (Windows), Transmission and Deluge offer profile
discovery plus manual folder selection for portable/custom installations. These
additional clients import saved `.torrent` files using the current index/copy/move
mode and register the chosen folder as a scan source; their resume databases and
running download state are not migrated. Downloaded content is kept.
Transmission paths follow its [configuration documentation](https://github.com/transmission/transmission/blob/main/docs/Configuration-Files.md),
including `TRANSMISSION_HOME`; Deluge uses the configuration `state` folder
described in its [FAQ](https://deluge-torrent.org/faq/#WheredoesDelugestoreitssettingsconfig).
Refresh also discovers these client folders again.

Opening **Add torrent from link** reads the clipboard once and prefills a valid
supported magnet. Other text/URLs are ignored, a delayed response does not replace
user input, and nothing is imported or downloaded until the user confirms.

The context menu offers **Copy magnet link** for both metainfo files and magnet
entries. Local/HTTP-imported metainfo exports its indexed v1 hash, encoded display
name and available trackers; an existing matching magnet keeps its parameters.
Multiple selection copies one magnet per line. Opening/importing a torrent or
link refreshes the current library page without replacing search/filter state
with a search for that torrent alone.

Interactive file/link imports detect an existing v1 info hash before changing
metadata or moving a source, then ask whether to merge. Merging unions trackers
and source links while preserving the existing task, destination, counters and
meaningful display name. Declining does not import, move or start a download.
Explicit magnet imports/merges update the modified time so retained old entries
can appear among recent items; unattended source scans keep their fast skip rules.
A saved-entry notice offers **Show in list**, which clears filters only when
clicked and selects the entry on its page in the full library, without a
single-hash filter. Original source links are retained in the index and Details.

## Storage and organization

The settings button offers three modes:

- **Index only** (default): metainfo stays in its original location.
- **Copy**: validated metainfo is copied to a user-selected folder.
- **Move**: metainfo is copied and verified, then its original is removed after
  the index transaction succeeds. This also applies to automatic imports; use
  index/copy mode for folders managed by another torrent client.

Copy/move destinations are `<chosen folder>/<first two hash characters>/<hash>.torrent`.
This avoids name collisions and huge flat directories. Copy organizes already
indexed metainfo too, including paths outside the configured scan folders.
Switching to Move shows a confirmation with the count and a lazy list of exact
source/destination paths, including originals retained by a previous Copy policy.
Cancelling keeps the previous mode and source files. Confirming verifies the
stored metainfo and durable index before deleting only the approved originals;
downloaded content, companion files and source directories remain in place.
Files changed or removed from the index after preview are skipped with an error,
and sources added later are outside that cleanup. Changing the destination in
Move mode or retrying **Organize torrent files** requires the same confirmation.
New imports continue to follow the selected storage policy; F5 remains add-only.
Progress, cancellation and scan errors remain visible.
Users can edit a group for each entry and search by name,
group, or full info-hash. Content categories are derived from file extensions.

The central index uses `torrents` and `torrent_sources` tables in the existing
`CBFileHub_v2/cb_file_hub.sqlite` app database. It retains source paths, fingerprints,
download destination, task state and progress. Removing an entry stops its task
and removes index rows while retaining metainfo and downloaded files. A later
scan can import that torrent again.

## Import and large libraries

### Import from qBittorrent on Windows

The Torrent toolbar has **Import from qBittorrent**. It discovers
`%LOCALAPPDATA%/qBittorrent/BT_backup` and `%APPDATA%/qBittorrent/BT_backup`, or lets
the user choose a portable profile. The source list is built lazily. Users choose
where the imported metainfo is stored; this action always makes a verified copy,
including when the library's normal storage mode is Move. It never starts payload
downloads and does not need Web UI or credentials.

**Remove torrents from qBittorrent after import** is off by default. Enabling it
requires a separate confirmation showing the exact `.torrent` and `.fastresume`
paths. qBittorrent must be fully closed; Windows process inventory is checked
before cleanup and again before committing each file group. Only approved,
unchanged files are removed after the chosen archive and durable index are
verified. Files are temporarily staged and restored if validation fails.
Downloaded content, unrelated files and source directories remain in place.

Resume-only entries first reuse existing metainfo, including alternate indexed
source paths when the canonical archive is missing. Otherwise the importer reads
the resume's v1 info hash, name, tracker tiers, category, saved payload directory
and original added time. Embedded `info` is recovered without changing its bytes;
entries without `info` are indexed as offline magnets. Those entries obtain
metadata only when the user explicitly downloads. Import never treats qBit's
piece flags or cumulative traffic as verified aria2 progress or live seed counts.

Every `.fastresume` is copied byte-for-byte under
`<chosen folder>/<hash prefix>/<hash>.qbit/<source-path digest>.fastresume`;
different source profiles retain separate backups. The index records the primary
resume backup and its SHA-256. Resume reads are capped at 64 MiB and processed
off the UI isolate. Cleanup additionally verifies every resume backup against the
approved source digest, including when a valid `.torrent` is also available.
Invalid/mismatched resume-only entries and corrupt metainfo are reported with
their sources retained. Profiles containing `torrents.db` are blocked
from file cleanup because deleting legacy backups would not remove SQLite rows.
The dialog supports cancellation, result counts and a complete error log at
`<application support>/torrent/qbittorrent-import.log`. F5 remains add-only.

### Source scans

Import multiple files, scan a selected folder, or scan all mounted local drives.
Automatic import scans configured sources at startup and every five minutes.
Initial sources include Downloads and existing common qBittorrent, uTorrent,
BitTorrent or Transmission metainfo folders. Users can add/remove source folders
and disable automatic import. Full-drive scans are explicitly started from the
screen; network/optical drives and symbolic links are not traversed.

Scanning loads compact source fingerprints in batches of 512 and uses in-memory
path/filename lookups, avoiding per-file database queries for known sources.
Unchanged files and same-filename sources in other folders skip metainfo parsing
when their indexed archive is still available. A changed known source, old metadata
or missing archive is re-imported. Name matching never authorizes source deletion:
move still verifies the content and durable index before removing an original.
Already organized, unchanged archives skip parsing in move mode too.
New files are processed in one worker isolate per file, including copy verification.
Scanning caps metainfo at 16 MiB, merges overlapping scan roots and
supports cancellation. Progress includes imported/duplicate/error counts. All
errors, including unreadable folders and invalid torrents, are written to
`<application support>/torrent/last-scan.log`; the UI keeps a bounded error sample.
Permission failures do not stop the remaining scan. Storage folders can also be
scanned; content identity makes archive re-import idempotent and supports recovery.

The tab uses `BrowserLikeFileSurface` and `FileListViewBuilder` directly, including
the browser's `FileItem`, `FileGridItem` and `FileDetailsItem`. List, Tiles, Grid,
Details, Tree and desktop Columns therefore use the same layout, file icons,
selection behavior, keyboard navigation, grid sizing and preview as file browsing.
Details includes the normal 24px file icon, configurable columns, sortable headers
and the column settings button. Column visibility and preview are remembered.
File tags follow the browser preference and are loaded for the current page.
Friendly indexed names are displayed even when the stored filename is a hash;
physical file commands still use the real metainfo path. Size is indexed payload
size and dates come from the index, so rendering does not stat the entire library.

Ctrl+F opens/focuses search; Escape clears and closes it. Ctrl+scroll steps through
view density, and Grid has the shared size control. The initial sort is **Modified
date, newest first** across the whole index, including upgrades from the old
torrent-specific sort preference. Further explicit sort choices are remembered.
The view and grid size initially use the browser defaults and are saved separately.

Name, size, content category and date sorting apply to the entire index before
pagination, with stable info-hash tie breaking. Modified date is the imported
metainfo's source timestamp; created date is when the entry joined the index.
Magnets use the index timestamp until metainfo is imported. Literal search uses
the shared Unicode/accent folding, separator and word-order rules across name,
group and hash. Regex searches each original field independently, preserving
anchors and regex syntax; it scans bounded batches and discards cancelled queries.

Each view builds visible items lazily and queries 80 records per page with SQL
search/filtering. Only one page and bounded regex batches are kept in memory.
The normal file context menu is extended with download, pause/resume, stop,
open destination, group, torrent properties and removal actions as applicable.
Selected tasks show live status/progress above the file view. Removing from the
index keeps files; ordinary file menu operations continue to address the physical
file. Magnets use virtual entries: native file menus, clipboard file operations
and file drags never receive their virtual paths. Paste is disabled in the index,
which combines files from multiple folders rather than providing a destination.
Pending download restoration uses batches of 64 with a hash cursor, independently
of the visible page.

F5 and the Refresh button only add new `.torrent` filenames from source folders,
then reload the index once. Each refresh rediscovers existing standard client
folders (including qBittorrent's `BT_backup`) and scans them together with the
configured sources, even when periodic auto-import is disabled. The storage
archive is not added as a scan source automatically. Discovery is repeated so a
client folder created after the initial app setup is still found. A running scan
is awaited; repeated refresh requests share one import. Known names are read in
compact database pages of 2048 and skipped before any per-file stat, existence
check or metainfo read, including in move mode. Names imported earlier in the same
pass are skipped too. Each source uses a native recursive directory stream, with
no links followed and without a separate Dart listing per subfolder. Only new
files follow the selected index/copy/move policy.
F5 does not organize existing files, repair archives, backfill metadata or wait
for the download engine; explicit scans and organization handle maintenance.
Download status continues to update on its normal timer. Scan progress does not
re-query the visible library page repeatedly. Scanning never starts a download.
The existing progress, cancellation and error log remain available.

Refresh checks the index migration once per schema version. A service retained by hot
reload can therefore import against a newer schema; an unset discovery callback
falls back to standard source discovery rather than invoking a null function.
Torrent icons come from Windows' current file association through the shared file
icon helper, including virtual magnet entries. List, Details and Grid icon sizes
are warmed per extension with concurrent requests coalesced. Explicit refresh
invalidates the `.torrent` icon cache to pick up association changes.

The standard file-browser bar stays at the top, reusing its navigation/search
bar and shared view/sort/column/preview/refresh controls. A separate torrent
command row sits directly below it with import, folder/system scans, magnet,
filters and settings. This row scrolls horizontally at narrow widths and never
wraps. Status and content category filters share a popup. Ctrl+F opens the shared
search bar above the torrent commands.

The pagination footer lets users choose 20, 50, 80 (default), 100, 200, 500 or
1,000 files per page. The choice is remembered across restarts. Changing it
returns to the first page and clears selection while retaining search, filters
and sort. Queries stay bounded and the file views remain lazy.

## Downloading

Details retains the shared file icons, selection and file columns, and adds
configurable download status, progress, download/upload speed, seeds, peers,
time remaining, downloaded/uploaded bytes, share ratio, file count, group,
download folder and info hash. Status, progress, download speed, seeds and peers
are visible initially. The common Column settings dialog and header context menu
both persist the same per-Torrent visibility choices. Header and lazy rows scroll
horizontally together when the columns exceed the available width.

The engine's existing two-second status poll updates these values. Seeds count
connected seeders; peers count all connected peers/servers (including seeders
and web seeds), rather than tracker-wide swarm totals. Unavailable measurements
show an em dash, including torrents only imported into the library. Pausing,
stopping or finishing clears live speeds and connection counts. ETA is a current
speed estimate; uploaded bytes and ratio use aria2's reported task counters.
The index migration preserves existing torrents and leaves unknown counters null.

There are 28 torrent-specific columns. Additional metainfo columns show the first
tracker and tracker count, torrent creation date, creator, comment, privacy,
piece size/count, metainfo file size, metainfo file path, source, error and task ID;
Remaining shows payload bytes still needed. Metadata is parsed from original
metainfo bytes and persisted in the index. First refresh after upgrading backfills
these fields even for unchanged source files, in the same bounded scan. Existing
task counters, state and group are retained. Later refreshes skip unchanged files.

**Download to…** chooses a payload destination independently for every torrent.
Pause, resume, stop, retry and open-download-folder actions are available. The
app restores active/queued/paused task intent after restart and aria2 uses its
`.aria2` control files plus integrity checking to reuse verified payload pieces.
Pause or stop before selecting a different destination. Importing never starts a download
or contacts trackers by itself. Seeding stops at completion (`seed-time=0`).

Windows bundles the official aria2 1.37.0 x64 runtime as a separate subprocess.
Its RPC endpoint binds loopback with a random secret; a file lock prevents two
app windows from launching competing download engines for the same index.
The process stops with its parent and also uses the Windows Job Object reaper.
Manage downloads from the owning window if another window reports ownership.

Windows builds fetch the SHA-256-pinned runtime with `just fetch-aria2`; this is
also wired into `just windows`, `scripts/build.sh` and Windows build/test CI.
For direct `flutter build windows`, fetch **both** llama and aria2 runtimes first.
The bundle includes upstream licences and a corresponding-source link.

Linux/macOS users install aria2 or select an executable in Torrent settings.
Downloading on mobile is not implemented; indexing accessible filesystem folders
is available. Pure BitTorrent v2 metainfo is rejected with an explicit error;
v1 and hybrid metainfo are supported. qBittorrent's saved payload directory is
retained as a download-dialog suggestion; its live session state is not resumed.
OS storage permissions still
govern which folders can be scanned.

## Validation

Run from `cb_file_manager`:

```sh
flutter test test/services/torrent
flutter test test/ui/screens/torrent_screen_test.dart
flutter test test/ui/tab_manager/torrent_tab_reuse_test.dart
flutter analyze
```

Unit tests use generated metainfo, temporary folders, an in-memory SQLite index
and a fake download engine. They cover original-byte identity, unsafe paths,
deduplication, 5,000-row pagination/filtering, storage modes, cancellation, corrupt
archives, restart intent, action/status races and retaining files on index removal.
They do not download from public swarms. E2E requires explicit authorization.

The Windows Torrent E2E suite runs the real app, SQLite index, window IPC and
bundled aria2 subprocess. It covers file/magnet opening, destination and start
choices, focus/tab reuse, duplicate merging, clipboard links, F5 imports,
pagination, shared views/search/sort, storage-mode confirmation and qBittorrent
backup recovery. Download verification uses generated private metainfo and a
loopback HTTP web seed, then checks the downloaded bytes. Peer discovery is
disabled for this test engine. App data and client backup fixtures use temporary
directories; the suite never imports the user's actual client backup.

After authorizing E2E execution, run from the repository root:

```sh
just e2e-file torrent_library_e2e_test
# Included in the parallel runner and Windows CI as well:
just e2e-parallel "Torrent Library"
```

The parallel runner waits for its other workers before running Torrent's native
focus checks, so another test window cannot steal focus during the assertions.

All full-app E2E suites isolate app storage and unmount the app before resetting
services. E2E windows do not prewarm spare app processes or join the production
window registry. The Torrent IPC tests opt into their own loopback registry.
