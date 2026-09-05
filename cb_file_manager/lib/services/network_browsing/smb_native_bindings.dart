import 'dart:ffi';

import 'package:ffi/ffi.dart';

// --- C Structs definitions for Dart ---

base class NativeFileInfo extends Struct {
  external Pointer<Utf16> name;
  @Int64()
  external int size;
  @Int64()
  external int modificationTime;
  @Bool()
  external bool isDirectory;
}

base class NativeFileList extends Struct {
  @Int32()
  external int count;
  external Pointer<NativeFileInfo> files;
}

base class NativeShareInfo extends Struct {
  external Pointer<Utf16> name;
  external Pointer<Utf16> comment;
  @Int32()
  external int type;
}

base class NativeShareList extends Struct {
  @Int32()
  external int count;
  external Pointer<NativeShareInfo> shares;
}

base class ReadResult extends Struct {
  @Int64()
  external int bytesRead;
  external Pointer<Uint8> data;
}

base class ThumbnailResult extends Struct {
  external Pointer<Uint8> data;
  @Int32()
  external int size;
}

// --- FFI Function Signatures ---

// Connection
typedef ConnectNative =
    Int32 Function(
      Pointer<Utf16> path,
      Pointer<Utf16> username,
      Pointer<Utf16> password,
    );
typedef ConnectDart =
    int Function(
      Pointer<Utf16> path,
      Pointer<Utf16> username,
      Pointer<Utf16> password,
    );
typedef DisconnectNative = Int32 Function(Pointer<Utf16> path);
typedef DisconnectDart = int Function(Pointer<Utf16> path);

// File Operations
typedef ListDirectoryNative =
    Pointer<NativeFileList> Function(Pointer<Utf16> path);
typedef ListDirectoryDart =
    Pointer<NativeFileList> Function(Pointer<Utf16> path);
typedef EnumerateSharesNative =
    Pointer<NativeShareList> Function(Pointer<Utf16> server);
typedef EnumerateSharesDart =
    Pointer<NativeShareList> Function(Pointer<Utf16> server);
typedef DeleteFileOrDirNative = Bool Function(Pointer<Utf16> path);
typedef DeleteFileOrDirDart = bool Function(Pointer<Utf16> path);
typedef CreateDirNative = Bool Function(Pointer<Utf16> path);
typedef CreateDirDart = bool Function(Pointer<Utf16> path);
typedef RenameNative =
    Bool Function(Pointer<Utf16> oldPath, Pointer<Utf16> newPath);
typedef RenameDart =
    bool Function(Pointer<Utf16> oldPath, Pointer<Utf16> newPath);

// File I/O
typedef OpenFileForReadingNative = IntPtr Function(Pointer<Utf16> path);
typedef OpenFileForReadingDart = int Function(Pointer<Utf16> path);
typedef CreateFileForWritingNative = IntPtr Function(Pointer<Utf16> path);
typedef CreateFileForWritingDart = int Function(Pointer<Utf16> path);
typedef ReadFileChunkNative =
    ReadResult Function(IntPtr handle, Int64 chunkSize);
typedef ReadFileChunkDart = ReadResult Function(int handle, int chunkSize);
typedef WriteFileChunkNative =
    Bool Function(IntPtr handle, Pointer<Uint8> data, Int32 length);
typedef WriteFileChunkDart =
    bool Function(int handle, Pointer<Uint8> data, int length);
typedef CloseFileNative = Void Function(IntPtr handle);
typedef CloseFileDart = void Function(int handle);

// Thumbnail
typedef GetThumbnailNative =
    ThumbnailResult Function(Pointer<Utf16> path, Int32 size);
typedef GetThumbnailDart =
    ThumbnailResult Function(Pointer<Utf16> path, int size);

// Memory Management
typedef FreeFileListNative = Void Function(Pointer<NativeFileList> list);
typedef FreeFileListDart = void Function(Pointer<NativeFileList> list);
typedef FreeShareListNative = Void Function(Pointer<NativeShareList> list);
typedef FreeShareListDart = void Function(Pointer<NativeShareList> list);
typedef FreeReadResultDataNative = Void Function(Pointer<Uint8> data);
typedef FreeReadResultDataDart = void Function(Pointer<Uint8> data);
typedef FreeThumbnailResultNative = Void Function(ThumbnailResult result);
typedef FreeThumbnailResultDart = void Function(ThumbnailResult result);

/// A class that provides a high-level Dart interface to the native SMB functions.
class SMBNativeBindings {
  late final DynamicLibrary _lib;

  // Function lookups
  late final ConnectDart connect;
  late final DisconnectDart disconnect;
  late final ListDirectoryDart listDirectory;
  late final EnumerateSharesDart enumerateShares;
  late final DeleteFileOrDirDart deleteFileOrDir;
  late final CreateDirDart createDir;
  late final RenameDart rename;
  late final OpenFileForReadingDart openFileForReading;
  late final CreateFileForWritingDart createFileForWriting;
  late final ReadFileChunkDart readFileChunk;
  late final WriteFileChunkDart writeFileChunk;
  late final CloseFileDart closeFile;
  late final GetThumbnailDart getThumbnail;
  late final FreeFileListDart freeFileList;
  late final FreeShareListDart freeShareList;
  late final FreeReadResultDataDart freeReadResultData;
  late final FreeThumbnailResultDart freeThumbnailResult;

  SMBNativeBindings() {
    _lib = DynamicLibrary.open('smb_native.dll');

    // Look up the functions
    connect = _lib
        .lookup<NativeFunction<ConnectNative>>('Connect')
        .asFunction<ConnectDart>();
    disconnect = _lib
        .lookup<NativeFunction<DisconnectNative>>('Disconnect')
        .asFunction<DisconnectDart>();
    listDirectory = _lib
        .lookup<NativeFunction<ListDirectoryNative>>('ListDirectory')
        .asFunction<ListDirectoryDart>();
    enumerateShares = _lib
        .lookup<NativeFunction<EnumerateSharesNative>>('EnumerateShares')
        .asFunction<EnumerateSharesDart>();
    deleteFileOrDir = _lib
        .lookup<NativeFunction<DeleteFileOrDirNative>>('DeleteFileOrDir')
        .asFunction<DeleteFileOrDirDart>();
    createDir = _lib
        .lookup<NativeFunction<CreateDirNative>>('CreateDir')
        .asFunction<CreateDirDart>();
    rename = _lib
        .lookup<NativeFunction<RenameNative>>('Rename')
        .asFunction<RenameDart>();
    openFileForReading = _lib
        .lookup<NativeFunction<OpenFileForReadingNative>>('OpenFileForReading')
        .asFunction<OpenFileForReadingDart>();
    createFileForWriting = _lib
        .lookup<NativeFunction<CreateFileForWritingNative>>(
          'CreateFileForWriting',
        )
        .asFunction<CreateFileForWritingDart>();
    readFileChunk = _lib
        .lookup<NativeFunction<ReadFileChunkNative>>('ReadFileChunk')
        .asFunction<ReadFileChunkDart>();
    writeFileChunk = _lib
        .lookup<NativeFunction<WriteFileChunkNative>>('WriteFileChunk')
        .asFunction<WriteFileChunkDart>();
    closeFile = _lib
        .lookup<NativeFunction<CloseFileNative>>('CloseFile')
        .asFunction<CloseFileDart>();
    getThumbnail = _lib
        .lookup<NativeFunction<GetThumbnailNative>>('GetThumbnail')
        .asFunction<GetThumbnailDart>();
    freeFileList = _lib
        .lookup<NativeFunction<FreeFileListNative>>('FreeFileList')
        .asFunction<FreeFileListDart>();
    freeShareList = _lib
        .lookup<NativeFunction<FreeShareListNative>>('FreeShareList')
        .asFunction<FreeShareListDart>();
    freeReadResultData = _lib
        .lookup<NativeFunction<FreeReadResultDataNative>>('FreeReadResultData')
        .asFunction<FreeReadResultDataDart>();
    freeThumbnailResult = _lib
        .lookup<NativeFunction<FreeThumbnailResultNative>>(
          'FreeThumbnailResult',
        )
        .asFunction<FreeThumbnailResultDart>();
  }
}
