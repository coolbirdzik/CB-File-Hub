import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  defaultListingsDirectory, loadStoreListings, loadGooglePlayListings, loadGooglePlayImages,
} from './store_listings.mjs';

// A portable snapshot: publishers consume the exact copy validated for this
// release, including all configured artwork, rather than resolving repo paths.
export function bundleStoreListings(output, directory = defaultListingsDirectory) {
  const microsoft = loadStoreListings(directory);
  const play = loadGooglePlayListings(directory);
  const playImages = loadGooglePlayImages(directory);
  // Refuse reuse so an older locale/image cannot survive a partial rebuild.
  if (fs.existsSync(output)) throw new Error(`Listing bundle already exists: ${output}`);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.mkdirSync(output);
  fs.mkdirSync(path.join(output, 'images'));
  const copyImage = (source) => {
    const data = fs.readFileSync(source);
    const hash = crypto.createHash('sha256').update(data).digest('hex');
    const file = `images/${hash}-${path.basename(source)}`;
    fs.writeFileSync(path.join(output, file), data);
    return file;
  };
  for (const [locale, listing] of Object.entries(microsoft)) {
    const original = JSON.parse(fs.readFileSync(path.join(directory, `${locale}.json`), 'utf8'));
    const language = original.googlePlayLanguage;
    const entry = {
      descriptionFile: `${locale}.txt`,
      shortDescription: play[language].shortDescription,
      googlePlayLanguage: language,
      ...(playImages[language] ? {
        googlePlayImages: Object.fromEntries(Object.entries(playImages[language])
          .map(([type, images]) => [type, images.map((image) => copyImage(image.source))])),
      } : {}),
      microsoftStoreImages: listing.images.map((image) => ({
        file: copyImage(image.source), imageType: image.imageType,
        ...(image.description ? { description: image.description } : {}),
      })),
    };
    fs.writeFileSync(path.join(output, `${locale}.txt`), `${listing.description}\n`);
    fs.writeFileSync(path.join(output, `${locale}.json`), `${JSON.stringify(entry, null, 2)}\n`);
  }
  // Revalidate paths, dimensions and text from the snapshot itself.
  loadStoreListings(output);
  loadGooglePlayListings(output);
  loadGooglePlayImages(output);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (!process.argv[2]) throw new Error('Usage: node scripts/bundle_store_listings.mjs <output-directory> [listings-directory]');
    bundleStoreListings(path.resolve(process.argv[2]), process.argv[3]);
    console.log(`Store submission bundle: ${process.argv[2]}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
