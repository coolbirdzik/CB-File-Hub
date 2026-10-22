#!/usr/bin/env node
// Check the actual release artifact, including DSP blobs placed under lib/.
// No external packages or Android SDK tools are required.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { inflateRawSync } from 'node:zlib';

const pageSize = 16384;

export function checkElf(bytes) {
  if (bytes.length < 52 || bytes.readUInt32LE(0) !== 0x464c457f) {
    throw new Error('not an ELF library');
  }
  if (bytes[5] !== 1 || ![1, 2].includes(bytes[4])) {
    throw new Error('unsupported ELF encoding');
  }
  const is64 = bytes[4] === 2;
  const integer = (offset) => is64
    ? Number(bytes.readBigUInt64LE(offset)) : bytes.readUInt32LE(offset);
  const table = integer(is64 ? 32 : 28);
  const stride = bytes.readUInt16LE(is64 ? 54 : 42);
  const count = bytes.readUInt16LE(is64 ? 56 : 44);
  if (stride < (is64 ? 56 : 32) || table + count * stride > bytes.length) {
    throw new Error('invalid ELF program headers');
  }
  const errors = [];
  let loads = 0;
  for (let i = 0; i < count; i++) {
    const header = table + i * stride;
    if (bytes.readUInt32LE(header) !== 1) continue; // PT_LOAD
    loads++;
    const alignment = integer(header + (is64 ? 48 : 28));
    const offset = integer(header + (is64 ? 8 : 4));
    const address = integer(header + (is64 ? 16 : 8));
    if (alignment < pageSize || !Number.isInteger(Math.log2(alignment))) {
      errors.push(`LOAD ${i}: p_align=${alignment}, expected a power of two >= ${pageSize}`);
    }
    if (offset % pageSize !== address % pageSize) {
      errors.push(`LOAD ${i}: file offset and virtual address differ modulo ${pageSize}`);
    }
  }
  if (!loads) throw new Error('ELF has no LOAD segments');
  return errors;
}

export function checkArtifact(zip, { apk = false } = {}) {
  // Read ZIP's central directory; AAB and APK both use this format. Reject
  // ZIP64 explicitly rather than silently missing native libraries.
  let end = -1;
  for (let i = zip.length - 22; i >= Math.max(0, zip.length - 65557); i--) {
    if (zip.readUInt32LE(i) === 0x06054b50 &&
        i + 22 + zip.readUInt16LE(i + 20) === zip.length) {
      end = i;
      break;
    }
  }
  if (end < 0) throw new Error('ZIP end record not found');
  const count = zip.readUInt16LE(end + 10);
  let cursor = zip.readUInt32LE(end + 16);
  if (count === 0xffff || cursor === 0xffffffff) {
    throw new Error('ZIP64 is unsupported; inspect with Android SDK tools');
  }
  const failures = [];
  let checked = 0;
  for (let i = 0; i < count; i++) {
    if (zip.readUInt32LE(cursor) !== 0x02014b50) throw new Error('invalid ZIP directory');
    const method = zip.readUInt16LE(cursor + 10);
    const size = zip.readUInt32LE(cursor + 20);
    const nameSize = zip.readUInt16LE(cursor + 28);
    const name = zip.toString('utf8', cursor + 46, cursor + 46 + nameSize);
    const local = zip.readUInt32LE(cursor + 42);
    cursor += 46 + nameSize + zip.readUInt16LE(cursor + 30) + zip.readUInt16LE(cursor + 32);
    // Include ELF32 Hexagon images shipped in arm64-v8a. Play checks those
    // too, although Android's ARM64 loader never loads them itself.
    if (!/(^|\/)lib\/(arm64-v8a|x86_64)\/[^/]+\.so$/.test(name)) continue;
    checked++;
    if (size === 0xffffffff || local === 0xffffffff) throw new Error('ZIP64 native entry');
    if (zip.readUInt32LE(local) !== 0x04034b50) throw new Error(`invalid ZIP entry: ${name}`);
    const data = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
    const compressed = zip.subarray(data, data + size);
    let bytes;
    if (method === 0) bytes = compressed;
    else if (method === 8) bytes = inflateRawSync(compressed);
    else throw new Error(`unsupported ZIP compression: ${name}`);
    for (const error of checkElf(bytes)) failures.push(`${name}: ${error}`);
    // AAB entries are not APK mappings. Only uncompressed APK libraries
    // need their ZIP data offset to be on a 16 KB boundary.
    if (apk && method === 0 && data % pageSize !== 0) {
      failures.push(`${name}: APK ZIP data offset ${data} is not 16 KB aligned`);
    }
  }
  if (!checked) throw new Error('no 64-bit Android native libraries found');
  return { checked, failures };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const artifacts = process.argv.slice(2);
  if (!artifacts.length) {
    console.error('Usage: node scripts/check_android_page_sizes.mjs <app.aab|app.apk> [...]');
    process.exitCode = 1;
  }
  for (const artifact of artifacts) {
    try {
      if (!/\.(aab|apk)$/i.test(artifact)) throw new Error('expected .aab or .apk');
      const { checked, failures } = checkArtifact(readFileSync(artifact), { apk: /\.apk$/i.test(artifact) });
      if (failures.length) {
        console.error(`${artifact}: FAIL\n${failures.join('\n')}`);
        process.exitCode = 1;
      } else {
        console.log(`${artifact}: PASS (${checked} native libraries, 16 KB alignment)`);
      }
    } catch (error) {
      console.error(`${artifact}: ${error.message}`);
      process.exitCode = 1;
    }
  }
}
