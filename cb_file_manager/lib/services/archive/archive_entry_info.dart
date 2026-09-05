import 'package:equatable/equatable.dart';

/// Metadata for one member inside an archive (no file bytes loaded).
class ArchiveEntryInfo extends Equatable {
  final String name;
  final int size;
  final int compressedSize;
  final bool isDirectory;
  final DateTime? modified;

  const ArchiveEntryInfo({
    required this.name,
    required this.size,
    this.compressedSize = 0,
    this.isDirectory = false,
    this.modified,
  });

  @override
  List<Object?> get props => [
    name,
    size,
    compressedSize,
    isDirectory,
    modified,
  ];
}
