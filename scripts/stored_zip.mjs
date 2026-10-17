import fs from 'node:fs';
import zlib from 'node:zlib';

// Minimal ZIP writer for Partner Center submission archives. Entries are
// stored uncompressed: MSIX packages and PNG images are already compressed.
// No ZIP64 support, so the archive must stay below 4 GB.

const chunkSize = 1024 * 1024;
const maxZip32 = 0xffffffff;
const dosDate = (1 << 5) | 1; // 1980-01-01, keeps archives reproducible.

function crc32File(filePath) {
  if (typeof zlib.crc32 !== 'function') {
    throw new Error('Node.js 22.2 or newer is required (zlib.crc32)');
  }
  const fd = fs.openSync(filePath, 'r');
  try {
    const buffer = Buffer.allocUnsafe(chunkSize);
    let crc = 0;
    let bytesRead;
    while ((bytesRead = fs.readSync(fd, buffer, 0, chunkSize, null)) > 0) {
      crc = zlib.crc32(buffer.subarray(0, bytesRead), crc);
    }
    return crc;
  } finally {
    fs.closeSync(fd);
  }
}

function copyInto(outFd, filePath) {
  const inFd = fs.openSync(filePath, 'r');
  try {
    const buffer = Buffer.allocUnsafe(chunkSize);
    let bytesRead;
    while ((bytesRead = fs.readSync(inFd, buffer, 0, chunkSize, null)) > 0) {
      fs.writeSync(outFd, buffer, 0, bytesRead);
    }
  } finally {
    fs.closeSync(inFd);
  }
}

/**
 * Writes `entries` ([{ name, source }]) to a new ZIP archive at `zipPath`.
 * Names are archive-relative; duplicates are rejected.
 */
export function writeStoredZip(zipPath, entries) {
  const names = new Set();
  const central = [];
  let offset = 0;
  const outFd = fs.openSync(zipPath, 'w');
  try {
    for (const { name, source } of entries) {
      if (!name || names.has(name)) throw new Error(`Invalid or duplicate ZIP entry name: ${name}`);
      names.add(name);
      const nameBytes = Buffer.from(name, 'utf8');
      const size = fs.statSync(source).size;
      const crc = crc32File(source);
      if (size > maxZip32 || offset > maxZip32) throw new Error('ZIP archive exceeds 4 GB');

      const local = Buffer.alloc(30);
      local.writeUInt32LE(0x04034b50, 0);
      local.writeUInt16LE(20, 4); // version needed
      local.writeUInt16LE(0x0800, 6); // UTF-8 names
      local.writeUInt16LE(0, 8); // stored
      local.writeUInt16LE(0, 10);
      local.writeUInt16LE(dosDate, 12);
      local.writeUInt32LE(crc, 14);
      local.writeUInt32LE(size, 18);
      local.writeUInt32LE(size, 22);
      local.writeUInt16LE(nameBytes.length, 26);
      local.writeUInt16LE(0, 28);
      fs.writeSync(outFd, local);
      fs.writeSync(outFd, nameBytes);
      copyInto(outFd, source);

      const header = Buffer.alloc(46);
      header.writeUInt32LE(0x02014b50, 0);
      header.writeUInt16LE(20, 4); // version made by
      header.writeUInt16LE(20, 6); // version needed
      header.writeUInt16LE(0x0800, 8);
      header.writeUInt16LE(0, 10);
      header.writeUInt16LE(0, 12);
      header.writeUInt16LE(dosDate, 14);
      header.writeUInt32LE(crc, 16);
      header.writeUInt32LE(size, 20);
      header.writeUInt32LE(size, 24);
      header.writeUInt16LE(nameBytes.length, 28);
      header.writeUInt32LE(offset, 42);
      central.push(header, nameBytes);
      offset += local.length + nameBytes.length + size;
    }
    const directory = Buffer.concat(central);
    if (offset + directory.length > maxZip32) throw new Error('ZIP archive exceeds 4 GB');
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(entries.length, 8);
    end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(directory.length, 12);
    end.writeUInt32LE(offset, 16);
    fs.writeSync(outFd, directory);
    fs.writeSync(outFd, end);
  } finally {
    fs.closeSync(outFd);
  }
}
