import 'dart:convert' show jsonEncode;

import 'core/notify_manager.dart';
import 'core/query_defaults.dart';
import 'query_cache_entry.dart';

/// Global cache for query data.
///
/// The client manages a `Map<String, QueryCacheEntry>` keyed by the JSON
/// serialization of query keys (e.g. `'["todos"]'`).
///
/// Supports a three-layer option cascade: global defaults → per-key defaults
/// → per-call options. Set global defaults via the constructor, per-key
/// defaults via [setQueryDefaults], and per-call options via [QueryMixin.query].
///
/// Prefer obtaining the client via [QueryClientProvider]; a singleton fallback
/// is available as [QueryClient.instance].
class QueryClient {
  QueryClient({QueryDefaults? defaultQueryOptions})
      : _globalDefaults = defaultQueryOptions ?? const QueryDefaults();

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  static QueryClient? _instance;

  /// Global singleton instance. Prefer [QueryClientProvider] for testability.
  static QueryClient get instance => _instance ??= QueryClient();

  /// Replace the global singleton (useful for tests).
  static set instance(QueryClient client) => _instance = client;

  /// Reset the singleton so the next access creates a fresh client.
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  // ---------------------------------------------------------------------------
  // Option cascade
  // ---------------------------------------------------------------------------

  final QueryDefaults _globalDefaults;
  final Map<String, QueryDefaults> _queryDefaults = {};

  /// Set default options for all queries whose key starts with [keyPrefix].
  ///
  /// These defaults sit between the global defaults and per-call options
  /// in the three-layer cascade.
  void setQueryDefaults(List<dynamic> keyPrefix, QueryDefaults defaults) {
    _queryDefaults[serializeKey(keyPrefix)] = defaults;
  }

  /// Resolve options: global → per-key → per-call.
  QueryDefaults resolveQueryOptions(
    List<dynamic> key,
    QueryDefaults perCall,
  ) {
    final perKey = _findMatchingDefaults(key);
    return _globalDefaults.merge(perKey).merge(perCall);
  }

  QueryDefaults? _findMatchingDefaults(List<dynamic> key) {
    final serialized = serializeKey(key);

    // Find the most specific (longest) matching prefix.
    String? bestMatch;
    for (final prefix in _queryDefaults.keys) {
      if (_keyMatchesPrefix(
        serialized,
        prefix.substring(0, prefix.length - 1),
        prefix,
      )) {
        if (bestMatch == null || prefix.length > bestMatch.length) {
          bestMatch = prefix;
        }
      }
    }
    return bestMatch != null ? _queryDefaults[bestMatch] : null;
  }

  // ---------------------------------------------------------------------------
  // Cache
  // ---------------------------------------------------------------------------

  final Map<String, QueryCacheEntry> _cache = {};

  /// Serialize a query key to a canonical string.
  static String serializeKey(List<dynamic> key) => jsonEncode(key);

  /// Return the cache entry for [key], creating one if it does not exist.
  QueryCacheEntry getOrCreateEntry(
    List<dynamic> key, {
    Duration gcTime = const Duration(minutes: 5),
  }) {
    final serialized = serializeKey(key);
    return _cache.putIfAbsent(serialized, () {
      final entry = QueryCacheEntry(
        serializedKey: serialized,
        gcTime: gcTime,
      );
      entry.onEvict = _evict;
      return entry;
    })
      // If the entry already exists, update gcTime to the maximum of the
      // existing and new values so that the most generous retention wins.
      ..gcTime = _maxDuration(_cache[serialized]!.gcTime, gcTime);
  }

  /// Retrieve cached data for [key], or `null` if none exists.
  T? getQueryData<T>(List<dynamic> key) {
    final entry = _cache[serializeKey(key)];
    if (entry == null || !entry.hasData) return null;
    return entry.data as T;
  }

  /// Directly set data for [key] in the cache. Useful for optimistic updates
  /// and pre-populating the cache.
  void setQueryData<T>(List<dynamic> key, T data) {
    final serialized = serializeKey(key);
    final entry = _cache[serialized];
    if (entry != null) {
      entry.data = data;
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      entry.isInvalidated = false;
      entry.error = null;
      entry.stackTrace = null;
      entry.notifyListeners();
    }
  }

  /// Set data on a cache entry by its already-serialized key.
  void setQueryDataRaw(String serializedKey, dynamic data) {
    final entry = _cache[serializedKey];
    if (entry != null) {
      entry.data = data;
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      entry.isInvalidated = false;
      entry.error = null;
      entry.stackTrace = null;
      entry.notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Invalidation
  // ---------------------------------------------------------------------------

  /// Invalidate all cache entries whose key starts with [keyPrefix].
  ///
  /// Prefix matching: `invalidateQueries(['todos'])` invalidates `['todos']`,
  /// `['todos', 'active']`, `['todos', 'completed']`, etc.
  ///
  /// Invalidated entries are marked so they are considered stale on next access,
  /// and listeners are notified immediately to trigger refetches.
  void invalidateQueries(List<dynamic> keyPrefix) {
    NotifyManager.instance.batch(() {
      final prefix = serializeKey(keyPrefix);
      // A serialized key `'["todos","active"]'` starts with the serialized
      // prefix `'["todos"'` (without trailing `]`) when it's a true prefix.
      //
      // We strip the trailing `]` from the prefix so that:
      //   '["todos"]'           starts with '["todos"'  ✓
      //   '["todos","active"]'  starts with '["todos"'  ✓
      //   '["todosX"]'          starts with '["todos"'  ✗ (handled below)
      final prefixWithoutClose = prefix.substring(0, prefix.length - 1);

      for (final entry in _cache.entries) {
        if (_keyMatchesPrefix(entry.key, prefixWithoutClose, prefix)) {
          entry.value.isInvalidated = true;
          entry.value.notifyListeners();
        }
      }
    });
  }

  /// Check if [serializedKey] matches the given prefix.
  ///
  /// A key matches if it equals the full serialized prefix (exact match) or
  /// starts with the prefix followed by a comma separator.
  bool _keyMatchesPrefix(
    String serializedKey,
    String prefixWithoutClose,
    String fullPrefix,
  ) {
    if (serializedKey == fullPrefix) return true;
    // The key must start with the prefix (minus `]`) followed by `,` to ensure
    // we don't match partial key segments like ["todosX"] for prefix ["todos"].
    return serializedKey.startsWith('$prefixWithoutClose,');
  }

  /// Remove all cache entries whose key starts with [keyPrefix].
  void removeQueries(List<dynamic> keyPrefix) {
    final prefix = serializeKey(keyPrefix);
    final prefixWithoutClose = prefix.substring(0, prefix.length - 1);

    final keysToRemove = _cache.keys
        .where((k) => _keyMatchesPrefix(k, prefixWithoutClose, prefix))
        .toList();

    for (final key in keysToRemove) {
      _cache.remove(key)?.dispose();
    }
  }

  /// Remove all entries from the cache.
  void clear() {
    for (final entry in _cache.values) {
      entry.dispose();
    }
    _cache.clear();
  }

  /// Clean up resources.
  void dispose() {
    clear();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _evict(String serializedKey) {
    _cache.remove(serializedKey)?.dispose();
  }

  static Duration _maxDuration(Duration a, Duration b) =>
      a > b ? a : b;

  // ---------------------------------------------------------------------------
  // Introspection (useful for tests & dev tools)
  // ---------------------------------------------------------------------------

  /// Number of entries currently in the cache.
  int get size => _cache.length;

  /// All serialized keys currently in the cache.
  Iterable<String> get keys => _cache.keys;

  /// Get a raw cache entry by serialized key. Intended for tests / dev tools.
  QueryCacheEntry? getEntry(String serializedKey) => _cache[serializedKey];

  /// Snapshot of all cache entries matching [keyPrefix].
  ///
  /// Returns a map of serialized key → current data. Used internally for
  /// optimistic-update rollback.
  Map<String, dynamic> snapshotEntries(List<List<dynamic>> keyPrefixes) {
    final snapshots = <String, dynamic>{};
    for (final keyPrefix in keyPrefixes) {
      final prefix = serializeKey(keyPrefix);
      final prefixWithoutClose = prefix.substring(0, prefix.length - 1);

      for (final entry in _cache.entries) {
        if (_keyMatchesPrefix(entry.key, prefixWithoutClose, prefix)) {
          snapshots[entry.key] = entry.value.data;
        }
      }
    }
    return snapshots;
  }

  /// Restore a previously taken snapshot. Used for optimistic-update rollback.
  void restoreSnapshot(Map<String, dynamic> snapshot) {
    for (final entry in snapshot.entries) {
      final cacheEntry = _cache[entry.key];
      if (cacheEntry != null) {
        cacheEntry.data = entry.value;
        cacheEntry.notifyListeners();
      }
    }
  }
}
