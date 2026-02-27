import 'dart:async';
import 'dart:ui' show VoidCallback;

/// A single entry in the query cache.
///
/// Stores the data (or error) for a given query key, tracks staleness,
/// manages listeners, handles fetch deduplication, and schedules garbage
/// collection when no listeners remain.
class QueryCacheEntry {
  QueryCacheEntry({
    required this.serializedKey,
    this.gcTime = const Duration(minutes: 5),
  });

  /// The canonical serialized key (e.g. `'["todos"]'`).
  final String serializedKey;

  /// How long to keep the entry after the last listener unsubscribes.
  Duration gcTime;

  /// The cached data (untyped — callers cast through generics).
  dynamic data;

  /// The last fetch error, if any.
  Object? error;

  /// Stack trace associated with [error].
  StackTrace? stackTrace;

  /// When the data was last successfully fetched.
  DateTime? fetchedAt;

  // ---------------------------------------------------------------------------
  // Listeners
  // ---------------------------------------------------------------------------

  final Set<VoidCallback> _listeners = {};

  /// Number of active listeners (query handles observing this entry).
  int get listenerCount => _listeners.length;

  /// Register a listener that is called whenever the entry's state changes.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    _cancelGcTimer();
  }

  /// Remove a previously registered listener.
  ///
  /// When the listener count drops to zero the GC timer starts.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      _startGcTimer();
    }
  }

  /// Notify all listeners of a state change.
  void notifyListeners() {
    // Copy to avoid concurrent modification if a listener triggers disposal.
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  // ---------------------------------------------------------------------------
  // Fetch deduplication
  // ---------------------------------------------------------------------------

  Future<void>? _activeFetch;

  /// Whether a fetch is currently in progress.
  bool get isFetching => _activeFetch != null;

  /// Execute [queryFn] or deduplicate against an in-flight request.
  ///
  /// If a fetch is already in progress for this entry the existing future is
  /// returned so that only one network request fires per cache key.
  Future<void> fetch(Future<dynamic> Function() queryFn) {
    _activeFetch ??= _executeFetch(queryFn).whenComplete(() {
      _activeFetch = null;
    });
    return _activeFetch!;
  }

  Future<void> _executeFetch(Future<dynamic> Function() queryFn) async {
    try {
      final result = await queryFn();
      data = result;
      error = null;
      stackTrace = null;
      fetchedAt = DateTime.now();
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Staleness
  // ---------------------------------------------------------------------------

  /// Returns `true` if the entry has no data or the data has exceeded the
  /// given [staleTime] since it was fetched.
  bool isStaleFor(Duration staleTime) {
    if (fetchedAt == null) return true;
    return DateTime.now().isAfter(fetchedAt!.add(staleTime));
  }

  /// Whether any data has been successfully fetched at least once.
  bool get hasData => data != null;

  /// Whether the last fetch resulted in an error.
  bool get hasError => error != null;

  // ---------------------------------------------------------------------------
  // Garbage collection
  // ---------------------------------------------------------------------------

  Timer? _gcTimer;

  /// Callback invoked when this entry should be evicted from the cache.
  void Function(String key)? onEvict;

  void _startGcTimer() {
    _gcTimer?.cancel();
    _gcTimer = Timer(gcTime, () {
      if (_listeners.isEmpty) {
        onEvict?.call(serializedKey);
      }
    });
  }

  void _cancelGcTimer() {
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  /// Cancel any pending timers. Called when the entry is removed from cache.
  void dispose() {
    _cancelGcTimer();
    _listeners.clear();
  }
}
