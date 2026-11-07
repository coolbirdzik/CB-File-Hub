import 'package:path/path.dart' as p;

/// Infer filesystem syntax from the actual home, independently of the app
/// layout being analyzed. Windows also accepts `/tmp/...` as absolute, so
/// checking windows.isAbsolute first misclassifies real POSIX homes.
p.Context storagePathContext(String home) {
  if (home.startsWith(r'\\') || home.startsWith('//')) return p.windows;
  if (p.posix.isAbsolute(home)) return p.posix;
  return p.windows.isAbsolute(home) ? p.windows : p.posix;
}
