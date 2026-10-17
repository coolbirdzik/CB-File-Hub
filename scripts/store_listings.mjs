import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const defaultListingsDirectory = fileURLToPath(
  new URL('../store/listings/', import.meta.url),
);

function loadListingContent(directory = defaultListingsDirectory) {
  const listings = {};
  const playLanguages = new Set();
  for (const file of fs.readdirSync(directory).filter((name) => name.endsWith('.json')).sort()) {
    const locale = path.basename(file, '.json');
    if (!/^[a-z]{2,3}-[a-z0-9]+$/.test(locale)) {
      throw new Error(`Invalid Store listing locale: ${locale}`);
    }
    const entry = JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8'));
    if (typeof entry.descriptionFile !== 'string' ||
        !/^[a-z0-9-]+\.txt$/.test(entry.descriptionFile)) {
      throw new Error(`${locale}: descriptionFile must name a sibling .txt file`);
    }
    const description = fs.readFileSync(path.join(directory, entry.descriptionFile), 'utf8').trim();
    if (!description || description.length > 4000) {
      throw new Error(`${locale}: shared description must contain 1–4000 characters`);
    }
    const shortDescription = entry.shortDescription?.trim();
    if (!shortDescription || shortDescription.length > 80) {
      throw new Error(`${locale}: shortDescription must contain 1–80 characters`);
    }
    if (typeof entry.googlePlayLanguage !== 'string' ||
        !/^[a-z]{2,3}(?:-[A-Z]{2}|-[0-9]{3})?$/.test(entry.googlePlayLanguage) ||
        playLanguages.has(entry.googlePlayLanguage)) {
      throw new Error(`${locale}: provide a unique Google Play language code`);
    }
    playLanguages.add(entry.googlePlayLanguage);
    const features = description.split(/\r?\n/)
      .filter((line) => line.startsWith('- ')).map((line) => line.slice(2).trim());
    if (features.length < 1 || features.length > 20 ||
        features.some((feature) => !feature || feature.length > 200)) {
      throw new Error(`${locale}: provide 1–20 features, each containing 1–200 characters`);
    }
    listings[locale] = {
      description, shortDescription, googlePlayLanguage: entry.googlePlayLanguage,
      features,
    };
  }
  for (const locale of ['en-us', 'vi-vn']) {
    if (!listings[locale]) throw new Error(`Missing required Store listing: ${locale}`);
  }
  return listings;
}

export function loadStoreListings(directory = defaultListingsDirectory) {
  return Object.fromEntries(Object.entries(loadListingContent(directory))
    .map(([locale, { description, features }]) => [locale, { description, features }]));
}

export function loadGooglePlayListings(directory = defaultListingsDirectory) {
  return Object.fromEntries(Object.values(loadListingContent(directory))
    .map(({ googlePlayLanguage, shortDescription, description }) =>
      [googlePlayLanguage, { shortDescription, fullDescription: description }]));
}

// Update only repository-owned marketing text; retain Store images, titles,
// release notes, policy URLs, platform overrides and all unrelated languages.
export function applyStoreListings(submission, content) {
  const result = structuredClone(submission);
  result.listings ??= {};
  const fallback = result.listings['en-us']?.baseListing ??
    Object.values(result.listings).find((listing) => listing.baseListing?.title)?.baseListing;
  for (const [locale, listing] of Object.entries(content)) {
    const existing = result.listings[locale];
    const base = existing?.baseListing ?? fallback;
    if (!base?.title) {
      throw new Error(`No existing Store title/metadata to seed ${locale}; prepare the initial listing in Partner Center first`);
    }
    result.listings[locale] = {
      ...(existing ?? { platformOverrides: {} }),
      baseListing: { ...structuredClone(base), ...structuredClone(listing) },
    };
  }
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const directory = process.argv[2] || defaultListingsDirectory;
    console.log(JSON.stringify({
      microsoft: loadStoreListings(directory),
      googlePlay: loadGooglePlayListings(directory),
    }, null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
