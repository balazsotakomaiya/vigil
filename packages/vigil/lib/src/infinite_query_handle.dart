import 'dart:async';

import 'core/focus_manager.dart';
import 'core/online_manager.dart';
import 'core/retryer.dart';
import 'infinite_query_data.dart';
import 'query_state.dart';

/// Handle for infinite (paginated) queries.
///
/// Accumulates pages via [fetchNextPage] / [fetchPreviousPage] and stores them
/// as [InfiniteQueryData]. The cache key stores the full `InfiniteQueryData`
/// object so that page state is preserved across re-mounts.
///
/// ```dart
/// late final todos = infiniteQuery<List<Todo>, int>(
///   ['todos'],
///   (pageParam) => api.fetchTodos(page: pageParam),
///   initialPageParam: 1,
///   getNextPageParam: (lastPage, allPages) =>
///       lastPage.length == 20 ? allPages.length + 1 : null,
/// );
///
/// // Fetch next page
/// todos.fetchNextPage();
/// // Access all pages
/// todos.pages; // List<List<Todo>>
/// ```
class InfiniteQueryHandle<T, P> {
  InfiniteQueryHandle({
    required List<dynamic> key,
    required Future<T> Function(P pageParam) queryFn,
    required P initialPageParam,
    required P? Function(T lastPage, List<T> allPages) getNextPageParam,
    P? Function(T firstPage, List<T> allPages)? getPreviousPageParam,
    required void Function() onStateChanged,
    Duration staleTime = Duration.zero,
    bool enabled = true,
    int? maxPages,
    RetryConfig retryConfig = const RetryConfig(),
    Duration? refetchInterval,
    bool refetchIntervalInBackground = false,
  })  : _key = key,
        _queryFn = queryFn,
        _initialPageParam = initialPageParam,
        _getNextPageParam = getNextPageParam,
        _getPreviousPageParam = getPreviousPageParam,
        _onStateChanged = onStateChanged,
        _staleTime = staleTime,
        _enabled = enabled,
        _maxPages = maxPages,
        _retryConfig = retryConfig,
        _refetchInterval = refetchInterval,
        _refetchIntervalInBackground = refetchIntervalInBackground {
    _computeInitialState();
    if (_enabled) _initialFetch();
    _startRefetchInterval();
  }

  final List<dynamic> _key;
  final Future<T> Function(P pageParam) _queryFn;
  final P _initialPageParam;
  final P? Function(T lastPage, List<T> allPages) _getNextPageParam;
  final P? Function(T firstPage, List<T> allPages)? _getPreviousPageParam;
  final void Function() _onStateChanged;
  final Duration _staleTime;
  final bool _enabled;
  final int? _maxPages;
  final RetryConfig _retryConfig;
  final Duration? _refetchInterval;
  final bool _refetchIntervalInBackground;

  bool _disposed = false;
  Future<void>? _activeFetch;

  // Refetch interval state
  Timer? _refetchTimer;
  void Function()? _focusUnsub;
  void Function()? _onlineUnsub;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  QueryState<InfiniteQueryData<T, P>> _state =
      const QueryState<InfiniteQueryData<Never, Never>>();

  /// The current state of this infinite query.
  QueryState<InfiniteQueryData<T, P>> get state => _state;

  /// All fetched pages.
  List<T> get pages => _state.data?.pages ?? [];

  /// All page parameters.
  List<P> get pageParams => _state.data?.pageParams ?? [];

  /// The accumulated data object, or `null` if no pages are loaded.
  InfiniteQueryData<T, P>? get data => _state.data;

  /// First load: no pages yet and currently fetching.
  bool get isLoading => _state.isLoading;

  /// Background refetch (have pages and currently fetching).
  bool get isRefetching => _state.isRefetching;

  /// Error state.
  bool get isError => _state.isError;

  /// The error, if any.
  Object? get error => _state.error;

  /// Whether fetching the next page is in progress.
  bool get isFetchingNextPage => _isFetchingDirection == _Direction.forward;

  /// Whether fetching the previous page is in progress.
  bool get isFetchingPreviousPage =>
      _isFetchingDirection == _Direction.backward;

  _Direction? _isFetchingDirection;

  /// Whether there is a next page available.
  bool get hasNextPage {
    final d = _state.data;
    if (d == null || d.pages.isEmpty) return true; // haven't loaded yet
    return _getNextPageParam(d.pages.last, d.pages) != null;
  }

  /// Whether there is a previous page available.
  bool get hasPreviousPage {
    if (_getPreviousPageParam == null) return false;
    final d = _state.data;
    if (d == null || d.pages.isEmpty) return false;
    return _getPreviousPageParam!(d.pages.first, d.pages) != null;
  }

  // ---------------------------------------------------------------------------
  // Convenience getters (list-like access to flattened pages)
  // ---------------------------------------------------------------------------

  /// The query key.
  List<dynamic> get key => _key;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Fetch the next page. No-op if [hasNextPage] is false or a fetch is
  /// already in progress.
  Future<void> fetchNextPage() async {
    if (_disposed) return;
    if (_activeFetch != null) return;
    if (!hasNextPage) return;

    final d = _state.data;
    P param;
    if (d == null || d.pages.isEmpty) {
      param = _initialPageParam;
    } else {
      final nextParam = _getNextPageParam(d.pages.last, d.pages);
      if (nextParam == null) return;
      param = nextParam;
    }

    _isFetchingDirection = _Direction.forward;
    try {
      await _fetchPage(param, _Direction.forward);
    } finally {
      _isFetchingDirection = null;
    }
  }

  /// Fetch the previous page. No-op if [hasPreviousPage] is false or a fetch
  /// is already in progress.
  Future<void> fetchPreviousPage() async {
    if (_disposed) return;
    if (_activeFetch != null) return;
    if (!hasPreviousPage) return;

    final d = _state.data;
    if (d == null || d.pages.isEmpty || _getPreviousPageParam == null) return;

    final prevParam = _getPreviousPageParam!(d.pages.first, d.pages);
    if (prevParam == null) return;

    _isFetchingDirection = _Direction.backward;
    try {
      await _fetchPage(prevParam, _Direction.backward);
    } finally {
      _isFetchingDirection = null;
    }
  }

  /// Refetch all existing pages sequentially, preserving their order.
  /// This is what happens on invalidation or refetchInterval.
  Future<void> refetchAllPages() async {
    if (_disposed) return;
    if (_activeFetch != null) return;

    final currentData = _state.data;
    if (currentData == null || currentData.pages.isEmpty) {
      // No pages to refetch; do initial fetch.
      await fetchNextPage();
      return;
    }

    _dispatch(_state.copyWith(fetchStatus: FetchStatus.fetching));

    _activeFetch = _refetchAllPagesImpl(currentData);
    try {
      await _activeFetch;
    } finally {
      _activeFetch = null;
    }
  }

  /// Force a refetch of all pages.
  void refetch() {
    if (_disposed) return;
    refetchAllPages();
    _resetRefetchInterval();
  }

  /// Dispose of this handle.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopRefetchInterval();
  }

  // ---------------------------------------------------------------------------
  // Internal: initial state + fetch
  // ---------------------------------------------------------------------------

  void _computeInitialState() {
    if (_enabled) {
      _state = QueryState<InfiniteQueryData<T, P>>(
        status: QueryStatus.pending,
        fetchStatus: FetchStatus.fetching,
      );
    } else {
      _state = QueryState<InfiniteQueryData<T, P>>(
        status: QueryStatus.pending,
        fetchStatus: FetchStatus.idle,
      );
    }
  }

  void _initialFetch() {
    fetchNextPage();
  }

  // ---------------------------------------------------------------------------
  // Internal: page fetching
  // ---------------------------------------------------------------------------

  Future<void> _fetchPage(P param, _Direction direction) async {
    _dispatch(_state.copyWith(fetchStatus: FetchStatus.fetching));

    final completer = Completer<void>();
    _activeFetch = completer.future;

    try {
      final retryer = Retryer<T>(
        fn: () => _queryFn(param),
        config: _retryConfig,
      );

      final page = await retryer.start();
      if (_disposed) return;

      var newData = _state.data ?? InfiniteQueryData<T, P>();
      if (direction == _Direction.forward) {
        newData = newData.appendPage(page, param);
      } else {
        newData = newData.prependPage(page, param);
      }

      // Apply maxPages eviction.
      if (_maxPages != null) {
        newData = newData.evict(_maxPages!);
      }

      _dispatch(QueryState<InfiniteQueryData<T, P>>(
        status: QueryStatus.success,
        fetchStatus: FetchStatus.idle,
        data: newData,
        dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } on RetryerCancelledException {
      // Cancelled — revert to idle.
      if (!_disposed) {
        _dispatch(_state.copyWith(fetchStatus: FetchStatus.idle));
      }
    } catch (e, st) {
      if (!_disposed) {
        _dispatch(QueryState<InfiniteQueryData<T, P>>(
          status: QueryStatus.error,
          fetchStatus: FetchStatus.idle,
          data: _state.data,
          error: e,
          stackTrace: st,
        ));
      }
    } finally {
      if (!completer.isCompleted) completer.complete();
      _activeFetch = null;
    }
  }

  Future<void> _refetchAllPagesImpl(
      InfiniteQueryData<T, P> currentData) async {
    final newPages = <T>[];
    final newParams = <P>[];

    for (var i = 0; i < currentData.pageParams.length; i++) {
      if (_disposed) return;

      final param = currentData.pageParams[i];

      try {
        final retryer = Retryer<T>(
          fn: () => _queryFn(param),
          config: _retryConfig,
        );

        final page = await retryer.start();
        newPages.add(page);
        newParams.add(param);
      } on RetryerCancelledException {
        if (!_disposed) {
          _dispatch(_state.copyWith(fetchStatus: FetchStatus.idle));
        }
        return;
      } catch (e, st) {
        if (!_disposed) {
          _dispatch(QueryState<InfiniteQueryData<T, P>>(
            status: QueryStatus.error,
            fetchStatus: FetchStatus.idle,
            data: _state.data,
            error: e,
            stackTrace: st,
          ));
        }
        return;
      }
    }

    if (_disposed) return;

    _dispatch(QueryState<InfiniteQueryData<T, P>>(
      status: QueryStatus.success,
      fetchStatus: FetchStatus.idle,
      data: InfiniteQueryData<T, P>(
        pages: newPages,
        pageParams: newParams,
      ),
      dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ---------------------------------------------------------------------------
  // Internal: state dispatch
  // ---------------------------------------------------------------------------

  void _dispatch(QueryState<InfiniteQueryData<T, P>> newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_disposed) {
      _onStateChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: refetch interval (polling)
  // ---------------------------------------------------------------------------

  void _startRefetchInterval() {
    if (_refetchInterval == null || !_enabled) return;

    if (!_refetchIntervalInBackground) {
      _focusUnsub = FocusManager.instance.subscribe(_onIntervalFocusChanged);
    }
    _onlineUnsub = OnlineManager.instance.subscribe(_onIntervalOnlineChanged);

    _scheduleNextInterval();
  }

  void _stopRefetchInterval() {
    _refetchTimer?.cancel();
    _refetchTimer = null;
    _focusUnsub?.call();
    _focusUnsub = null;
    _onlineUnsub?.call();
    _onlineUnsub = null;
  }

  void _resetRefetchInterval() {
    if (_refetchInterval == null) return;
    _refetchTimer?.cancel();
    _refetchTimer = null;
    _scheduleNextInterval();
  }

  void _scheduleNextInterval() {
    if (_disposed || _refetchInterval == null) return;
    if (!_shouldIntervalRun()) return;

    _refetchTimer?.cancel();
    _refetchTimer = Timer(_refetchInterval!, () {
      if (_disposed) return;
      if (!_shouldIntervalRun()) return;
      refetchAllPages();
      _scheduleNextInterval();
    });
  }

  bool _shouldIntervalRun() {
    if (!_enabled) return false;
    if (!_refetchIntervalInBackground && !FocusManager.instance.isFocused) {
      return false;
    }
    if (!OnlineManager.instance.isOnline) return false;
    return true;
  }

  void _onIntervalFocusChanged() {
    if (_disposed || _refetchInterval == null) return;
    if (FocusManager.instance.isFocused) {
      _scheduleNextInterval();
    } else {
      _refetchTimer?.cancel();
      _refetchTimer = null;
    }
  }

  void _onIntervalOnlineChanged() {
    if (_disposed || _refetchInterval == null) return;
    if (OnlineManager.instance.isOnline) {
      _scheduleNextInterval();
    } else {
      _refetchTimer?.cancel();
      _refetchTimer = null;
    }
  }
}

enum _Direction { forward, backward }
