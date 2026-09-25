export const links = {
  microsoftStore: "https://apps.microsoft.com/detail/9nchpzkc4m5c",
  googlePlay: "https://play.google.com/store/apps/details?id=com.cbv.filehub",
  demo: "/demo",
  privacy: "/privacy",
  terms: "/terms",
  releases: "/releases",
  github: "https://github.com/coolbirdzik/CB-File-Hub",
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
