import data from "../data/releases.json";

const github = "https://github.com/coolbirdzik/CB-File-Hub";

// macOS ships only as a DMG on GitHub Releases: link the newest one straight to the file.
// Windows gets the same treatment with the MSI installer, next to the Microsoft Store listing.
// The snapshot is refreshed on every release build, so these track the latest version.
const assets = data.releases.flatMap((r) => r.assets);
const latestDmg = assets.find((a) => a.platform === "macos");
const latestMsi = assets.find((a) => a.platform === "windows" && a.ext === "msi");

export const links = {
  microsoftStore: "https://apps.microsoft.com/detail/9nchpzkc4m5c",
  googlePlay: "https://play.google.com/store/apps/details?id=com.cbv.filehub",
  windows: latestMsi?.url ?? `${github}/releases/latest`,
  macos: latestDmg?.url ?? `${github}/releases/latest`,
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
  { href: "/releases", en: "Release notes", vi: "Bản phát hành" },
];

export const download = { en: "Download", vi: "Tải ứng dụng" };
