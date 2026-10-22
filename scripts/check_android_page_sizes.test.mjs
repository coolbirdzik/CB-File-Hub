import assert from 'node:assert/strict';
import test from 'node:test';
import { deflateRawSync } from 'node:zlib';
import { checkArtifact, checkElf } from './check_android_page_sizes.mjs';

function elf({ is64 = true, alignment = 16384, offset = 0, address = 0 } = {}) {
  const header = is64 ? 64 : 52;
  const bytes = Buffer.alloc(header + (is64 ? 56 : 32));
  bytes.writeUInt32LE(0x464c457f);
  bytes[4] = is64 ? 2 : 1;
  bytes[5] = 1;
  if (is64) {
    bytes.writeBigUInt64LE(BigInt(header), 32);
    bytes.writeUInt16LE(56, 54);
    bytes.writeUInt16LE(1, 56);
    bytes.writeBigUInt64LE(BigInt(offset), header + 8);
    bytes.writeBigUInt64LE(BigInt(address), header + 16);
    bytes.writeBigUInt64LE(BigInt(alignment), header + 48);
  } else {
    bytes.writeUInt32LE(header, 28);
    bytes.writeUInt16LE(32, 42);
    bytes.writeUInt16LE(1, 44);
    bytes.writeUInt32LE(offset, header + 4);
    bytes.writeUInt32LE(address, header + 8);
    bytes.writeUInt32LE(alignment, header + 28);
  }
  bytes.writeUInt32LE(1, header);
  return bytes;
}

// Minimal ZIP fixture: local entry, central directory, end record. CRC is
// irrelevant to the ELF/offset checks; the payload is valid deflate data.
function zipEntry(name, bytes, { compressed = false, aligned = false } = {}) {
  const filename = Buffer.from(name);
  const payload = compressed ? deflateRawSync(bytes) : bytes;
  const extra = aligned ? (16384 - (30 + filename.length) % 16384) % 16384 : 0;
  const local = Buffer.alloc(30 + filename.length + extra);
  local.writeUInt32LE(0x04034b50);
  local.writeUInt16LE(compressed ? 8 : 0, 8);
  local.writeUInt32LE(payload.length, 18);
  local.writeUInt32LE(bytes.length, 22);
  local.writeUInt16LE(filename.length, 26);
  local.writeUInt16LE(extra, 28);
  filename.copy(local, 30);
  const central = Buffer.alloc(46 + filename.length);
  central.writeUInt32LE(0x02014b50);
  central.writeUInt16LE(compressed ? 8 : 0, 10);
  central.writeUInt32LE(payload.length, 20);
  central.writeUInt32LE(bytes.length, 24);
  central.writeUInt16LE(filename.length, 28);
  filename.copy(central, 46);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(local.length + payload.length, 16);
  return Buffer.concat([local, payload, central, end]);
}

test('accepts 16 KB and 64 KB LOAD alignment', () => {
  assert.deepEqual(checkElf(elf()), []);
  assert.deepEqual(checkElf(elf({ alignment: 65536 })), []);
});

test('rejects 4 KB ELF32 Hexagon blobs inside the arm64 AAB directory', () => {
  const zip = zipEntry('base/lib/arm64-v8a/libQnnHtpV73Skel.so',
    elf({ is64: false, alignment: 4096 }), { compressed: true });
  const result = checkArtifact(zip);
  assert.equal(result.checked, 1);
  assert.match(result.failures[0], /libQnnHtpV73Skel.so.*p_align=4096/);
});

test('checks x86_64 libraries and segment offset congruence', () => {
  const result = checkArtifact(zipEntry('lib/x86_64/libcb_native.so', elf({ offset: 4096 })));
  assert.match(result.failures[0], /differ modulo 16384/);
});

test('checks ZIP mapping alignment only for uncompressed APK libraries', () => {
  const name = 'lib/arm64-v8a/libflutter.so';
  assert.equal(checkArtifact(zipEntry(name, elf())).failures.length, 0);
  assert.match(checkArtifact(zipEntry(name, elf()), { apk: true }).failures[0], /ZIP data offset/);
  assert.equal(checkArtifact(zipEntry(name, elf(), { aligned: true }), { apk: true }).failures.length, 0);
  assert.equal(checkArtifact(zipEntry(name, elf(), { compressed: true }), { apk: true }).failures.length, 0);
});

test('rejects malformed artifacts and missing 64-bit native libraries', () => {
  assert.throws(() => checkArtifact(Buffer.alloc(0)), /ZIP end record/);
  assert.throws(() => checkElf(Buffer.alloc(60)), /not an ELF/);
  assert.throws(() => checkArtifact(zipEntry('assets/empty', Buffer.alloc(0))), /no 64-bit/);
});
