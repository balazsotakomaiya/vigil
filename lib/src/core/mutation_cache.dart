/// Global registry for in-flight mutations.
///
/// Manages scope-based serial execution: mutations that share a [scope]
/// run one-at-a-time in FIFO order. Mutations without a scope run
/// concurrently (the default).
class MutationCache {
  MutationCache();

  static final instance = MutationCache();

  final _entries = <MutationCacheEntry>[];

  /// Register a mutation. Returns its assigned [MutationCacheEntry].
  MutationCacheEntry add({String? scope}) {
    final entry = MutationCacheEntry._(scope: scope, cache: this);
    _entries.add(entry);
    return entry;
  }

  /// Remove a mutation from the cache (on dispose).
  void remove(MutationCacheEntry entry) {
    _entries.remove(entry);
  }

  /// Whether [entry] is allowed to execute now.
  ///
  /// A scoped mutation can run only if no other mutation with the same scope
  /// is currently executing.
  bool canRun(MutationCacheEntry entry) {
    if (entry.scope == null) return true;
    for (final other in _entries) {
      if (other == entry) continue;
      if (other.scope == entry.scope && other.isExecuting) {
        return false;
      }
    }
    return true;
  }

  /// Notify the next waiting mutation in [scope] that it can proceed.
  void runNext(String scope) {
    for (final entry in _entries) {
      if (entry.scope == scope && entry.isWaiting) {
        entry.proceed();
        return;
      }
    }
  }

  /// Number of entries in the cache.
  int get length => _entries.length;

  /// Clear all entries. Used by tests.
  void clear() {
    _entries.clear();
  }
}

/// Tracks the state of a single mutation within the [MutationCache].
class MutationCacheEntry {
  MutationCacheEntry._({required this.scope, required this.cache});

  /// The scope key, or `null` for unscoped (concurrent) mutations.
  final String? scope;

  /// The owning cache.
  final MutationCache cache;

  bool _executing = false;
  bool _waiting = false;
  void Function()? _onProceed;

  /// Whether this mutation is currently executing.
  bool get isExecuting => _executing;

  /// Whether this mutation is waiting for its turn in the scope queue.
  bool get isWaiting => _waiting;

  /// Mark this mutation as executing.
  void markExecuting() {
    _executing = true;
    _waiting = false;
  }

  /// Mark this mutation as done executing.
  /// Triggers the next waiting mutation in the same scope.
  void markDone() {
    _executing = false;
    _waiting = false;
    if (scope != null) {
      cache.runNext(scope!);
    }
  }

  /// Mark this mutation as waiting for its turn.
  void markWaiting(void Function() onProceed) {
    _waiting = true;
    _onProceed = onProceed;
  }

  /// Resume this mutation (called by [MutationCache.runNext]).
  void proceed() {
    _waiting = false;
    _onProceed?.call();
    _onProceed = null;
  }

  /// Remove this entry from the cache.
  void dispose() {
    _executing = false;
    _waiting = false;
    cache.remove(this);
    // If we were executing and got disposed, let the next one run.
    if (scope != null) {
      cache.runNext(scope!);
    }
  }
}
