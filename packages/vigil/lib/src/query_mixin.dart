import 'package:flutter/widgets.dart';

import 'core/focus_manager.dart';
import 'core/network_mode.dart';
import 'core/retryer.dart';
import 'infinite_query_handle.dart';
import 'mutation_handle.dart';
import 'query_client.dart';
import 'query_client_provider.dart';
import 'query_handle.dart';

/// Mixin that adds TanStack Query-style data fetching to a [State].
///
/// Usage:
/// ```dart
/// class _MyState extends State<MyWidget> with QueryMixin {
///   late final todos = query<List<Todo>>(
///     ['todos'],
///     () => api.fetchTodos(),
///     stale: Duration(minutes: 5),
///   );
///
///   late final addTodo = mutation<Todo, CreateTodoInput>(
///     (input) => api.createTodo(input),
///     invalidates: [['todos']],
///   );
///
///   @override
///   Widget build(BuildContext context) {
///     final s = todos.state;
///     if (s.isLoading) return CircularProgressIndicator();
///     if (s.isError) return Text('${s.error}');
///     return TodoList(s.data!);
///   }
/// }
/// ```
mixin QueryMixin<W extends StatefulWidget> on State<W> {
  final List<QueryHandle<dynamic>> _queries = [];
  final List<MutationHandle<dynamic, dynamic>> _mutations = [];
  final List<InfiniteQueryHandle<dynamic, dynamic>> _infiniteQueries = [];
  void Function()? _focusUnsub;

  /// Resolve the [QueryClient] — prefer inherited, fall back to singleton.
  QueryClient get _queryClient {
    final inherited = context
        .getInheritedWidgetOfExactType<QueryClientProvider>()
        ?.client;
    return inherited ?? QueryClient.instance;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _focusUnsub = FocusManager.instance.subscribe(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusUnsub?.call();
    for (final q in _queries) {
      q.dispose();
    }
    for (final m in _mutations) {
      m.dispose();
    }
    for (final iq in _infiniteQueries) {
      iq.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (FocusManager.instance.isFocused) {
      for (final q in _queries) {
        q.refetchIfStale();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Query factory
  // ---------------------------------------------------------------------------

  /// Create a cached, auto-fetched, stale-aware query.
  ///
  /// - [key] identifies the query in the cache. Use a list like
  ///   `['todos']` or `['todo', id]`.
  /// - [queryFn] is the async function that fetches data.
  /// - [stale] is how long fetched data is considered fresh (default: 0 — always
  ///   stale, meaning every mount triggers a background refetch).
  /// - [gcTime] is how long unused cache entries are kept after all listeners
  ///   unsubscribe (default: 5 minutes).
  /// - [refetchOnMount] controls whether the query automatically refetches when
  ///   the widget mounts and data is stale (default: true).
  /// - [enabled] can disable automatic fetching (default: true).
  /// - [placeholderData] is shown while the first fetch is in progress.
  /// - [retry] is the maximum number of retries on failure (default: 3).
  /// - [retryDelay] computes the delay before each retry (default: exponential
  ///   backoff with full jitter, capped at 30s).
  /// - [shouldRetry] decides whether a given error should be retried
  ///   (default: always retry).
  /// - [networkMode] controls fetch behavior relative to connectivity
  ///   (default: [NetworkMode.online]).
  /// - [refetchInterval] enables polling: the query automatically refetches
  ///   at this interval. Pass `null` (the default) to disable.
  /// - [refetchIntervalInBackground] if `true`, keeps polling even when the
  ///   app is backgrounded (default: `false`).
  QueryHandle<T> query<T>(
    List<dynamic> key,
    Future<T> Function() queryFn, {
    Duration stale = Duration.zero,
    Duration gcTime = const Duration(minutes: 5),
    bool refetchOnMount = true,
    bool enabled = true,
    T? placeholderData,
    int retry = 3,
    Duration Function(int attempt)? retryDelay,
    bool Function(Object error)? shouldRetry,
    NetworkMode networkMode = NetworkMode.online,
    Duration? refetchInterval,
    bool refetchIntervalInBackground = false,
  }) {
    final handle = QueryHandle<T>(
      key: key,
      queryFn: queryFn,
      client: _queryClient,
      onStateChanged: _safeSetState,
      staleTime: stale,
      gcTime: gcTime,
      refetchOnMount: refetchOnMount,
      enabled: enabled,
      placeholderData: placeholderData,
      retryConfig: RetryConfig(
        maxRetries: retry,
        retryDelay: retryDelay != null
            ? (attempt, {random}) => retryDelay(attempt)
            : defaultRetryDelay,
        shouldRetry: shouldRetry ?? defaultShouldRetry,
        networkMode: networkMode,
      ),
      refetchInterval: refetchInterval,
      refetchIntervalInBackground: refetchIntervalInBackground,
    );
    _queries.add(handle);
    return handle;
  }

  // ---------------------------------------------------------------------------
  // Infinite Query factory
  // ---------------------------------------------------------------------------

  /// Create a paginated, infinite query.
  ///
  /// - [key] identifies the query in the cache.
  /// - [queryFn] receives a page parameter and returns the data for that page.
  /// - [initialPageParam] is the page parameter for the first page.
  /// - [getNextPageParam] derives the next page param from the last page and
  ///   all pages. Return `null` to signal there are no more pages.
  /// - [getPreviousPageParam] derives the previous page param. Optional.
  /// - [maxPages] limits the number of pages kept in memory (FIFO eviction).
  /// - [stale], [enabled], [retry], [retryDelay], [shouldRetry],
  ///   [networkMode], [refetchInterval], [refetchIntervalInBackground] work
  ///   the same as for [query].
  InfiniteQueryHandle<T, P> infiniteQuery<T, P>(
    List<dynamic> key,
    Future<T> Function(P pageParam) queryFn, {
    required P initialPageParam,
    required P? Function(T lastPage, List<T> allPages) getNextPageParam,
    P? Function(T firstPage, List<T> allPages)? getPreviousPageParam,
    Duration stale = Duration.zero,
    bool enabled = true,
    int? maxPages,
    int retry = 3,
    Duration Function(int attempt)? retryDelay,
    bool Function(Object error)? shouldRetry,
    NetworkMode networkMode = NetworkMode.online,
    Duration? refetchInterval,
    bool refetchIntervalInBackground = false,
  }) {
    final handle = InfiniteQueryHandle<T, P>(
      key: key,
      queryFn: queryFn,
      initialPageParam: initialPageParam,
      getNextPageParam: getNextPageParam,
      getPreviousPageParam: getPreviousPageParam,
      onStateChanged: _safeSetState,
      staleTime: stale,
      enabled: enabled,
      maxPages: maxPages,
      retryConfig: RetryConfig(
        maxRetries: retry,
        retryDelay: retryDelay != null
            ? (attempt, {random}) => retryDelay(attempt)
            : defaultRetryDelay,
        shouldRetry: shouldRetry ?? defaultShouldRetry,
        networkMode: networkMode,
      ),
      refetchInterval: refetchInterval,
      refetchIntervalInBackground: refetchIntervalInBackground,
    );
    _infiniteQueries.add(handle);
    return handle;
  }

  // ---------------------------------------------------------------------------
  // Mutation factory
  // ---------------------------------------------------------------------------

  /// Create a mutation that can fire an async write and optionally invalidate
  /// queries on success.
  ///
  /// - [mutationFn] is the async function to execute.
  /// - [invalidates] is a list of query key prefixes to invalidate on success.
  /// - [onSuccess] is called with the result data on success.
  /// - [onError] is called with the error and a rollback function on failure.
  /// - [optimisticUpdate] runs synchronously before the mutation to apply
  ///   an optimistic cache update. If the mutation fails, calling `rollback()`
  ///   in [onError] restores the previous data.
  /// - [scope] groups mutations for serial execution. Two mutations with the
  ///   same scope never run concurrently — the second waits for the first.
  MutationHandle<TData, TInput> mutation<TData, TInput>(
    Future<TData> Function(TInput input) mutationFn, {
    List<List<dynamic>>? invalidates,
    void Function(TData data)? onSuccess,
    void Function(Object error, void Function() rollback)? onError,
    void Function(TInput input)? optimisticUpdate,
    String? scope,
  }) {
    final handle = MutationHandle<TData, TInput>(
      mutationFn: mutationFn,
      client: _queryClient,
      onStateChanged: _safeSetState,
      invalidates: invalidates,
      onSuccess: onSuccess,
      onError: onError,
      optimisticUpdate: optimisticUpdate,
      scope: scope,
    );
    _mutations.add(handle);
    return handle;
  }

  // ---------------------------------------------------------------------------
  // Imperative API
  // ---------------------------------------------------------------------------

  /// Invalidate all queries matching [keyPrefix] across the cache.
  void invalidateQueries(List<dynamic> keyPrefix) {
    _queryClient.invalidateQueries(keyPrefix);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _safeSetState() {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {});
    }
  }
}
