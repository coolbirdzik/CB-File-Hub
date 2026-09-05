import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import 'disk_tree_node.dart';

/// One filesystem change reported by the NTFS USN Journal.
class DiskJournalChange {
  final int fileReferenceNumber;
  final int parentFileReferenceNumber;
  final String name;
  final int reason;
  final bool isDirectory;

  const DiskJournalChange({
    required this.fileReferenceNumber,
    required this.parentFileReferenceNumber,
    required this.name,
    required this.reason,
    required this.isDirectory,
  });
}

/// Result of reading the journal since a previous cursor.
class DiskJournalReadResult {
  final bool isUsable;
  final DiskScanJournalCursor? cursor;
  final List<DiskJournalChange> changes;
  final String? failureReason;

  const DiskJournalReadResult({
    required this.isUsable,
    this.cursor,
    this.changes = const <DiskJournalChange>[],
    this.failureReason,
  });
}

/// Reads the NTFS USN Journal without walking the volume's directory tree.
///
/// This class is deliberately synchronous because it runs inside the scan
/// isolate. A missing journal, a changed journal identity, or a retention gap
/// is reported as unusable so the caller can fall back to a complete scan.
class DiskUsnJournalReader {
  static const int _bufferBytes = 1024 * 1024;
  static const int _probeBufferBytes = 64 * 1024;
  static const int _maxChanges = 100000;

  const DiskUsnJournalReader._();

  static DiskJournalReadResult readChanges({
    required String drivePath,
    required DiskScanJournalCursor previous,
  }) {
    if (!Platform.isWindows) {
      return const DiskJournalReadResult(
        isUsable: false,
        failureReason: 'USN Journal is only available on Windows.',
      );
    }

    final volume = _openJournalVolume(drivePath);
    if (volume == null) {
      return const DiskJournalReadResult(
        isUsable: false,
        failureReason: 'Unable to open the volume for USN Journal access.',
      );
    }

    try {
      final journal = _queryJournal(volume);
      if (journal == null) {
        return const DiskJournalReadResult(
          isUsable: false,
          failureReason: 'The NTFS USN Journal is not active.',
        );
      }

      final currentCursor = journal.cursor;
      if (currentCursor.journalId != previous.journalId ||
          previous.nextUsn < journal.lowestValidUsn ||
          previous.nextUsn > currentCursor.nextUsn) {
        return const DiskJournalReadResult(
          isUsable: false,
          failureReason: 'The USN Journal cursor is no longer valid.',
        );
      }

      if (previous.nextUsn == currentCursor.nextUsn) {
        return DiskJournalReadResult(isUsable: true, cursor: currentCursor);
      }

      final changes = <DiskJournalChange>[];
      var startUsn = previous.nextUsn;
      final input = calloc<_ReadUsnJournalData>();
      final output = calloc<Uint8>(_bufferBytes);
      final bytesReturned = calloc<Uint32>();
      try {
        _initializeReadInput(
          input,
          startUsn: startUsn,
          journalId: currentCursor.journalId,
        );

        while (startUsn < currentCursor.nextUsn) {
          input.ref.startUsn = startUsn;
          bytesReturned.value = 0;
          final read = win32.DeviceIoControl(
            volume,
            win32.FSCTL_READ_USN_JOURNAL,
            input.cast(),
            sizeOf<_ReadUsnJournalData>(),
            output,
            _bufferBytes,
            bytesReturned,
            nullptr,
          );
          if (!read.value) {
            final error = read.error;
            if (error == win32.ERROR_HANDLE_EOF) break;
            return DiskJournalReadResult(
              isUsable: false,
              failureReason: 'USN Journal read failed with error $error.',
            );
          }

          final byteCount = bytesReturned.value;
          if (byteCount < 8) break;
          final bytes = output.asTypedList(byteCount);
          final data = ByteData.sublistView(bytes);
          final nextUsn = data.getInt64(0, Endian.little);
          _appendRecords(data, bytes, changes);
          if (changes.length > _maxChanges) {
            return const DiskJournalReadResult(
              isUsable: false,
              failureReason:
                  'Too many journal changes require a complete scan.',
            );
          }
          if (nextUsn <= startUsn) break;
          startUsn = nextUsn;
        }
      } finally {
        calloc.free(bytesReturned);
        calloc.free(output);
        calloc.free(input);
      }

      return DiskJournalReadResult(
        isUsable: true,
        cursor: currentCursor,
        changes: changes,
      );
    } finally {
      win32.CloseHandle(volume);
    }
  }

  /// Returns whether the raw NTFS journal can actually be read.
  ///
  /// Querying journal metadata through a directory handle is available to
  /// more Windows users than reading journal records through a raw volume
  /// handle. This probe performs one bounded, non-blocking read so callers do
  /// not mistake metadata access for incremental-scan capability.
  static bool canReadChanges(String drivePath) {
    if (!Platform.isWindows) return false;

    final volume = _openJournalVolume(drivePath);
    if (volume == null) return false;

    try {
      final journal = _queryJournal(volume);
      if (journal == null) return false;

      final input = calloc<_ReadUsnJournalData>();
      final output = calloc<Uint8>(_probeBufferBytes);
      final bytesReturned = calloc<Uint32>();
      try {
        _initializeReadInput(
          input,
          startUsn: journal.cursor.nextUsn,
          journalId: journal.cursor.journalId,
        );
        final ok = win32.DeviceIoControl(
          volume,
          win32.FSCTL_READ_USN_JOURNAL,
          input.cast(),
          sizeOf<_ReadUsnJournalData>(),
          output,
          _probeBufferBytes,
          bytesReturned,
          nullptr,
        ).value;
        return ok && bytesReturned.value >= sizeOf<Int64>();
      } finally {
        calloc.free(bytesReturned);
        calloc.free(output);
        calloc.free(input);
      }
    } finally {
      win32.CloseHandle(volume);
    }
  }

  static DiskScanJournalCursor? readCursor(String drivePath) {
    if (!Platform.isWindows) return null;
    final volume = _openMetadataRoot(drivePath);
    if (volume == null) return null;
    try {
      return _queryJournal(volume)?.cursor;
    } finally {
      win32.CloseHandle(volume);
    }
  }

  static int? readFileReferenceNumber(String path) {
    if (!Platform.isWindows) return null;
    final pathPointer = path.toNativeUtf16();
    final info = calloc<win32.BY_HANDLE_FILE_INFORMATION>();
    try {
      final handle = win32.CreateFile(
        win32.PCWSTR(pathPointer),
        win32.GENERIC_READ,
        win32.FILE_SHARE_READ |
            win32.FILE_SHARE_WRITE |
            win32.FILE_SHARE_DELETE,
        null,
        win32.OPEN_EXISTING,
        win32.FILE_FLAG_BACKUP_SEMANTICS,
        null,
      ).value;
      if (!handle.isValid) return null;
      try {
        if (!win32.GetFileInformationByHandle(handle, info).value) return null;
        return (info.ref.nFileIndexHigh << 32) |
            (info.ref.nFileIndexLow & 0xffffffff);
      } finally {
        win32.CloseHandle(handle);
      }
    } finally {
      calloc.free(info);
      calloc.free(pathPointer);
    }
  }

  static win32.HANDLE? _openMetadataRoot(String drivePath) {
    final root = drivePath.trim();
    if (root.length < 2 || root[1] != ':') return null;
    // A root-directory handle is sufficient for the metadata query and avoids
    // requiring raw-volume access from normal Windows accounts.
    final rootPath = '${root.substring(0, 2)}\\';
    final pathPointer = rootPath.toNativeUtf16();
    try {
      final handle = win32.CreateFile(
        win32.PCWSTR(pathPointer),
        win32.GENERIC_READ,
        win32.FILE_SHARE_READ |
            win32.FILE_SHARE_WRITE |
            win32.FILE_SHARE_DELETE,
        null,
        win32.OPEN_EXISTING,
        win32.FILE_FLAG_BACKUP_SEMANTICS,
        null,
      ).value;
      return handle.isValid ? handle : null;
    } finally {
      calloc.free(pathPointer);
    }
  }

  static win32.HANDLE? _openJournalVolume(String drivePath) {
    final root = drivePath.trim();
    if (root.length < 2 || root[1] != ':') return null;
    final volumePath = '\\\\.\\${root.substring(0, 2)}';
    final pathPointer = volumePath.toNativeUtf16();
    try {
      final handle = win32.CreateFile(
        win32.PCWSTR(pathPointer),
        win32.GENERIC_READ,
        win32.FILE_SHARE_READ |
            win32.FILE_SHARE_WRITE |
            win32.FILE_SHARE_DELETE,
        null,
        win32.OPEN_EXISTING,
        const win32.FILE_FLAGS_AND_ATTRIBUTES(0),
        null,
      ).value;
      return handle.isValid ? handle : null;
    } finally {
      calloc.free(pathPointer);
    }
  }

  static void _initializeReadInput(
    Pointer<_ReadUsnJournalData> input, {
    required int startUsn,
    required int journalId,
  }) {
    input.ref.startUsn = startUsn;
    input.ref.reasonMask = 0xffffffff;
    input.ref.returnOnlyOnClose = 0;
    input.ref.timeout = 0;
    input.ref.bytesToWaitFor = 0;
    input.ref.usnJournalId = journalId;
    input.ref.minMajorVersion = 2;
    // The parser below handles USN_RECORD_V2's 64-bit file identifiers.
    input.ref.maxMajorVersion = 2;
  }

  static _JournalQuery? _queryJournal(win32.HANDLE volume) {
    final data = calloc<_UsnJournalData>();
    final bytesReturned = calloc<Uint32>();
    try {
      final ok = win32.DeviceIoControl(
        volume,
        win32.FSCTL_QUERY_USN_JOURNAL,
        nullptr,
        0,
        data.cast(),
        sizeOf<_UsnJournalData>(),
        bytesReturned,
        nullptr,
      ).value;
      if (!ok || bytesReturned.value < sizeOf<_UsnJournalData>()) {
        return null;
      }
      return _JournalQuery(
        cursor: DiskScanJournalCursor(
          journalId: data.ref.usnJournalId,
          nextUsn: data.ref.nextUsn,
        ),
        lowestValidUsn: data.ref.lowestValidUsn,
      );
    } finally {
      calloc.free(bytesReturned);
      calloc.free(data);
    }
  }

  static void _appendRecords(
    ByteData data,
    Uint8List bytes,
    List<DiskJournalChange> changes,
  ) {
    var offset = 8;
    while (offset + 60 <= bytes.length) {
      final recordLength = data.getUint32(offset, Endian.little);
      if (recordLength < 60 || offset + recordLength > bytes.length) break;
      final majorVersion = data.getUint16(offset + 4, Endian.little);
      if (majorVersion == 2) {
        final fileReferenceNumber = data.getUint64(offset + 8, Endian.little);
        final parentFileReferenceNumber = data.getUint64(
          offset + 16,
          Endian.little,
        );
        final reason = data.getUint32(offset + 40, Endian.little);
        final fileAttributes = data.getUint32(offset + 52, Endian.little);
        final fileNameLength = data.getUint16(offset + 56, Endian.little);
        final fileNameOffset = data.getUint16(offset + 58, Endian.little);
        if (fileNameOffset + fileNameLength <= recordLength) {
          changes.add(
            DiskJournalChange(
              fileReferenceNumber: fileReferenceNumber,
              parentFileReferenceNumber: parentFileReferenceNumber,
              name: _decodeFileName(
                bytes,
                offset + fileNameOffset,
                fileNameLength,
              ),
              reason: reason,
              isDirectory: fileAttributes & win32.FILE_ATTRIBUTE_DIRECTORY != 0,
            ),
          );
        }
      }
      offset += recordLength;
    }
  }

  static String _decodeFileName(Uint8List bytes, int offset, int length) {
    final codeUnits = <int>[];
    for (var index = offset; index + 1 < offset + length; index += 2) {
      codeUnits.add(bytes[index] | (bytes[index + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }
}

class _JournalQuery {
  final DiskScanJournalCursor cursor;
  final int lowestValidUsn;

  const _JournalQuery({required this.cursor, required this.lowestValidUsn});
}

base class _UsnJournalData extends Struct {
  @Uint64()
  external int usnJournalId;

  @Int64()
  external int firstUsn;

  @Int64()
  external int nextUsn;

  @Int64()
  external int lowestValidUsn;

  @Int64()
  external int maxUsn;

  @Uint64()
  external int maximumSize;

  @Uint64()
  external int allocationDelta;
}

base class _ReadUsnJournalData extends Struct {
  @Int64()
  external int startUsn;

  @Uint32()
  external int reasonMask;

  @Uint32()
  external int returnOnlyOnClose;

  @Uint64()
  external int timeout;

  @Uint64()
  external int bytesToWaitFor;

  @Uint64()
  external int usnJournalId;

  @Uint16()
  external int minMajorVersion;

  @Uint16()
  external int maxMajorVersion;
}
