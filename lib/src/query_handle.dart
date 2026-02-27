import 'dart:ui' show VoidCallback;

import 'core/retryer.dart';
import 'query_cache_entry.dart';
import 'query_client.dart';
import 'query_state.dart';

/// Handle returned by [QueryMixin.query] that exposes the current state of a
/// cached query and provides methods to refetch or optimistically update data.
class QueryHandle<T> {
  QueryHandle({
    required List<dynamic> key,
    required Future<T> Function() queryFn,
    required QueryClient client,
    required VoidCallback onStateChanged,
    required Duration staleTime,
    Duration gcTime = const Duration(minutes: 5),
    bool refetchOnMount = true,
    bool enabled = true,
    T? placeholderData,
    RetryConfig retryConfig = const RetryConfig(),
  })  : _key = key,
        _queryFn = queryFn,
        _client = client,
        _onStateChanged = onStateChanged,
        _staleTime = staleTime,
        _refetchOnMount = refetchOnMount,
        _enabled = enabled,
        _placeholderData = placeholderData,
        _retryConfig = retryConfig {
    _entry = client.getOrCreateEntry(key, gcTime: gcTime);
    _entry.addListener(_onCacheEntryChanged);
    _computeInitialState();
    _maybeAutoFetch();
  }

  final List<dynamic> _key;
  final Future<T> Function() _queryFn;
  final QueryClient _client;
  final VoidCallback _onStateChanged;
  final Duration _staleTime;
  final bool _refetchOnMount;
  final bool _enabled;
  final T? _placeholderData;
  final RetryConfig _retryConfig;

  late final QueryCacheEntry _entry;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  QueryState<T> _state = const QueryState<Never>();

  /// The current state of this query.
  QueryState<T> get state => _state;

  /// Shorthand: the data if available, otherwise `null`.
  T? get data => _state.data;

  /// `true` when the query is loading for the first time (no data yet).
  bool get isLoading => _state.isLoading;

  /// `true` when the query is in an error state.
  bool get isError => _state.isError;

  /// `true` when stale data is displayed and a background refetch is running.
  bool get isRefetching => _state.isRefetching;

  /// The error object if in error state, otherwise `null`.
  Object? get error => _state.error;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Force a refetch regardless of stale time.
  void refetch() {
    if (_disposed) return;
    _triggerFetch();
  }

  /// Refetch only if the cached data is stale. Called by [QueryMixin] when the
  /// app returns to the foreground.
  void refetchIfStale() {
    if (_disposed) return;
    if (_isStale) refetch();
  }

  /// Optimistically update the cached data.
  void setData(T Function(T prev) updater) {
    if (_disposed) return;
    final current = _entry.data as T;
    final updated = updater(current);
    _client.setQueryData(_key, updated);
  }

  /// Unsubscribe from the cache entry. Called by [QueryMixin.dispose].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _entry.removeListener(_onCacheEntryChanged);
  }

  // ---------------------------------------------------------------------------
  // Internal: staleness check
  // ---------------------------------------------------------------------------

  bool get _isStale => _entry.isStaleFor(_staleTime);

  // ---------------------------------------------------------------------------
  // Internal: state computation
  // ---------------------------------------------------------------------------

  void _computeInitialState() {
    if (_entry.hasData) {
      final isStale = _isStale;
      final willRefetch = isStale && _refetchOnMount && _enabled;
      _state = QueryState<T>(
        status: QueryStatus.success,
        fetchStatus: willRefetch ? FetchStatus.fetching : FetchStatus.idle,
        data: _entry.data as T,
        dataUpdatedAt: _entry.dataUpdatedAt,
      );
    } else if (_entry.hasError) {
      _state = QueryState<T>(
        status: QueryStatus.error,
        fetchStatus: FetchStatus.idle,
        error: _entry.error,
        stackTrace: _entry.stackTrace,
      );
    } else if (_placeholderData != null) {
      _state = QueryState<T>(
        status: QueryStatus.success,
        fetchStatus: FetchStatus.fetching,
        data: _placeholderData,
      );
    } else if (_enabled) {
      _state = const QueryState(
        status: QueryStatus.pending,
        fetchStatus: FetchStatus.fetching,
      );
    } else {
      _state = const QueryState(
        status: QueryStatus.pending,
        fetchStatus: FetchStatus.idle,
      );
    }
  }

  void _maybeAutoFetch() {
    if (!_enabled) return;

    if (!_entry.hasData) {
      // No data at all — must fetch.
      _triggerFetch();
    } else if (_refetchOnMount && _isStale) {
      // Have data but it's stale and refetchOnMount is on.
      _triggerFetch();
    }
  }

  void _triggerFetch() {
    if (_disposed) return;

    // If there's existing data, mark as refetching.
    if (_entry.hasData) {
      _dispatch(_state.copyWith(
        status: QueryStatus.success,
        fetchStatus: FetchStatus.fetching,
        data: () => _entry.data as T,
        dataUpdatedAt: _entry.dataUpdatedAt,
      ));
    }

    _entry.fetch(
      () => _queryFn(),
      retryConfig: _retryConfig,
      onFailed: (failureCount, error) {
        if (_disposed) return;
        _dispatch(_state.copyWith(
          fetchFailureCount: failureCount,
          fetchFailureReason: () => error,
        ));
      },
      onPause: () {
        if (_disposed) return;
        _dispatch(_state.copyWith(fetchStatus: FetchStatus.paused));
      },
      onContinue: () {
        if (_disposed) return;
        _dispatch(_state.copyWith(fetchStatus: FetchStatus.fetching));
      },
    );
  }

  void _onCacheEntryChanged() {
    if (_disposed) return;

    // Detect if a refetch will be needed (entry was invalidated).
    final needsRefetch =
        _entry.isInvalidated && !_entry.isFetching && _enabled;

    if (_entry.hasData && _entry.error == null) {
      _dispatch(QueryState<T>(
        status: QueryStatus.success,
        fetchStatus: needsRefetch ? FetchStatus.fetching : FetchStatus.idle,
        data: _entry.data as T,
        dataUpdatedAt: _entry.dataUpdatedAt,
      ));
    } else if (_entry.hasError && _entry.hasData) {
      _dispatch(QueryState<T>(
        status: QueryStatus.error,
        fetchStatus: FetchStatus.idle,
        data: _entry.data as T,
        error: _entry.error,
        stackTrace: _entry.stackTrace,
        dataUpdatedAt: _entry.dataUpdatedAt,
      ));
    } else if (_entry.hasError) {
      _dispatch(QueryState<T>(
        status: QueryStatus.error,
        fetchStatus: FetchStatus.idle,
        error: _entry.error,
        stackTrace: _entry.stackTrace,
      ));
    }

    if (needsRefetch) {
      _triggerFetch();
    }
  }

  void _dispatch(QueryState<T> newState) {
    if (_state == newState) return;
    _state = newState;
    _onStateChanged();
  }
}
