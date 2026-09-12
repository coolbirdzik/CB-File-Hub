/// Invalidates older asynchronous search work on edits, refresh, or disposal.
class SearchRequestGuard {
  int _revision = 0;
  bool _disposed = false;

  int begin() => ++_revision;
  void invalidate() => _revision++;
  bool isCurrent(int revision) => !_disposed && revision == _revision;
  void dispose() {
    _disposed = true;
    invalidate();
  }
}
