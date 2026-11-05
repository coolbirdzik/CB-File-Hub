# CB File Hub: All-in-One File Manager for Windows, macOS, Linux and Android

**One app for your files, servers and storage.** CB File Hub combines a tabbed file manager, an SSH client with SFTP, network shares (SMB, FTP, WebDAV), an AI file assistant, a disk cleaner, a photo and video library, file tags and a torrent library, so you do not need a separate tool for each job.

[![Build and Test](https://github.com/coolbirdzik/cb-file-hub/actions/workflows/build-test.yml/badge.svg)](https://github.com/coolbirdzik/cb-file-hub/actions/workflows/build-test.yml)
[![Build and Release](https://github.com/coolbirdzik/CB-File-Hub/actions/workflows/release.yml/badge.svg)](https://github.com/coolbirdzik/CB-File-Hub/actions/workflows/release.yml)

<p align="center">
  <a href="https://apps.microsoft.com/detail/9nchpzkc4m5c?referrer=appbadge&mode=full"><img src="https://get.microsoft.com/images/en-us%20dark.svg" alt="Download CB File Hub from the Microsoft Store" width="200" /></a>
  &nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.cbv.filehub"><img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get CB File Hub on Google Play" width="220" /></a>
</p>

<p align="center">
  <a href="https://coolbird.net">Website</a> ·
  <a href="https://github.com/coolbirdzik/cb-file-hub/releases/latest">Download</a> ·
  <a href="docs/index.md">Documentation</a> ·
  <a href="README.vi.md">Tiếng Việt</a>
</p>

<p align="center">
  <img src="screenshots/promo/desktop/01_file_browser.png" alt="CB File Hub desktop file manager with tabs, tags and file preview" />
</p>

## Features

### File manager
Tabs and tear-off windows, split panes, grid and list views with previews, pinned locations, archive browsing (zip, 7z, tar), keyboard shortcuts and a fast recursive search.

### CB Agent: AI file assistant
Ask in plain language: *"find duplicate videos"*, *"show large files from last year"*, *"tag these photos"*. The agent searches file names and document text, explains what it found and **asks before it moves, renames or deletes anything**. Use OpenAI, Anthropic, OpenRouter, Ollama or LM Studio, or run a local GGUF model on your own device with no cloud.

### SSH manager and network files
- **SSH client:** saved hosts and keys, built-in terminal, trusted hosts, connections through HTTP or SOCKS proxies.
- **SFTP:** browse and transfer files on your servers.
- **SSH tunnels:** local, remote and SOCKS5 port forwarding.
- **Import:** hosts from Termius, OpenSSH, PuTTY, WinSCP, SecureCRT and Tabby.
- **Network shares:** SMB/CIFS, FTP and WebDAV, with media streaming from network shares.

### Disk cleaner
Smart Clean removes only junk that apps can recreate: temporary files, browser and app caches, crash dumps, and developer caches (npm, pip, Cargo, Gradle, Go, Xcode). Disk usage shows a full-drive tree, and you review every item before it goes to the Recycle Bin or Trash.

### Photos, videos and tags
Gallery and video library, built-in player with picture-in-picture, image editor, albums and rule-based smart albums, and hierarchical tags you can search across every folder.

### Torrents and backup
A searchable torrent library with qBittorrent and Transmission import and built-in downloads. Back up settings and tags to Google Drive, Dropbox or OneDrive.

Heavy work (disk scans, search, thumbnails, hashing, archives) runs on Rust worker threads: a full rescan of 100,000 files took **84.9 ms, 3.3× faster than TreeSize Free** in [our benchmark](docs/quality/03-rust-benchmarks.md#folder-scan-ui-comparison-with-treesize-free).

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="screenshots/promo/desktop/04_ai_search.png" alt="AI file search in the CB Agent side panel" /></td>
    <td width="50%"><img src="screenshots/promo/desktop/05_ai_approval.png" alt="CB Agent asks for approval before changing files" /></td>
  </tr>
  <tr>
    <td width="50%"><img src="screenshots/promo/desktop/10_disk_cleaner.png" alt="Disk cleaner scan results with category review" /></td>
    <td width="50%"><img src="screenshots/promo/desktop/07_tag_management.png" alt="Hierarchical file tags and tag management" /></td>
  </tr>
  <tr>
    <td width="50%"><img src="screenshots/promo/desktop/02_gallery_hub.png" alt="Photo and video gallery hub" /></td>
    <td width="50%"><img src="screenshots/promo/desktop/11_torrent_library.png" alt="Torrent library with qBittorrent import" /></td>
  </tr>
</table>

<p align="center">
  <img src="screenshots/promo/mobile/01_mobile_home.png" alt="CB File Hub Android home screen" width="22%" />
  <img src="screenshots/promo/mobile/02_mobile_grid.png" alt="CB File Hub Android file grid" width="22%" />
  <img src="screenshots/promo/mobile/03_mobile_tabs.png" alt="CB File Hub Android tabs" width="22%" />
  <img src="screenshots/promo/mobile/04_mobile_tags.png" alt="CB File Hub Android file tags" width="22%" />
</p>

[More screenshots](screenshots/)

## Download

| Platform | Get CB File Hub |
|----------|-----------------|
| **Windows** | [Microsoft Store](https://apps.microsoft.com/detail/9nchpzkc4m5c), or the [MSI installer / portable ZIP](https://github.com/coolbirdzik/cb-file-hub/releases/latest) |
| **macOS 12+** | [Universal DMG](https://github.com/coolbirdzik/cb-file-hub/releases/latest) for Apple Silicon and Intel |
| **Linux** | [.deb for Debian/Ubuntu, or tar.gz](https://github.com/coolbirdzik/cb-file-hub/releases/latest) |
| **Android** | [Google Play](https://play.google.com/store/apps/details?id=com.cbv.filehub) or [APK](https://github.com/coolbirdzik/cb-file-hub/releases/latest) |

Some features depend on the platform; see the [installation guide](docs/guides/04-installation.md) and the [feature guides](docs/features/).

## Build from source

Requires **Flutter 3.47.8 stable** and [`just`](https://github.com/casey/just):

```bash
git clone https://github.com/coolbirdzik/cb-file-hub.git
cd cb-file-hub
just deps
```

See [development setup](docs/contributing/04-development-setup.md) for each platform's toolchain, builds and tests.

## Contributing

[Open an issue](https://github.com/coolbirdzik/cb-file-hub/issues) for bugs and feature requests, or send a pull request. Start with the [contribution guide](docs/contributing/01-contribution-guide.md) and the [technical docs](docs/technical/index.md).
