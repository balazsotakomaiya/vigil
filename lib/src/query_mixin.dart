import 'package:flutter/widgets.dart';

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
///     return switch (todos.state) {
///       QueryLoading() => CircularProgressIndicator(),
///       QueryError(:final error) => Text('$error'),
///       QueryData(:final data) => TodoList(data),
///       _ => SizedBox.shrink(),
///     };
///   }
/// }
/// ```
mixin QueryMixin<W extends StatefulWidget> on State<W> {
  final List<QueryHandle<dynamic>> _queries = [];
  final List<MutationHandle<dynamic, dynamic>> _mutations = [];
  _AppLifecycleObserver? _lifecycleObserver;

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
    _lifecycleObserver = _AppLifecycleObserver(_onAppResumed);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  @override
  void dispose() {
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    }
    for (final q in _queries) {
      q.dispose();
    }
    for (final m in _mutations) {
      m.dispose();
    }
    super.dispose();
  }

  void _onAppResumed() {
    for (final q in _queries) {
      q.refetchIfStale();
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
  QueryHandle<T> query<T>(
    List<dynamic> key,
    Future<T> Function() queryFn, {
    Duration stale = Duration.zero,
    Duration gcTime = const Duration(minutes: 5),
    bool refetchOnMount = true,
    bool enabled = true,
    T? placeholderData,
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
    );
    _queries.add(handle);
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
  MutationHandle<TData, TInput> mutation<TData, TInput>(
    Future<TData> Function(TInput input) mutationFn, {
    List<List<dynamic>>? invalidates,
    void Function(TData data)? onSuccess,
    void Function(Object error, void Function() rollback)? onError,
    void Function(TInput input)? optimisticUpdate,
  }) {
    final handle = MutationHandle<TData, TInput>(
      mutationFn: mutationFn,
      client: _queryClient,
      onStateChanged: _safeSetState,
      invalidates: invalidates,
      onSuccess: onSuccess,
      onError: onError,
      optimisticUpdate: optimisticUpdate,
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

// ---------------------------------------------------------------------------
// App lifecycle observer
// ---------------------------------------------------------------------------

class _AppLifecycleObserver extends WidgetsBindingObserver {
  _AppLifecycleObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
