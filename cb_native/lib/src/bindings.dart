// FFI declarations for rust/src/lib.rs. Keep in sync with its ABI_VERSION.
@DefaultAsset('package:cb_native/cb_native')
library;

import 'dart:ffi';

const int expectedAbiVersion = 6;

const int statusOk = 0;
const int statusInvalidArgument = 1;
const int statusInvalidRegex = 2;

const int kindDirectory = 1;
const int kindFile = 2;
const int kindLink = 3;

final class SearchHandle extends Opaque {}

@Native<Uint32 Function()>(isLeaf: true)
external int cb_native_abi_version();

@Native<Void Function(Pointer<Uint8>, Size)>(isLeaf: true)
external void cb_buffer_free(Pointer<Uint8> ptr, int len);

@Native<
  Int32 Function(Pointer<Uint8>, Size, Pointer<Pointer<Uint8>>, Pointer<Size>)
>(isLeaf: true)
external int cb_search_key(
  Pointer<Uint8> ptr,
  int len,
  Pointer<Pointer<Uint8>> outPtr,
  Pointer<Size> outLen,
);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<SearchHandle>>,
  )
>()
external int cb_search_start(
  Pointer<Uint8> rootPtr,
  int rootLen,
  Pointer<Uint8> wordsPtr,
  int wordsLen,
  Pointer<Uint8> regexPtr,
  int regexLen,
  Pointer<Pointer<SearchHandle>> outHandle,
);

@Native<
  Int32 Function(Pointer<SearchHandle>, Pointer<Pointer<Uint8>>, Pointer<Size>)
>(isLeaf: true)
external int cb_search_poll(
  Pointer<SearchHandle> handle,
  Pointer<Pointer<Uint8>> outPtr,
  Pointer<Size> outLen,
);

@Native<Void Function(Pointer<SearchHandle>)>(isLeaf: true)
external void cb_search_cancel(Pointer<SearchHandle> handle);

// Untyped so its address can back a NativeFinalizer.
@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void cb_search_free(Pointer<Void> handle);

final class DiskScanHandle extends Opaque {}

@Native<
  Int32 Function(Pointer<Uint8>, Size, Pointer<Pointer<DiskScanHandle>>)
>()
external int cb_disk_scan_start(
  Pointer<Uint8> configPtr,
  int configLen,
  Pointer<Pointer<DiskScanHandle>> outHandle,
);

@Native<
  Int32 Function(
    Pointer<DiskScanHandle>,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(isLeaf: true)
external int cb_disk_scan_poll(
  Pointer<DiskScanHandle> handle,
  Pointer<Pointer<Uint8>> outPtr,
  Pointer<Size> outLen,
);

@Native<
  Void Function(
    Pointer<DiskScanHandle>,
    Pointer<Uint64>,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(isLeaf: true)
external void cb_disk_scan_progress(
  Pointer<DiskScanHandle> handle,
  Pointer<Uint64> outCounts,
  Pointer<Pointer<Uint8>> outPathPtr,
  Pointer<Size> outPathLen,
);

@Native<Void Function(Pointer<DiskScanHandle>)>(isLeaf: true)
external void cb_disk_scan_cancel(Pointer<DiskScanHandle> handle);

// Untyped so its address can back a NativeFinalizer.
@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void cb_disk_scan_free(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Void>)>(isLeaf: true)
external int cb_native_init_dart_api(Pointer<Void> data);

@Native<Pointer<Uint8> Function(Size)>(isLeaf: true)
external Pointer<Uint8> cb_buffer_alloc(int len);

// `cb_job_start` kinds (lib.rs).
const int jobDirSize = 1;
const int jobWalk = 2;
const int jobJunkScan = 3;
const int jobListDir = 4;
const int jobThumbnail = 5;
const int jobEncodeImage = 6;
const int jobInpaint = 7;
const int jobHashFile = 8;
const int jobArchiveList = 9;
const int jobArchiveExtract = 10;
const int jobSortPaths = 11;
const int jobContentSearch = 12;
const int jobDocumentText = 13;
const int jobImageDimensions = 14;
const int jobImageTranscode = 15;
const int jobExistsBatch = 16;
const int jobCreateZip = 17;
const int jobReadZipEntry = 18;
const int jobUsnParents = 19;
const int jobRecycleBin = 20;
const int jobTorrentMetainfo = 21;
const int jobCachePlan = 22;
const int jobPathSuggestions = 23;
const int jobChildCounts = 24;
const int jobSmartAlbum = 25;
const int jobArchiveChildren = 26;
const int jobSyntax = 27;
const int jobPermanentDelete = 28;

// Job states (job.rs).
const int jobRunning = 0;
const int jobDone = 1;
const int jobFailed = 2;
const int jobCancelled = 3;

final class JobHandle extends Opaque {}

@Native<
  Int32 Function(
    Uint32,
    Pointer<Uint8>,
    Size,
    Int64,
    Pointer<Pointer<JobHandle>>,
  )
>()
external int cb_job_start(
  int kind,
  Pointer<Uint8> configPtr,
  int configLen,
  int port,
  Pointer<Pointer<JobHandle>> outHandle,
);

@Native<
  Int32 Function(Pointer<JobHandle>, Pointer<Pointer<Uint8>>, Pointer<Size>)
>(isLeaf: true)
external int cb_job_poll(
  Pointer<JobHandle> handle,
  Pointer<Pointer<Uint8>> outPtr,
  Pointer<Size> outLen,
);

@Native<
  Void Function(Pointer<JobHandle>, Pointer<Pointer<Uint8>>, Pointer<Size>)
>(isLeaf: true)
external void cb_job_error(
  Pointer<JobHandle> handle,
  Pointer<Pointer<Uint8>> outPtr,
  Pointer<Size> outLen,
);

@Native<
  Void Function(
    Pointer<JobHandle>,
    Pointer<Uint64>,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(isLeaf: true)
external void cb_job_progress(
  Pointer<JobHandle> handle,
  Pointer<Uint64> outCounts,
  Pointer<Pointer<Uint8>> outPathPtr,
  Pointer<Size> outPathLen,
);

@Native<Void Function(Pointer<JobHandle>)>(isLeaf: true)
external void cb_job_cancel(Pointer<JobHandle> handle);

// Untyped so its address can back a NativeFinalizer.
@Native<Void Function(Pointer<Void>)>(isLeaf: true)
external void cb_job_free(Pointer<Void> handle);
