// Keep build-only metadata and source maps out of the published static assets.
import { readdir, rm } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const output = fileURLToPath(new URL("../public/", import.meta.url));
for (const entry of await readdir(output, { recursive: true, withFileTypes: true })) {
  if (entry.isFile() && (entry.name.endsWith(".map") || ["webpack.stats.json", "chunk-map.json"].includes(entry.name))) {
    await rm(resolve(entry.parentPath, entry.name));
  }
}
