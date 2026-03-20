# Project Brief

- **Product**: CoolBird FM (a.k.a **CB File Hub**) – cross-platform Flutter file manager.
- **Platforms**: 
    - **Tier 1**: Windows, Android.
    - **Tier 2**: macOS, Linux.
    - **Tier 3**: iOS (Video playback support is currently experimental/disabled).
- **Promise**: Fast media-centric browsing with tagging, streaming, and PiP playback inside a tabbed shell.
- **Core Value**: Local-first control: scan, tag, and stream personal libraries without cloud lock-in.

## Pillars
- **Experience**: Consistent UI across platforms with touch/desktop parity.
- **Media IQ**: Tag-driven organization, instant search, rich previews, and smart albums.
- **Performance**: Startup guards, caching, and isolates keep scrolling and playback smooth.

## Must-Have Features
- Tag + search, grid/list file viewing, mobile galleries.
- **Streaming**: SMB (via native implementation), FTP (manual), WebDAV (manual/http).
- **Playback**: Picture-in-Picture (PiP) window support on Desktop.

## Guardrails
- Privacy-first storage access, no unsolicited uploads.
- Keep runtime responsive on low-end Android and Windows laptops.
- Maintain full functionality offline; network integrations are optional add-ons.

## Success Signals
- Rapid file discovery (<2s searches for typical directories).
- Stable playback across target platforms.
- Tagging used in majority of sessions.

_Last updated: 2026-03-07_
