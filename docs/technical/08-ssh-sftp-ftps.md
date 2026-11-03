# SSH workspace, SFTP and FTPS

The sidebar's **SSH workspace** opens `#ssh`. Network Home also links to it.
`#sftp` uses the same saved SSH hosts, with shortcuts to browse files or open a
terminal in another application tab. Host profiles support names, groups,
host/port, username, password or a managed SSH key.

Hosts and desktop network List mode use the file browser's `AdaptiveFileList`
column layout and shared compact row geometry. A desktop host click selects;
double-click or Enter opens SSH (or browses files in SFTP). The host menu keeps
terminal, file browsing, edit and delete actions available; its address is shown
in a tooltip. Discovered config aliases remain in the connection form only.

SSH/SFTP host collections offer only Grid and List, with a visible toggle beside
search and Grid as the fallback. `GridListCollection<T>`, `GridListViewToggle`
and `GridListViewController` are common components built on the existing browser
collection. The scoped SQLite preference `collection_view_ssh_hosts` persists
the choice without changing file-browser preferences. Both views keep the same
selection and host actions. A fixed management toolbar prevents selection from
moving the double-click target; Grid also shows address and authentication.

## SSH and SFTP

`dartssh2` supplies SSH and SFTP; the vendored `xterm` 4.0.0+cb.1 renders
interactive PTY sessions. The patch in `third_party/xterm/PATCHES.md` binds
text input to `View.of(context).viewId` for Flutter 3.47.2. Upstream 4.0.0
omits it, causing Windows to reject keyboard attachment with "view ID is null"
and then "no client is set". Restart the running app after switching to the
patched dependency. The patch preserves IME input and is not a keyboard-only
fallback.
Terminal tabs resize the remote PTY, retain their session while switching desktop
tabs, and close the transport when their tab is closed or navigates elsewhere.
Reconnect, disconnect, clear, Home and SSH workspace controls remain available.

`SshProfileStore` keeps profiles, passwords, private keys and trusted fingerprints
in `FlutterSecureStorage`. SSH secrets are not stored in `network_credentials`.
Keys can be generated as Ed25519 or imported as OpenSSH/PEM, including encrypted
keys. Import unlocks the key with its passphrase and stores it in the OS vault;
the passphrase is not retained. Public keys can be copied for installation on a
server. Referenced keys cannot be deleted until their hosts are updated.

### Local SSH discovery and connection forms

SSH/SFTP connection dialogs and the SSH workspace scan the current user's
`~/.ssh` automatically (`%USERPROFILE%\.ssh` on Windows). The Hosts list shows
only saved profiles. Discovered hosts are available in the connection dialog's
SSH config selector; selecting one fills HostName, User, Port and an
available IdentityFile. A sole host, or an explicitly supplied matching host,
is filled automatically in a new untouched form. Asynchronous discovery does
not overwrite manual edits or existing saved profiles.

The config reader supports quoted paths, explicit aliases, Host wildcard and
negation defaults, first-value precedence, additive IdentityFile entries,
bounded/cycle-checked Include globs and common identity path tokens. It never
executes config commands. Conditional Match settings are skipped with a notice;
hosts requiring ProxyJump, ProxyCommand or SSH certificates display a notice
because the current connector does not implement those options.

Private-key candidates are recognized by their OpenSSH/PEM headers, including
custom filenames and IdentityFile paths outside `.ssh`. Public keys, known_hosts
and PuTTY `.ppk` files are not imported as private keys. Discovery reads only
headers; choosing a key opens the import dialog with its file preselected.
Encrypted keys ask for a passphrase. Re-importing an existing fingerprint reuses
its vault identity. The original files and SSH config are never modified.

Connection forms use the shared desktop dialog with responsive field rows and
scrolling content. Import private key and Generate Ed25519 key are directly
available beside authentication, and importing/generating selects the resulting
key immediately. The workspace Keys section also lists local files and provides
Copy public key for installing generated keys on servers.

Unknown and changed server fingerprints require an explicit trust decision.
Background connections without an interactive trust callback reject untrusted
keys. Trust is scoped to hostname and port and can be removed from the workspace.

SFTP connections have separate transports per account/host/port. Virtual paths
encode the connection authority and preserve remote file names literally. The
provider supports listing, streaming, download/upload, mkdir, rename and delete.
Directory deletion is non-recursive, so non-empty directories produce a server
error rather than silently deleting their contents.

### Two-pane SFTP file transfer

`#ssh/transfer` (or `#ssh/transfer/<profileId>`, which connects at once) is a
WinSCP-style screen in `ui/screens/ssh/sftp_transfer_screen.dart`. This
computer is always the left pane and the chosen SSH host the right one; below
720 px the local pane stacks on top. Open it from **SSH → Hosts → File
transfer**, a host's menu (in place or in a new tab), or the terminal toolbar.
Choosing another host in the right pane's selector reconnects in place without
changing the tab path, so the cached tab content and its session survive.

The screen owns its own `SSHClient`/`SftpClient` through `SshConnector` (same
keys, proxies and fingerprint prompt as the terminal) and closes it when the
tab closes or navigates away. It does not register in `NetworkServiceRegistry`.
A closed transport shows a reconnect action and cancels a running transfer.

Each pane has Up, Refresh, New folder and an editable path field; on Windows
the level above a drive root lists the drives. Rows support click, Ctrl/Shift
selection, arrow keys, Ctrl+A, Enter, Backspace, F5 and Escape. Double-clicking
a folder opens it; double-clicking a file sends it to the other pane. Selected
items go across with the pane's Upload/Download button, Enter, or by dragging
them onto the other pane.

`services/ssh/sftp_transfer.dart` performs transfers over a small
`TransferFileSystem` interface (local and SFTP implementations):

- Folders copy recursively and merge into existing folders. When top-level
  names already exist, one Replace/Skip/Cancel question covers the batch,
  including files inside merged folders. A file where a folder goes (or the
  reverse) is reported, never replaced, and its contents are not attempted.
- Links are listed but never followed, so junctions such as
  `Application Data` cannot loop. A selected linked folder is reported; linked
  files copy their target.
- Downloads to Windows reject names with `<>:"/\|?*`, control characters,
  trailing dots or spaces, and device names (`CON`, `NUL`, `COM1`…), per item.
  Names differing only by case (`README.md`, `Readme.md`) keep the first and
  report the rest instead of silently overwriting it.
- On Android the local pane starts on the first shared storage location.
- Progress is aggregated in bytes across the batch and throttled to 100 ms.
  Cancel stops between chunks and deletes the partly written file. The
  destination pane refreshes afterwards; failures are listed in a dialog.
- There is no delete action: SFTP folder deletion stays non-recursive, and a
  local delete here would bypass the Recycle Bin.

Tests: `test/services/ssh/sftp_transfer_test.dart` (recursive copy, progress,
links, Windows names and case, conflicts, cancel, drive list) and
`test/ui/screens/network_browsing/sftp_transfer_screen_test.dart` (pane order
at 320/1200 px in English and Vietnamese, upload, folder navigation, download).
The opt-in loopback suite also round-trips a tree through a real SFTP server
and cancels a 4 MiB upload, checking that no partial file remains. Close the
`SftpClient` before its `SSHClient`; the reverse order aborts the socket.

## Port forwarding

**SSH → Port forwarding** (`#ssh/forwards`) lists saved rules; **Add forward** (also in each
host's menu, with that host preselected) creates one:

| Type | Like | Listens on | Connections go to |
| --- | --- | --- | --- |
| Local | `ssh -L` | this computer | destination as the SSH server resolves it |
| Remote | `ssh -R` | the SSH server | destination as this computer resolves it |
| Dynamic | `ssh -D` | this computer (SOCKS5, no auth, CONNECT) | any address, through the server |

Rules (`SshForward`, `services/ssh/ssh_forward.dart`) are stored in the same
vault document as hosts under `forwards`, with the same snapshot/rollback.
Deleting a host deletes its rules. Ports must be 1–65535 and the listen
address defaults to `127.0.0.1`; any non-loopback address shows a warning in
the dialog, because other devices could then use the tunnel (for SOCKS, an
open proxy).

`SshTunnelManager` (`services/ssh/ssh_tunnel_manager.dart`) runs tunnels
app-wide, so they keep running while tabs change, and stops any whose rule or
host disappears from the store. Each tunnel has its own SSH connection through
`SshConnector` (keys, proxies and the fingerprint prompt as for the terminal).
Rows show Stopped / Starting / Running with the open connection count (not for
SOCKS), or the failure: server refused the remote listen, transport
disconnected, or the connect error. A connection whose destination cannot be
reached is dropped and reported on the row while the tunnel keeps listening.
Running rules can be stopped but not edited or deleted; Stop also aborts a
tunnel that is still authenticating.

Each forwarded connection copies both directions with backpressure and
half-closes the other side when one finishes sending. Shutdown closes the
listener, then live connections, then the client. The remote listener is
cancelled with `cancelForwardRemote` directly, since
`SSHRemoteForward.close()` leaves a cancel request that fails once the client
closes.

dartssh2 matches incoming `-R` channels to the requested listen address by
exact string (`SSHClient._findRemoteForward`), so the server must report back
the address the rule requested. RFC 4254 requires that, and asyncssh does it
in the loopback test; other servers were not tested. The exposure warning is
not shown for remote rules, whose reach is decided by the server's
`GatewayPorts`.

Not implemented: auto-start at launch, automatic reconnect (start the rule
again after a failure), Unix-socket forwards and X11. On Android the system
stops tunnels when the app goes to the background.

Tests: `test/services/ssh/ssh_tunnel_manager_test.dart` uses a fake link over
real loopback TCP (local and remote echo, half-close, refused destinations and
listens, dropped transport, stop during connect, host deletion, vault
round-trip). `test/ui/screens/network_browsing/ssh_forward_section_test.dart`
covers the section at 320/1200 px in English and Vietnamese and the dialog.
The opt-in loopback suite drives -L, -R and a hand-written SOCKS5 handshake
through asyncssh, whose test server allows `direct-tcpip` and `tcpip-forward`.

## SSH proxies

Use **SSH → Proxies → Add proxy**, then choose that proxy in the host editor.
Proxies can be edited and shared by several hosts. A referenced proxy cannot be
deleted until its hosts select another route. Endpoints and proxy credentials
are stored in the same OS credential vault as SSH profiles; older saved profiles
continue to connect directly.

Supported upstream protocols are HTTP CONNECT (optional Basic authentication),
SOCKS5 (anonymous or username/password), and SOCKS4a (optional user ID). Both the
terminal and SFTP use the shared connector and saved `proxyId`. Hostname targets
are sent to the proxy for DNS resolution. Handshakes have bounded responses and
timeouts; failure closes the socket and never retries a direct connection. SSH
server fingerprint verification still applies to the final destination. SSH
jump hosts/host chains, HTTPS proxies and NTLM/Digest proxy authentication are not
implemented.

## Import SSH hosts and keychains

Open **SSH → Import from another app** (also available in SFTP). It automatically
scans known per-user application locations, reads the local host/keychain data,
and shows sources and discovered hosts/keys. Select the desired items and import.
**Scan installed apps** refreshes the results, including after entering a private
key passphrase. **Import a file** remains available for portable backups. Parsing,
decryption and key decoding run in a worker isolate; scanning never writes to the
source application or CB's vault.

Automatic discovery reads:

- Termius: `%APPDATA%/Termius`, Linux `.config/Termius` and snap profiles, macOS
  Application Support and App Store containers. Its encrypted IndexedDB LevelDB
  tables are read directly, using the current manifest, active SST/WAL files,
  checksums, sequence numbers and deletion tombstones. A bounded Snappy/V8 reader
  decodes the records; unsupported versions/blob records fail visibly.
- Termius's named `localKey` from Windows Credential Manager (`CredReadW`), macOS
  Keychain (`security`), or Linux Secret Service (`secret-tool`). XSalsa20-Poly1305
  authenticates a candidate before it is used. This imports private keys, including
  unattached keys, passwords and host → config → identity → key references. Group
  inheritance, local/server IDs, newer identity join tables and logical deletion
  are handled. Decrypted data stays in memory.
- OpenSSH: `~/.ssh/config`, Includes and local private keys through the shared
  discovery service.
- PuTTY and WinSCP: their current-user Windows registry sessions; WinSCP also
  checks its per-user INI. Registry access is read-only.
- SecureCRT: session INIs in default per-user VanDyke directories.
- Tabby: per-user `config.yaml` in AppData, `.config`, or Application Support.

Referenced private key files in installed configurations are read automatically
within the user's home. UNC paths and symbolic links are excluded. Portable
installations outside these default locations can use file import. Scans retain
per-source not-found/read-error/key-unavailable states; one failed source does not
hide the other applications. macOS/Linux discovery is implemented but was not
validated against live installations in this Windows session.

Supported portable formats:

| Client | Input | Credentials |
| --- | --- | --- |
| Termius | Decrypted host CSV, JSON, or OpenSSH export | Plaintext exported passwords, inline OpenSSH/PEM keys, or explicitly selected key files |
| OpenSSH | `config` / `sshconfig` | Explicitly selected `IdentityFile` keys |
| PuTTY | Export of `HKCU\Software\SimonTatham\PuTTY\Sessions` as `.reg` | OpenSSH/PEM or PPK v2/v3 private keys |
| WinSCP | Tools → Export/Backup Configuration, `.ini` | SFTP/SCP sessions; encrypted saved passwords must be entered again |
| SecureCRT | SSH session `.ini` files | Host, username, hexadecimal SSH port and identity file; encrypted passwords must be entered again |
| Tabby | `config.yaml`, profile-list YAML, or JSON with `profiles` | SSH profiles, inline passwords if present, and explicitly selected private key files |

Automatic Termius discovery needs no export, external runtime, cloud login or
third-party extraction script. For a portable backup instead, the normalized
`export.json` and key files produced by
[termius-export](https://github.com/y01and3/termius-export) are supported: add
`export.json` together with the referenced files from `keys/` and `keys-unlinked/`.
Its per-key passphrases are honored when present. The older official
[Termius CLI](https://github.com/termius/termius-cli) can produce an OpenSSH
`sshconfig`; its repository is archived, so availability depends on the version.

Termius CSV uses the columns `Groups`, `Label`, `Hostname`, `Protocol`, `Port`,
`Username`, `Password`, with optional `IdentityFile`/`KeyLabel` and `KeyPassphrase`.
Only SSH/SFTP rows are imported. Quoted commas, quotes and newlines are retained.
JSON accepts the following portable structure (private keys must contain real
OpenSSH/PEM data, with newlines encoded as JSON `\n`):

```json
{
  "keys": [{"id": "work-key", "label": "Work", "private_key": "<OpenSSH/PEM>", "passphrase": ""}],
  "identities": [{"id": "deploy", "username": "deploy", "ssh_key_id": "work-key"}],
  "hosts": [{"label": "Web", "address": "web.example.test", "port": 22, "group": "Work", "identity_id": "deploy"}]
}
```

`keychain` and `ssh_keys` are accepted instead of `keys`; keys may also use
`name`/`pem`. Keychain-only exports import unattached private keys. Normalized
exports can use `keys[].file` and `hosts[].identity_file` instead of inline keys.
References match files by full path, then by an unambiguous basename. In manual
file mode the importer only reads explicitly selected files. Missing, invalid or
ambiguous keys skip their hosts and explain why in the preview. A shared
passphrase field handles encrypted key files; exported per-key passphrases take
precedence. PPK v2/v3 RSA, Ed25519 and ECDSA are decoded directly, with MAC
verification; encrypted PPK uses AES-CBC and SHA-1 or bounded Argon2 derivation.
Hardware keys and SSH agents are not supported.

Termius scans read the `proxies` table, resolve proxy → identity credentials and
host/group configuration → proxy references, and include unattached proxies in
the selection. Portable JSON accepts `proxies` plus `hosts[].proxy_id`, or an
inline `hosts[].proxy` with `type`/`kind`, `host`/`hostname`, `port`, `username` and
`password`. CSV supports `ProxyType`, `ProxyHost`, `ProxyPort`, `ProxyUsername`
and `ProxyPassword`. PuTTY/WinSCP proxy methods 1/2/3 map to SOCKS4a/SOCKS5/HTTP;
encrypted WinSCP proxy passwords must be entered again. Tabby HTTP/SOCKS proxy
endpoints are also retained. Missing/invalid/unsupported proxies skip their
dependent hosts rather than silently importing a direct route. Proxy previews
show only names, protocols and endpoints; attached proxies are selected together
with their hosts. Matching proxy connection settings and credentials are reused
without overwriting existing entries.

Jump-host, forwarding and conditional settings are reported for manual review.
Manual-file Includes are never followed and commands are never executed. Imported
data never adds trusted server fingerprints. Duplicate keys are reused by
fingerprint, and duplicate hosts (name, group, hostname, port, username, proxy route) are
skipped without replacing existing credentials. The selected batch is saved in
one credential-vault write, with in-memory rollback on failure. No intermediate
plaintext files are created. Preview rows display host metadata and key
fingerprints, never passwords or private key material.

Limits: 128 configuration/key files, 8 MiB per file, 32 MiB total, and 2,000 parsed hosts
or keys per batch. Export files must be UTF-8; UTF-16LE with BOM is also accepted
for Windows registry exports. Unit tests cover formats, key linking, encrypted
keys, duplicate handling and rollback; widget tests cover selection and preview
invalidation on narrow/wide English and Vietnamese dialogs. Binary fixtures cover
current manifests, inactive tables, WAL fragments, tombstones and corruption.
`CB_SSH_LOCAL_SCAN=true` enables a read-only local Termius smoke test which logs
counts only; it never imports live credentials into CB's vault.

## FTPS desktop

The existing FTP connection form offers plain FTP, Explicit TLS (default port
21), and Implicit TLS (default port 990). The saved `ftpSecurity` option is
restored when reconnecting. All continue through the shared FTP browser.

FTPS uses desktop `curl` (the Windows system executable, or `curl` on PATH on
macOS/Linux). This supplies TLS shutdown and session handling which Dart's
`SecureSocket` does not provide adequately for strict FTPS upload servers.
Mobile FTPS is not supported by this backend. Plain FTP retains the Dart client.

Both control and data channels require TLS. Certificate verification remains
enabled; there is no plaintext fallback or accept-all certificate option.
Passwords are passed in a curl configuration through stdin, never in command
arguments or a temporary configuration file. Curl's user configuration and
environment proxies are disabled for these direct server connections.
Processes are scoped to operations and terminated on disconnect. Download
progress is incremental; upload progress reports completion.

## Verification

From `cb_file_manager/`:

```powershell
flutter analyze --no-pub
flutter test --no-pub
python -m pip install asyncssh pyftpdlib pyopenssl
flutter test --no-pub --dart-define=CB_SECURE_NETWORK_TEST=true test/services/ssh
```

Loopback tests start temporary SSH and FTP servers, require verified TLS on FTPS,
exercise transfers and file operations, password/key auth, PTY output, changed
host rejection, and independent connections on different ports. They run only
with the explicit define, so ordinary unit tests need no Python packages.

The widget tests cover English/Vietnamese and narrow/wide layouts. Optional
`CB_SSH_CAPTURE=true` captures the SSH workspace fixture into
`build/network-layout-review/ssh-workspace.png` and the connection dialog fixture
into `build/network-layout-review/ssh-connection-dialog.png`.

Restart the application after updating dependencies and the network registry.
