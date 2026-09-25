import data from "../data/releases.json";

const github = "https://github.com/coolbirdzik/CB-File-Hub";

// macOS ships only as a DMG on GitHub Releases: link the newest one straight to the file.
// The snapshot is refreshed on every release build, so this tracks the latest version.
const latestDmg = data.releases.flatMap((r) => r.assets).find((a) => a.platform === "macos");

export const links = {
  microsoftStore: "https://apps.microsoft.com/detail/9nchpzkc4m5c",
  googlePlay: "https://play.google.com/store/apps/details?id=com.cbv.filehub",
  macos: latestDmg?.url ?? `${github}/releases/latest`,
  demo: "/demo",
  privacy: "/privacy",
  terms: "/terms",
  releases: "/releases",
  github,
};

// Anchor ids are kept from the previous static site so existing deep links still work.
// Rooted at "/" so the same links work from /releases and the 404 page.
export const nav = [
  { href: "/#experience", en: "Experience", vi: "Trải nghiệm" },
  { href: "/#features", en: "Features", vi: "Tính năng" },
  { href: "/#platforms", en: "Platforms", vi: "Nền tảng" },
  { href: "/#live-demo", en: "Live demo", vi: "Dùng thử" },
  { href: "/releases", en: "Release notes", vi: "Bản phát hành" },
];

export const download = { en: "Download", vi: "Tải ứng dụng" };
export const liveDemo = { en: "Live demo", vi: "Dùng thử" };
