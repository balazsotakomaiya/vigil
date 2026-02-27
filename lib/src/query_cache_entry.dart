import 'dart:async';
import 'dart:ui' show VoidCallback;

import 'core/notify_manager.dart';
import 'core/retryer.dart';

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

  /// When the data was last successfully fetched (millisecondsSinceEpoch).
  int dataUpdatedAt = 0;

  /// Whether the entry has been explicitly invalidated.
  bool isInvalidated = false;

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

  /// Notify all listeners of a state change via [NotifyManager].
  void notifyListeners() {
    NotifyManager.instance.notify(() {
      // Copy to avoid concurrent modification if a listener triggers disposal.
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Fetch deduplication
  // ---------------------------------------------------------------------------

  Future<void>? _activeFetch;
  Retryer<dynamic>? _activeRetryer;

  /// Whether a fetch is currently in progress.
  bool get isFetching => _activeFetch != null;

  /// The currently active retryer, if any. Exposed for cancellation.
  Retryer<dynamic>? get activeRetryer => _activeRetryer;

  /// Execute [queryFn] or deduplicate against an in-flight request.
  ///
  /// If a fetch is already in progress for this entry the existing future is
  /// returned so that only one network request fires per cache key.
  ///
  /// [retryConfig] controls retry behavior (count, delay, network mode).
  Future<void> fetch(
    Future<dynamic> Function() queryFn, {
    RetryConfig retryConfig = const RetryConfig(),
    void Function(int failureCount, Object error)? onFailed,
    void Function()? onPause,
    void Function()? onContinue,
  }) {
    _activeFetch ??= _executeFetch(
      queryFn,
      retryConfig: retryConfig,
      onFailed: onFailed,
      onPause: onPause,
      onContinue: onContinue,
    ).whenComplete(() {
      _activeFetch = null;
      _activeRetryer = null;
    });
    return _activeFetch!;
  }

  Future<void> _executeFetch(
    Future<dynamic> Function() queryFn, {
    required RetryConfig retryConfig,
    void Function(int failureCount, Object error)? onFailed,
    void Function()? onPause,
    void Function()? onContinue,
  }) async {
    final retryer = Retryer<dynamic>(
      fn: queryFn,
      config: retryConfig,
      onFailed: onFailed,
      onPause: onPause,
      onContinue: onContinue,
    );
    _activeRetryer = retryer;

    try {
      final result = await retryer.start();
      data = result;
      error = null;
      stackTrace = null;
      dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      isInvalidated = false;
    } on RetryerCancelledException {
      // Cancelled — don't update state.
      return;
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
    if (dataUpdatedAt == 0) return true;
    if (isInvalidated) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - dataUpdatedAt;
    return elapsed >= staleTime.inMilliseconds;
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
