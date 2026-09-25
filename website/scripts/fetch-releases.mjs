#!/usr/bin/env node
// Snapshots the GitHub releases into src/data/releases.json for the /releases page.
//
//   npm run releases            # refresh the snapshot
//   GITHUB_TOKEN=... npm run releases   # optional, lifts the 60 req/h anonymous limit
//
// The commit list is parsed out of each release body ("What's Changed" section).
// `ci:` commits (build-number bumps and the like), version bumps and merge commits are dropped: they mean nothing to users.
// If GitHub cannot be reached, the existing snapshot is kept so builds never fail over it.

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = "coolbirdzik/CB-File-Hub";
const OUT = resolve(dirname(fileURLToPath(import.meta.url)), "../src/data/releases.json");

const TYPES = "feat|fix|perf|refactor|style|docs|test|tests|chore|build|ci|revert";
// Squashed commits sometimes carry several conventional subjects on one line: split before each.
const SPLIT = new RegExp(`\\s+(?=(?:${TYPES})(?:\\([^)]*\\))?!?:\\s)`, "i");
const HEAD = new RegExp(`^(${TYPES})(?:\\(([^)]*)\\))?(!)?:\\s*(.+)$`, "i");

const TESTISH = /\b(tests?|e2e|ci|workflow)\b|_tests?\b/i;

/** Maps a conventional type (or an unprefixed subject) to a section of the page. */
function groupOf(type, scope, subject) {
  // Test and tooling scopes are housekeeping whatever the type says, e.g. feat(integration_tests).
  if (scope && TESTISH.test(scope)) return "maintenance";
  switch (type) {
    case "feat":
      return "new";
    case "fix":
      return "fixes";
    case "perf":
    case "refactor":
    case "style":
      return "improvements";
    case "docs":
    case "test":
    case "tests":
    case "chore":
    case "build":
    case "revert":
      return "maintenance";
    default:
      return TESTISH.test(subject) ? "maintenance" : "improvements";
  }
}

function parseCommits(body) {
  const section = body.split(/^##\s+📦/m)[0];
  const items = [];
  for (const raw of section.split(/\r?\n/)) {
    const line = raw.match(/^-\s+(.+?)\s+\(([0-9a-f]{7,40})\)\s*$/i);
    if (!line) continue;
    const [, message, hash] = line;
    if (/^Merge (branch|pull request|remote-tracking)/i.test(message)) continue;
    for (const part of message.split(SPLIT)) {
      const m = part.trim().match(HEAD);
      const type = m ? m[1].toLowerCase() : null;
      if (type === "ci") continue;
      const subject = (m ? m[4] : part).trim().replace(/\.$/, "");
      if (!subject) continue;
      if (type === "chore" && /^bump version to /i.test(subject)) continue;
      items.push({
        group: groupOf(type, m?.[2] ?? null, subject),
        type,
        scope: m?.[2] ?? null,
        breaking: Boolean(m?.[3]),
        subject: subject.charAt(0).toUpperCase() + subject.slice(1),
        hash,
      });
    }
  }
  return items;
}

function describeAsset(name) {
  const lower = name.toLowerCase();
  if (lower.endsWith(".zip")) return { platform: "windows", label: "Portable", ext: "zip" };
  if (lower.endsWith(".msi")) return { platform: "windows", label: "Installer", ext: "msi" };
  if (lower.endsWith(".msix")) return { platform: "windows", label: "MSIX", ext: "msix" };
  if (lower.endsWith(".dmg")) return { platform: "macos", label: "macOS DMG", ext: "dmg" };
  if (lower.endsWith(".apk")) {
    const arch = lower.match(/(arm64-v8a|armeabi-v7a|x86_64)/)?.[1] ?? "universal";
    return { platform: "android", label: `APK ${arch}`, ext: "apk" };
  }
  return null; // .aab is only for Google Play uploads, not for people.
}

async function main() {
  const headers = { Accept: "application/vnd.github+json", "User-Agent": "cbfilehub-website" };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;

  let data;
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=100`, { headers });
    if (!res.ok) throw new Error(`GitHub API ${res.status} ${res.statusText}`);
    data = await res.json();
  } catch (err) {
    const existing = await readFile(OUT, "utf8").catch(() => null);
    if (existing) {
      console.warn(`fetch-releases: ${err.message}. Keeping the existing snapshot.`);
      return;
    }
    throw err;
  }

  const releases = data
    .filter((r) => !r.draft)
    .map((r) => ({
      tag: r.tag_name,
      version: r.tag_name.replace(/^v/, ""),
      date: r.published_at,
      prerelease: r.prerelease,
      url: r.html_url,
      items: parseCommits(r.body ?? ""),
      assets: r.assets
        .map((a) => {
          const info = describeAsset(a.name);
          return info && { name: a.name, size: a.size, url: a.browser_download_url, ...info };
        })
        .filter(Boolean),
    }))
    .sort((a, b) => b.date.localeCompare(a.date));

  await mkdir(dirname(OUT), { recursive: true });
  await writeFile(OUT, JSON.stringify({ repo: REPO, fetchedAt: new Date().toISOString(), releases }, null, 2) + "\n");
  const kept = releases.reduce((n, r) => n + r.items.length, 0);
  console.log(`fetch-releases: ${releases.length} releases, ${kept} changes -> ${OUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
