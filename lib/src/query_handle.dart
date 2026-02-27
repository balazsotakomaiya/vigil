import 'dart:ui' show VoidCallback;

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
  })  : _key = key,
        _queryFn = queryFn,
        _client = client,
        _onStateChanged = onStateChanged,
        _staleTime = staleTime,
        _refetchOnMount = refetchOnMount,
        _enabled = enabled,
        _placeholderData = placeholderData {
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

  late final QueryCacheEntry _entry;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  QueryState<T> _state = const QueryInitial();

  /// The current state of this query.
  QueryState<T> get state => _state;

  /// Shorthand: the data if in [QueryData] state, otherwise `null`.
  T? get data => switch (_state) {
        QueryData<T>(:final data) => data,
        QueryError<T>(:final staleData) => staleData,
        _ => null,
      };

  /// `true` when the query is loading for the first time (no data yet).
  bool get isLoading => _state is QueryLoading<T>;

  /// `true` when the query is in an error state.
  bool get isError => _state is QueryError<T>;

  /// `true` when stale data is displayed and a background refetch is running.
  bool get isRefetching => switch (_state) {
        QueryData<T>(:final isRefetching) => isRefetching,
        _ => false,
      };

  /// The error object if in [QueryError] state, otherwise `null`.
  Object? get error => switch (_state) {
        QueryError<T>(:final error) => error,
        _ => null,
      };

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
  ///
  /// The previous value is stored internally so that [MutationHandle] can
  /// perform a rollback on error.
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
      _state = QueryData<T>(
        _entry.data as T,
        isRefetching: isStale && _refetchOnMount && _enabled,
      );
    } else if (_entry.hasError) {
      _state = QueryError<T>(
        _entry.error!,
        stackTrace: _entry.stackTrace,
      );
    } else if (_placeholderData != null) {
      _state = QueryData<T>(_placeholderData as T, isRefetching: true);
    } else if (_enabled) {
      _state = const QueryLoading();
    } else {
      _state = const QueryInitial();
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
      _updateState(QueryData<T>(_entry.data as T, isRefetching: true));
    }

    _entry.fetch(() => _queryFn());
  }

  void _onCacheEntryChanged() {
    if (_disposed) return;

    // Detect if a refetch will be needed (entry was invalidated).
    final needsRefetch =
        _entry.fetchedAt == null && !_entry.isFetching && _enabled;

    if (_entry.hasData && _entry.error == null) {
      _updateState(QueryData<T>(
        _entry.data as T,
        isRefetching: needsRefetch,
      ));
    } else if (_entry.hasError && _entry.hasData) {
      _updateState(QueryError<T>(
        _entry.error!,
        stackTrace: _entry.stackTrace,
        staleData: _entry.data as T,
      ));
    } else if (_entry.hasError) {
      _updateState(QueryError<T>(
        _entry.error!,
        stackTrace: _entry.stackTrace,
      ));
    }

    if (needsRefetch) {
      _triggerFetch();
    }
  }

  void _updateState(QueryState<T> newState) {
    if (_state == newState) return;
    _state = newState;
    _onStateChanged();
  }
}
