// Sample library for the live demo. Everything here is fictional and lives only in memory.
// Names and thumbnails follow the app's own showcase fixtures (cover_ocean.jpg, trailer.mp4, ...).

export type Kind = "drive" | "folder" | "image" | "video" | "audio" | "pdf" | "text" | "code" | "sheet" | "archive";
export type Tone = "ocean" | "sunset" | "forest" | "night" | "earth";

export type Entry = {
  id: string;
  name: string;
  kind: Kind;
  parent: string | null;
  size?: number; // bytes
  modified: string; // ISO date
  tone?: Tone;
  tags?: string[];
};

const KB = 1024;
const MB = 1024 * KB;
const GB = 1024 * MB;

export const entries: Entry[] = [
  { id: "c", name: "C:", kind: "drive", parent: null, size: 128 * GB, modified: "2026-09-01" },
  { id: "d", name: "D:", kind: "drive", parent: null, size: 512 * GB, modified: "2026-09-01" },

  { id: "users", name: "Users", kind: "folder", parent: "c", modified: "2026-08-02" },
  { id: "windows", name: "Windows", kind: "folder", parent: "c", modified: "2026-07-14" },
  { id: "demo", name: "Demo", kind: "folder", parent: "users", modified: "2026-09-20" },

  { id: "desktop", name: "Desktop", kind: "folder", parent: "demo", modified: "2026-09-21" },
  { id: "documents", name: "Documents", kind: "folder", parent: "demo", modified: "2026-09-19" },
  { id: "downloads", name: "Downloads", kind: "folder", parent: "demo", modified: "2026-09-22" },
  { id: "music", name: "Music", kind: "folder", parent: "demo", modified: "2026-08-30" },
  { id: "pictures", name: "Pictures", kind: "folder", parent: "demo", modified: "2026-09-18" },
  { id: "videos", name: "Videos", kind: "folder", parent: "demo", modified: "2026-09-16" },

  { id: "albums", name: "Albums", kind: "folder", parent: "pictures", modified: "2026-09-12" },
  { id: "screens", name: "Screenshots", kind: "folder", parent: "pictures", modified: "2026-09-22" },
  { id: "sc1", name: "Screenshot 2026-09-22.png", kind: "image", parent: "screens", size: 412 * KB, modified: "2026-09-22", tone: "ocean" },
  { id: "weekend", name: "Weekend Picks", kind: "folder", parent: "albums", modified: "2026-09-12" },
  { id: "p1", name: "cover_forest.jpg", kind: "image", parent: "pictures", size: 52.4 * KB, modified: "2026-09-15", tone: "forest", tags: ["travel", "mountains"] },
  { id: "p2", name: "cover_night_city.jpg", kind: "image", parent: "pictures", size: 58.7 * KB, modified: "2026-09-12", tone: "night", tags: ["favorite"] },
  { id: "p3", name: "cover_ocean.jpg", kind: "image", parent: "pictures", size: 52.2 * KB, modified: "2026-09-18", tone: "ocean", tags: ["travel", "beach", "favorite"] },
  { id: "p4", name: "cover_sunset.jpg", kind: "image", parent: "pictures", size: 57.9 * KB, modified: "2026-09-10", tone: "sunset", tags: ["vacation"] },
  { id: "p11", name: "poster_northern_lights.jpg", kind: "image", parent: "pictures", size: 61.3 * KB, modified: "2026-09-17", tone: "ocean", tags: ["travel"] },
  { id: "p12", name: "poster_desert_run.jpg", kind: "image", parent: "pictures", size: 55.8 * KB, modified: "2026-09-16", tone: "sunset" },
  { id: "p13", name: "poster_deep_forest.jpg", kind: "image", parent: "pictures", size: 54.0 * KB, modified: "2026-09-14", tone: "forest", tags: ["mountains"] },
  { id: "p14", name: "poster_after_dark.jpg", kind: "image", parent: "pictures", size: 57.1 * KB, modified: "2026-09-13", tone: "night", tags: ["favorite"] },
  { id: "p5", name: "beach_sunrise.jpg", kind: "image", parent: "weekend", size: 57.9 * KB, modified: "2026-09-08", tone: "sunset", tags: ["beach"] },
  { id: "p6", name: "harbour_lights.jpg", kind: "image", parent: "weekend", size: 60.1 * KB, modified: "2026-09-07", tone: "ocean", tags: ["travel"] },
  { id: "p7", name: "mountain_ridge.jpg", kind: "image", parent: "weekend", size: 52.4 * KB, modified: "2026-09-06", tone: "forest", tags: ["mountains"] },
  { id: "p8", name: "night_market.jpg", kind: "image", parent: "weekend", size: 53.4 * KB, modified: "2026-09-05", tone: "night", tags: ["vacation"] },
  { id: "p9", name: "lake_reflection.jpg", kind: "image", parent: "weekend", size: 60.1 * KB, modified: "2026-09-04", tone: "ocean" },
  { id: "p10", name: "desert_dunes.jpg", kind: "image", parent: "weekend", size: 52.1 * KB, modified: "2026-09-03", tone: "sunset", tags: ["travel"] },

  { id: "v1", name: "trailer.mp4", kind: "video", parent: "videos", size: 84.2 * MB, modified: "2026-09-16", tone: "earth", tags: ["movies", "project"] },
  { id: "v2", name: "teaser_cut.mp4", kind: "video", parent: "videos", size: 31.6 * MB, modified: "2026-09-14", tone: "earth", tags: ["project"] },
  { id: "v3", name: "timelapse_sunset.mp4", kind: "video", parent: "videos", size: 128.4 * MB, modified: "2026-09-11", tone: "sunset", tags: ["travel"] },
  { id: "v4", name: "feature_film.mkv", kind: "video", parent: "videos", size: 2.3 * GB, modified: "2026-08-28", tone: "earth", tags: ["movies", "action"] },
  { id: "v5", name: "trailer (1).mp4", kind: "video", parent: "downloads", size: 84.2 * MB, modified: "2026-09-19", tone: "earth" },

  { id: "d1", name: "project_brief.pdf", kind: "pdf", parent: "documents", size: 1.2 * MB, modified: "2026-09-20", tags: ["project"] },
  { id: "d2", name: "meeting_notes.txt", kind: "text", parent: "documents", size: 18 * KB, modified: "2026-09-19", tags: ["project"] },
  { id: "d3", name: "export_settings.json", kind: "code", parent: "documents", size: 4.1 * KB, modified: "2026-09-17" },
  { id: "d4", name: "budget_2026.xlsx", kind: "sheet", parent: "documents", size: 62 * KB, modified: "2026-09-02", tags: ["archive"] },

  { id: "m1", name: "weekend_mix.mp3", kind: "audio", parent: "music", size: 11.4 * MB, modified: "2026-08-30", tags: ["favorite"] },
  { id: "m2", name: "focus_session.flac", kind: "audio", parent: "music", size: 38.9 * MB, modified: "2026-08-21" },

  { id: "w1", name: "wallpaper_pack.zip", kind: "archive", parent: "downloads", size: 341 * MB, modified: "2026-09-22", tags: ["archive"] },
  { id: "w2", name: "README.txt", kind: "text", parent: "downloads", size: 2.3 * KB, modified: "2026-09-21" },
  { id: "w3", name: "cover_ocean (copy).jpg", kind: "image", parent: "downloads", size: 52.2 * KB, modified: "2026-09-20", tone: "ocean" },

  { id: "s1", name: "todo.txt", kind: "text", parent: "desktop", size: 1.1 * KB, modified: "2026-09-21" },

  { id: "media", name: "Media", kind: "folder", parent: "d", modified: "2026-09-01" },
  { id: "movies", name: "Movies", kind: "folder", parent: "media", modified: "2026-08-28" },
  { id: "photos", name: "Photos", kind: "folder", parent: "media", modified: "2026-09-05" },
  { id: "backup", name: "Backups", kind: "folder", parent: "d", modified: "2026-09-10" },
  { id: "b1", name: "cbfilehub_backup.zip", kind: "archive", parent: "backup", size: 2.4 * MB, modified: "2026-09-10" },
];

export const byId = new Map(entries.map((e) => [e.id, e]));

export function childrenOf(id: string) {
  return entries.filter((e) => e.parent === id);
}

export function pathOf(id: string): Entry[] {
  const chain: Entry[] = [];
  let cur = byId.get(id);
  while (cur) {
    chain.unshift(cur);
    cur = cur.parent ? byId.get(cur.parent) : undefined;
  }
  return chain;
}

export function pathString(id: string) {
  const chain = pathOf(id);
  if (chain.length === 1) return `${chain[0].name}\\`;
  return chain.map((e) => e.name).join("\\");
}

export function folderSize(id: string): number {
  return childrenOf(id).reduce((sum, e) => sum + (e.kind === "folder" ? folderSize(e.id) : e.size ?? 0), 0);
}

export function formatSize(bytes: number) {
  if (bytes < KB) return `${bytes} B`;
  if (bytes < MB) return `${(bytes / KB).toFixed(1)} KB`;
  if (bytes < GB) return `${(bytes / MB).toFixed(1)} MB`;
  return `${(bytes / GB).toFixed(2)} GB`;
}

export function formatDate(iso: string, lang: "en" | "vi") {
  const d = new Date(`${iso}T09:30:00`);
  return d.toLocaleDateString(lang === "vi" ? "vi-VN" : "en-US", { day: "numeric", month: "short", year: "numeric" });
}

export const isMedia = (e: Entry) => e.kind === "image" || e.kind === "video";

// Tag tree, matching the app's Tag Management showcase.
export type TagDef = { id: string; name: { en: string; vi: string }; color: string; parent?: string };

export const tags: TagDef[] = [
  { id: "archive", name: { en: "Archive", vi: "Lưu trữ" }, color: "#f4511e" },
  { id: "favorite", name: { en: "Favorite", vi: "Yêu thích" }, color: "#fb8c00" },
  { id: "media", name: { en: "Media", vi: "Media" }, color: "#43a047" },
  { id: "movies", name: { en: "Movies", vi: "Phim" }, color: "#e91e63", parent: "media" },
  { id: "action", name: { en: "Action", vi: "Hành động" }, color: "#f4511e", parent: "movies" },
  { id: "photos", name: { en: "Photos", vi: "Ảnh" }, color: "#fb8c00", parent: "media" },
  { id: "project", name: { en: "project", vi: "dự án" }, color: "#00acc1" },
  { id: "travel", name: { en: "Travel", vi: "Du lịch" }, color: "#7cb342" },
  { id: "beach", name: { en: "Beach", vi: "Biển" }, color: "#fb8c00", parent: "travel" },
  { id: "mountains", name: { en: "Mountains", vi: "Núi" }, color: "#7cb342", parent: "travel" },
  { id: "vacation", name: { en: "vacation", vi: "kỳ nghỉ" }, color: "#8bc34a" },
];

export const tagById = new Map(tags.map((t) => [t.id, t]));

/** Files carrying a tag or any of its descendants. */
export function filesWithTag(tagId: string) {
  const ids = new Set([tagId]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const t of tags) if (t.parent && ids.has(t.parent) && !ids.has(t.id)) (ids.add(t.id), (grew = true));
  }
  return entries.filter((e) => e.tags?.some((t) => ids.has(t)));
}

// Thumbnails are CSS gradients, the same flat colour fields the app's showcase fixtures use.
export const toneBackground: Record<Tone, string> = {
  ocean: "radial-gradient(circle at 50% 55%, #7cc6f0 0%, transparent 60%), linear-gradient(180deg, #3172c4, #6bc6ee)",
  sunset: "radial-gradient(circle at 50% 55%, #ffd3a0 0%, transparent 60%), linear-gradient(180deg, #ff8a5b, #ffd98a)",
  forest: "radial-gradient(circle at 50% 55%, #9fd18f 0%, transparent 60%), linear-gradient(180deg, #3b8762, #8ccb78)",
  night: "radial-gradient(circle at 50% 55%, #d59af0 0%, transparent 60%), linear-gradient(180deg, #7442b6, #de82f1)",
  earth:
    "radial-gradient(circle at 44% 42%, rgba(255,214,150,.35) 0 2%, transparent 3%), radial-gradient(circle at 58% 50%, rgba(255,214,150,.25) 0 1.5%, transparent 2.5%), radial-gradient(circle at 50% 50%, #2b3f63 0%, #16233b 38%, #0a1120 43%, #020306 45%), #020306",
};

// Accent colours offered by the app's Settings > Accent color (theme_config.dart).
export const accents = [
  { id: "teal", hex: "#00b294", name: { en: "Teal", vi: "Xanh ngọc" } },
  { id: "blue", hex: "#0078d4", name: { en: "Blue", vi: "Xanh dương" } },
  { id: "green", hex: "#107c10", name: { en: "Green", vi: "Xanh lá" } },
  { id: "orange", hex: "#f7630c", name: { en: "Orange", vi: "Cam" } },
  { id: "red", hex: "#e81123", name: { en: "Red", vi: "Đỏ" } },
  { id: "magenta", hex: "#b4009e", name: { en: "Magenta", vi: "Hồng tím" } },
  { id: "purple", hex: "#744da9", name: { en: "Purple", vi: "Tím" } },
];
