/// One physical filename per DLL, matching the native PE import tables.
/// Native Assets IDs retain their upstream names; only their file changes.
const windowsCanonicalLibraryNames = <String, String>{
  'GemmaModelConstraintProvider': 'libGemmaModelConstraintProvider',
  'LiteRt': 'libLiteRt',
  'LiteRtTopKWebGpuSampler': 'libLiteRtTopKWebGpuSampler',
  'LiteRtWebGpuAccelerator': 'libLiteRtWebGpuAccelerator',
  // The WebGPU sampler/accelerator import Dawn WITHOUT the lib prefix.
  'libwebgpu_dawn': 'webgpu_dawn',
};

String canonicalWindowsLibraryFileName(String fileName) {
  final name = fileName.endsWith('.dll')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;
  return '${windowsCanonicalLibraryNames[name] ?? name}.dll';
}
