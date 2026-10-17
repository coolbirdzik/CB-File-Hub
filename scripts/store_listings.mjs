import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const defaultListingsDirectory = fileURLToPath(
  new URL('../store/listings/', import.meta.url),
);

// Every listing must exist; these are the languages the app UI supports and
// the MSIX manifest declares (cb_file_manager/pubspec.yaml msix_config.languages).
export const requiredStoreLocales = ['en-us', 'vi-vn', 'tr-tr', 'zh-cn'];

const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const maxImageBytes = 50 * 1024 * 1024;

// Partner Center image rules for the image types CI manages.
// https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images
const microsoftImageRules = {
  Screenshot: {
    max: 10,
    size: 'at least 1366x768 and at most 3840x2160',
    fits: (width, height) => Math.max(width, height) >= 1366 && Math.min(width, height) >= 768 &&
      Math.max(width, height) <= 3840 && Math.min(width, height) <= 2160,
  },
  PromotionalArt16x9: {
    max: 1,
    size: '1920x1080 or 3840x2160',
    fits: (width, height) => (width === 1920 && height === 1080) || (width === 3840 && height === 2160),
  },
  Icon: {
    max: 1,
    size: '300x300',
    fits: (width, height) => width === 300 && height === 300,
  },
};

function readPngSize(buffer) {
  if (buffer.length < 24 || !buffer.subarray(0, 8).equals(pngSignature) ||
      buffer.toString('ascii', 12, 16) !== 'IHDR') {
    return null;
  }
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
}

function loadMicrosoftImages(locale, directory, entries) {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new Error(`${locale}: microsoftStoreImages must list at least one image`);
  }
  const counts = {};
  const images = entries.map((entry, index) => {
    const label = `${locale}: microsoftStoreImages[${index}]`;
    const rule = microsoftImageRules[entry?.imageType];
    if (!rule) {
      throw new Error(`${label}: imageType must be one of ${Object.keys(microsoftImageRules).join(', ')}`);
    }
    if (typeof entry.file !== 'string' || !entry.file.endsWith('.png')) {
      throw new Error(`${label}: file must be a .png path relative to ${directory}`);
    }
    const description = entry.description?.trim() ?? '';
    if (description.length > 200) {
      throw new Error(`${label}: description must contain at most 200 characters`);
    }
    const source = path.resolve(directory, entry.file);
    if (!fs.existsSync(source)) throw new Error(`${label}: ${entry.file} not found`);
    const data = fs.readFileSync(source);
    const size = readPngSize(data);
    if (!size) throw new Error(`${label}: ${entry.file} is not a PNG image`);
    if (data.length > maxImageBytes) throw new Error(`${label}: ${entry.file} exceeds 50 MB`);
    if (!rule.fits(size.width, size.height)) {
      throw new Error(`${label}: ${entry.imageType} must be ${rule.size}, got ${size.width}x${size.height}`);
    }
    counts[entry.imageType] = (counts[entry.imageType] ?? 0) + 1;
    const hash = crypto.createHash('sha256').update(data).digest('hex').slice(0, 12);
    return {
      source,
      // Content-addressed: an unchanged image keeps its name, so a later
      // submission can keep the uploaded copy instead of re-uploading it.
      fileName: `store-${locale}-${String(index + 1).padStart(2, '0')}-${hash}.png`,
      imageType: entry.imageType,
      description,
    };
  });
  for (const [imageType, count] of Object.entries(counts)) {
    if (count > microsoftImageRules[imageType].max) {
      throw new Error(`${locale}: at most ${microsoftImageRules[imageType].max} ${imageType} images are allowed`);
    }
  }
  if (!counts.Screenshot) throw new Error(`${locale}: provide at least one Screenshot image`);
  return images;
}

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
    const description = fs.readFileSync(path.join(directory, entry.descriptionFile), 'utf8')
      .replace(/\r\n/g, '\n').trim();
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
    const features = description.split('\n')
      .filter((line) => line.startsWith('- ')).map((line) => line.slice(2).trim());
    if (features.length < 1 || features.length > 20 ||
        features.some((feature) => !feature || feature.length > 200)) {
      throw new Error(`${locale}: provide 1–20 features, each containing 1–200 characters`);
    }
    listings[locale] = {
      description, shortDescription, googlePlayLanguage: entry.googlePlayLanguage,
      features, images: loadMicrosoftImages(locale, directory, entry.microsoftStoreImages),
    };
  }
  for (const locale of requiredStoreLocales) {
    if (!listings[locale]) throw new Error(`Missing required Store listing: ${locale}`);
  }
  return listings;
}

export function loadStoreListings(directory = defaultListingsDirectory, { images = true } = {}) {
  return Object.fromEntries(Object.entries(loadListingContent(directory))
    .map(([locale, listing]) => [locale, {
      description: listing.description,
      features: listing.features,
      ...(images ? { images: listing.images } : {}),
    }]));
}

export function loadGooglePlayListings(directory = defaultListingsDirectory) {
  return Object.fromEntries(Object.values(loadListingContent(directory))
    .map(({ googlePlayLanguage, shortDescription, description }) =>
      [googlePlayLanguage, { shortDescription, fullDescription: description }]));
}

// Replace the listing's images of the managed types (the types present in the
// plan). Other image types stay. When the uploaded images already match the
// plan by content-addressed name and order, nothing is re-uploaded.
function planListingImages(existingImages, planned) {
  const managed = new Set(planned.map((image) => image.imageType));
  const current = existingImages.filter((image) =>
    managed.has(image.imageType) && image.fileStatus !== 'PendingDelete');
  const unchanged = current.length === planned.length && current.every((image, index) =>
    image.fileStatus === 'Uploaded' && image.fileName === planned[index].fileName &&
    image.imageType === planned[index].imageType);
  if (unchanged) {
    let next = 0;
    return {
      images: existingImages.map((image) =>
        current.includes(image) ? { ...image, description: planned[next++].description } : image),
      uploads: [],
    };
  }
  const images = [];
  for (const image of existingImages) {
    if (!managed.has(image.imageType)) images.push(image);
    // Images without an id were never processed (a failed earlier draft) and can be dropped.
    else if (image.id) images.push({ ...image, fileStatus: 'PendingDelete' });
  }
  for (const image of planned) {
    images.push({
      fileName: image.fileName,
      fileStatus: 'PendingUpload',
      imageType: image.imageType,
      description: image.description,
    });
  }
  return { images, uploads: planned };
}

// Update only repository-owned marketing content (description, features and,
// when provided, the managed image types); retain titles, other images,
// release notes, policy URLs, platform overrides and unrelated languages.
// Returns the new submission and the image files that must be in the upload ZIP.
export function applyStoreListings(submission, content) {
  const result = structuredClone(submission);
  result.listings ??= {};
  const fallback = result.listings['en-us']?.baseListing ??
    Object.values(result.listings).find((listing) => listing.baseListing?.title)?.baseListing;
  const uploads = [];
  for (const [locale, listing] of Object.entries(content)) {
    const existing = result.listings[locale];
    // A new language is seeded from existing metadata, without the other
    // language's images: Partner Center stores images per listing.
    const base = existing?.baseListing ?? (fallback && { ...structuredClone(fallback), images: [] });
    if (!base?.title) {
      throw new Error(`No existing Store title/metadata to seed ${locale}; prepare the initial listing in Partner Center first`);
    }
    const baseListing = {
      ...structuredClone(base),
      description: listing.description,
      features: [...listing.features],
    };
    if (listing.images) {
      const plan = planListingImages(baseListing.images ?? [], listing.images);
      baseListing.images = plan.images;
      uploads.push(...plan.uploads);
    }
    result.listings[locale] = { ...(existing ?? { platformOverrides: {} }), baseListing };
  }
  return { submission: result, uploads };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const directory = process.argv[2] || defaultListingsDirectory;
    const microsoft = loadStoreListings(directory);
    for (const listing of Object.values(microsoft)) {
      listing.images = listing.images.map(({ source, ...image }) => ({
        ...image, source: path.relative(process.cwd(), source).replaceAll('\\', '/'),
      }));
    }
    console.log(JSON.stringify({
      microsoft,
      googlePlay: loadGooglePlayListings(directory),
    }, null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
