# Vigil — TanStack Query Architecture Port Plan

> Derived from TanStack Query source analysis. Preserves Vigil's mixin API.
> Each phase is a standalone increment that can ship and be tested independently.

---

## Phase 1: Subscribable + NotifyManager (Foundations)

### Why first
Everything else builds on these two primitives. TanStack Query's entire event system uses Subscribable, and NotifyManager is what prevents cascading rebuilds when multiple queries invalidate at once.

### 1a. Subscribable<T> base class

**New file**: `lib/src/core/subscribable.dart`

```dart
abstract class Subscribable<T extends Function> {
  final _listeners = <T>{};

  /// Returns an unsubscribe function.
  VoidCallback subscribe(T listener) {
    _listeners.add(listener);
    onSubscribe();
    return () {
      _listeners.remove(listener);
      onUnsubscribe();
    };
  }

  bool get hasListeners => _listeners.isNotEmpty;

  @protected
  void onSubscribe() {}

  @protected
  void onUnsubscribe() {}
}
```

~30 lines. Will be extended by: QueryCache (replacing raw Map), MutationCache, QueryObserver, FocusManager, OnlineManager.

### 1b. NotifyManager singleton

**New file**: `lib/src/core/notify_manager.dart`

Responsibilities:
- `batch(VoidCallback callback)` — queue notifications during a transaction, flush once at end
- `schedule(VoidCallback callback)` — default: `WidgetsBinding.instance.addPostFrameCallback`
- Pluggable `scheduleFn` and `batchNotifyFn` for testing

```dart
class NotifyManager {
  static final instance = NotifyManager();

  int _transactions = 0;
  final _queue = <VoidCallback>[];

  void batch(VoidCallback callback) {
    _transactions++;
    try {
      callback();
    } finally {
      _transactions--;
      if (_transactions == 0) _flush();
    }
  }

  void notify(VoidCallback callback) {
    if (_transactions > 0) {
      _queue.add(callback);
    } else {
      scheduleFn(callback);
    }
  }

  void _flush() {
    final queued = List<VoidCallback>.of(_queue);
    _queue.clear();
    scheduleFn(() {
      for (final cb in queued) {
        cb();
      }
    });
  }

  /// Override for testing (e.g. synchronous execution).
  void Function(VoidCallback) scheduleFn = _defaultSchedule;

  static void _defaultSchedule(VoidCallback cb) {
    // Post-frame callback batches with Flutter's rendering pipeline
    WidgetsBinding.instance.addPostFrameCallback((_) => cb());
  }
}
```

### Impact on existing code
- `QueryCacheEntry.notifyListeners()` → route through `NotifyManager.instance.notify()`
- `QueryClient.invalidateQueries()` → wrap in `NotifyManager.instance.batch()`
- `MutationHandle.mutate()` → wrap post-mutation invalidation in `batch()`

### Tests
- Batch suppresses intermediate notifications
- Flush delivers all queued notifications
- Multiple `invalidateQueries` calls in one `batch` → single notification per entry
- Pluggable `scheduleFn` for sync test execution

---

## Phase 2: FocusManager + OnlineManager (Pluggable Singletons)

### Why second
Retryer (Phase 4) needs to know online/offline state to pause/resume. The current lifecycle observer is hardcoded in the mixin. Extracting to singletons makes them testable and platform-overridable.

### 2a. FocusManager

**New file**: `lib/src/core/focus_manager.dart`

Extends `Subscribable<VoidCallback>`. Lazy: only attaches `WidgetsBindingObserver` when first subscriber arrives, detaches on last.

```dart
class FocusManager extends Subscribable<VoidCallback> {
  static final instance = FocusManager();

  bool _focused = true;

  bool get isFocused => _focused;

  @override
  void onSubscribe() {
    if (_listeners.length == 1) _attachPlatformListener();
  }

  @override
  void onUnsubscribe() {
    if (!hasListeners) _detachPlatformListener();
  }

  /// Override for React Native / desktop / tests.
  void setEventListener(void Function(void Function(bool focused) notify) setup) { ... }
}
```

### 2b. OnlineManager

**New file**: `lib/src/core/online_manager.dart`

Same pattern as FocusManager. Defaults to `true` (optimistic). For real connectivity, consumer plugs in `connectivity_plus`:

```dart
OnlineManager.instance.setEventListener((notify) {
  final sub = Connectivity().onConnectivityChanged.listen((result) {
    notify(result != ConnectivityResult.none);
  });
  return sub.cancel;
});
```

### Refactor QueryMixin
- Remove `_AppLifecycleObserver` class
- `initState` → subscribe to `FocusManager.instance` (refetch stale on focus)
- `initState` → subscribe to `OnlineManager.instance` (refetch on reconnect — future use)
- `dispose` → unsubscribe both

### Tests
- FocusManager attaches/detaches observer lazily
- OnlineManager defaults to online
- Focus change triggers subscriber callbacks
- Override with `setEventListener` works

---

## Phase 3: Dual-Axis Status Model

### Why third
The retryer (Phase 4) introduces `paused` as a fetch status. We need the dual-axis model in place before the retryer can dispatch pause/continue actions.

### Rework QueryState

Replace the current 4-class sealed hierarchy with a dual-axis model:

```dart
enum QueryStatus { pending, success, error }
enum FetchStatus { fetching, paused, idle }

sealed class QueryState<T> {
  const QueryState();

  // Data axis
  QueryStatus get status;
  T? get data;
  Object? get error;
  StackTrace? get stackTrace;
  int get dataUpdatedAt;       // millisecondsSinceEpoch, 0 = never
  bool get isInvalidated;

  // Network axis
  FetchStatus get fetchStatus;

  // Derived convenience getters
  bool get isPending => status == QueryStatus.pending;
  bool get isSuccess => status == QueryStatus.success;
  bool get isError => status == QueryStatus.error;
  bool get isFetching => fetchStatus == FetchStatus.fetching;
  bool get isPaused => fetchStatus == FetchStatus.paused;
  bool get isIdle => fetchStatus == FetchStatus.idle;
  bool get isLoading => isPending && isFetching;   // first load
  bool get isRefetching => isSuccess && isFetching; // background refetch
}
```

### Implementation approach: immutable data class

Single concrete `QueryState<T>` class with `copyWith()` rather than multiple sealed subtypes. The dual-axis model means the number of state combinations is large (3 × 3 = 9); sealed classes for each combination would be unwieldy. Keep sealed `QueryStatus` and `FetchStatus` enums for pattern matching.

```dart
class QueryState<T> {
  const QueryState({
    this.status = QueryStatus.pending,
    this.fetchStatus = FetchStatus.idle,
    this.data,
    this.error,
    this.stackTrace,
    this.dataUpdatedAt = 0,
    this.isInvalidated = false,
    this.fetchFailureCount = 0,
    this.fetchFailureReason,
  });

  // ... fields ...

  QueryState<T> copyWith({ ... });
}
```

### Action/Reducer pattern

```dart
enum QueryAction { fetch, success, error, invalidate, pause, resume, failed, setState }

QueryState<T> queryReducer<T>(QueryState<T> state, QueryAction action, payload) {
  return switch (action) {
    QueryAction.fetch => state.copyWith(fetchStatus: FetchStatus.fetching, ...),
    QueryAction.success => state.copyWith(status: QueryStatus.success, data: payload, fetchStatus: FetchStatus.idle, ...),
    QueryAction.error => state.copyWith(status: QueryStatus.error, error: payload, fetchStatus: FetchStatus.idle, ...),
    QueryAction.invalidate => state.copyWith(isInvalidated: true),
    QueryAction.pause => state.copyWith(fetchStatus: FetchStatus.paused),
    QueryAction.resume => state.copyWith(fetchStatus: FetchStatus.fetching),
    QueryAction.failed => state.copyWith(fetchFailureCount: state.fetchFailureCount + 1, ...),
    QueryAction.setState => ...,
  };
}
```

State transitions are synchronous and pure. This makes every state change testable in isolation.

### Migration of existing pattern matching

Users currently write:
```dart
switch (query.state) {
  QueryLoading() => ...,
  QueryData(:final data) => ...,
  QueryError(:final error) => ...,
  QueryInitial() => ...,
}
```

With dual-axis, they'd write:
```dart
switch (query.state) {
  QueryState(isLoading: true) => ...,       // pending + fetching
  QueryState(isError: true, :final error) => ...,
  QueryState(isSuccess: true, :final data) => ...,
  _ => ...,                                  // pending + idle (disabled)
}
```

Or use the convenience getters directly:
```dart
if (query.isLoading) return CircularProgressIndicator();
if (query.isError) return Text('${query.error}');
return TodoList(query.data as List<Todo>);
```

### Update QueryHandle and QueryCacheEntry
- `QueryCacheEntry` stores `QueryState` instead of separate `data`/`error`/`fetchedAt` fields
- `QueryHandle._state` uses the new `QueryState<T>`
- `dispatch()` method on QueryHandle calls the reducer and notifies

### Tests
- Reducer produces correct state for every action
- `isLoading` = pending + fetching
- `isRefetching` = success + fetching
- `copyWith` preserves unchanged fields
- Background refetch while showing stale data: `status: success, fetchStatus: fetching`

---

## Phase 4: Retryer (Retry + Exponential Backoff + Jitter)

### Why fourth
With dual-axis status and OnlineManager in place, the retryer can dispatch `pause`/`resume`/`failed` actions and check online status.

### New file: `lib/src/core/retryer.dart`

```dart
class Retryer<T> {
  Retryer({
    required Future<T> Function() fn,
    required void Function() onSuccess,
    required void Function(Object error) onError,
    required void Function() onFailed,   // non-terminal failure (will retry)
    required void Function() onPause,
    required void Function() onContinue,
    required bool Function() canRun,     // online + focus check
    int retry = 3,
    Duration Function(int attempt)? retryDelay,
    bool Function(Object error)? shouldRetry,
    this.networkMode = NetworkMode.online,
  });
}
```

### Defaults
- **Retry count**: 3 (queries), 0 (mutations)
- **Retry delay**: Exponential backoff with jitter:

```dart
Duration defaultRetryDelay(int attempt) {
  final base = Duration(milliseconds: math.min(1000 * math.pow(2, attempt).toInt(), 30000));
  // Full jitter: uniform random in [0, base]
  final jitter = Duration(milliseconds: _random.nextInt(base.inMilliseconds + 1));
  return jitter;
}
```

The **full jitter** strategy (from the AWS Architecture Blog) picks a random value between 0 and the exponential cap. This decorrelates retries from multiple callers hitting the same endpoint. Compared to "equal jitter" (half base + half random), full jitter produces lower average delay and better spread under contention.

Attempt progression with full jitter:
| Attempt | Base delay | Jitter range |
|---------|-----------|--------------|
| 0       | 1s        | [0, 1s]      |
| 1       | 2s        | [0, 2s]      |
| 2       | 4s        | [0, 4s]      |
| 3       | 8s        | [0, 8s]      |
| 4       | 16s       | [0, 16s]     |
| 5+      | 30s       | [0, 30s]     |

### `shouldRetry` predicate
- Default: always retry (any error)
- User can provide a predicate: e.g. don't retry 4xx HTTP errors, only retry on network/timeout

### Execution flow

```
start()
  ├── canRun()?
  │    ├── no → dispatch(pause) → wait for online/focus → dispatch(resume) → retry
  │    └── yes → run fn()
  │         ├── success → resolve promise → onSuccess()
  │         └── error
  │              ├── shouldRetry(error) && attempt < maxRetries?
  │              │    ├── yes → onFailed() → wait(retryDelay(attempt)) → loop
  │              │    └── no → reject promise → onError()
  │              └── During wait: if offline → pause wait, resume on reconnect
  └── cancel() → abort, reject with CancelledException
```

### Pause/Resume mechanics
- When offline (or can't run), create a `Completer` that resolves when `OnlineManager` / `FocusManager` fires
- The retryer subscribes to both managers while paused, unsubscribes on resume
- `networkMode: always` skips the online check entirely
- `networkMode: offlineFirst` skips the online check for attempt 0 only

### NetworkMode enum

```dart
enum NetworkMode { online, always, offlineFirst }
```

### Cancellation

```dart
class CancellationToken {
  bool _cancelled = false;
  bool _consumed = false;

  /// Reading this marks the token as consumed (lazy tracking).
  bool get isCancelled {
    _consumed = true;
    return _cancelled;
  }

  /// Whether the consumer ever checked the token.
  bool get wasConsumed => _consumed;

  void cancel() => _cancelled = true;
}
```

Pass to `queryFn` via a context object. If consumed, cancel immediately on last observer unsubscribe. If not consumed, let the fetch complete for caching.

### Integration with QueryCacheEntry
- `_executeFetch` creates a `Retryer` and delegates to it
- Retryer dispatches `pause`/`resume`/`failed` actions on the query state
- Existing `_activeFetch` deduplication still works — the retryer's future is stored there

### New query/mutation options
```dart
query<T>(
  key, queryFn,
  // ... existing options ...
  retry: 3,                              // number of retries
  retryDelay: defaultRetryDelay,         // Duration Function(int attempt)
  shouldRetry: null,                     // bool Function(Object error)?
  networkMode: NetworkMode.online,       // online | always | offlineFirst
)
```

### Tests
- Retries 3 times by default, then errors
- Exponential backoff delays increase correctly
- Jitter produces values within [0, base] range (seed Random for determinism)
- `shouldRetry: (e) => false` → no retries
- `retry: 0` → no retries (mutation default)
- Cancel aborts in-flight fetch
- Pause when offline, resume when online
- `networkMode: always` ignores online status
- `networkMode: offlineFirst` tries once offline, then respects status
- `CancellationToken.wasConsumed` tracks lazy access

---

## Phase 5: Three-Layer Option Cascade

### Why fifth
With retry/network options added, we now have enough configuration surface that global and per-key defaults become valuable. This reduces boilerplate.

### QueryClient changes

```dart
class QueryClient {
  QueryClient({
    this.defaultQueryOptions = const QueryDefaults(),
    this.defaultMutationOptions = const MutationDefaults(),
  });

  final QueryDefaults defaultQueryOptions;
  final MutationDefaults defaultMutationOptions;

  // Per-key defaults (partial key match)
  final _queryDefaults = <List<dynamic>, QueryDefaults>{};

  void setQueryDefaults(List<dynamic> keyPrefix, QueryDefaults defaults) {
    _queryDefaults[keyPrefix] = defaults;
  }

  /// Resolve: global → per-key → per-call
  QueryDefaults resolveQueryOptions(List<dynamic> key, QueryDefaults perCall) {
    final perKey = _findMatchingDefaults(key);
    return defaultQueryOptions.merge(perKey).merge(perCall);
  }
}
```

### QueryDefaults data class

```dart
class QueryDefaults {
  const QueryDefaults({
    this.staleTime,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.shouldRetry,
    this.networkMode,
    this.refetchOnMount,
    this.refetchOnFocus,
    this.refetchOnReconnect,
  });

  QueryDefaults merge(QueryDefaults? other) {
    if (other == null) return this;
    return QueryDefaults(
      staleTime: other.staleTime ?? staleTime,
      gcTime: other.gcTime ?? gcTime,
      retry: other.retry ?? retry,
      // ... etc
    );
  }
}
```

### QueryMixin.query() changes
- Instead of passing raw options through, build a `QueryDefaults` from per-call params
- Call `client.resolveQueryOptions(key, perCallDefaults)` to get merged options
- Pass resolved options to `QueryHandle`

### Derived defaults
- `refetchOnReconnect` defaults to `true` unless `networkMode == NetworkMode.always`
- `enabled` defaults to `false` if `queryFn` is `null`

### Tests
- Global defaults apply when no per-call options
- Per-key defaults override global
- Per-call overrides per-key
- `merge` with null preserves existing values
- Partial key matching for per-key defaults

---

## Phase 6: Scoped Mutation Serialization

### Why sixth
With the retryer handling retry/pause, mutations need a queue to prevent race conditions on the same resource.

### MutationCache (new)

**New file**: `lib/src/core/mutation_cache.dart`

```dart
class MutationCache extends Subscribable<void Function(MutationCacheEvent)> {
  final _mutations = <MutationHandle>[];
  final _scopes = <String, List<MutationHandle>>{};
  int _nextId = 0;

  bool canRun(MutationHandle mutation) {
    if (mutation.scope == null) return true;
    final queue = _scopes[mutation.scope];
    if (queue == null) return true;
    final firstPending = queue.firstWhereOrNull((m) => m.state.isPending);
    return firstPending == null || firstPending == mutation;
  }

  void runNext(String scope) {
    final queue = _scopes[scope];
    final next = queue?.firstWhereOrNull((m) => m.state.isPaused);
    next?.resume();
  }
}
```

### Mutation scope option
```dart
mutation<TData, TInput>(
  mutationFn,
  scope: 'todo-updates',  // mutations with same scope run serially
)
```

### Tests
- Two mutations with same scope → second waits for first
- Two mutations with different scopes → run concurrently
- After first completes, second starts automatically
- Null scope → no serialization

---

## Phase 7: Refetch Interval (Polling)

### Why seventh
Builds on FocusManager (pause when backgrounded) and OnlineManager (pause when offline).

### QueryHandle changes

```dart
query<T>(
  key, queryFn,
  refetchInterval: Duration(seconds: 30),
  refetchIntervalInBackground: false,
)
```

- `Timer.periodic` fires refetches
- Pauses when `FocusManager.isFocused == false` (unless `refetchIntervalInBackground`)
- Pauses when `OnlineManager.isOnline == false`
- Timer resets on manual refetch
- Timer disposed with handle

### Tests
- Refetches at the configured interval
- Pauses when backgrounded (default)
- Continues when `refetchIntervalInBackground: true`
- Pauses when offline
- Disposes cleanly

---

## Phase 8: Infinite Queries

### Why last
Most complex feature. Builds on everything above (retryer, dual-axis state, caching).

### InfiniteQueryHandle<T, P>

Extends the query system with pagination. Uses the same cache entry but stores `InfiniteQueryData`:

```dart
class InfiniteQueryData<T, P> {
  final List<T> pages;
  final List<P> pageParams;
}
```

### API

```dart
late final todos = infiniteQuery<List<Todo>, int>(
  ['todos'],
  (pageParam) => api.fetchTodos(page: pageParam),
  initialPageParam: 1,
  getNextPageParam: (lastPage, allPages) => lastPage.length == 20 ? allPages.length + 1 : null,
  getPreviousPageParam: (firstPage, allPages) => allPages.length > 1 ? 1 : null,
  maxPages: 10,  // FIFO eviction
);

// Usage:
todos.fetchNextPage();
todos.fetchPreviousPage();
todos.hasNextPage; // derived from getNextPageParam returning non-null
todos.hasPreviousPage;
```

### Behavior injection
Following TanStack's approach: inject custom fetch behavior rather than subclassing Query. The infinite query behavior replaces the fetch function to handle page accumulation, direction-based fetching, and refetch-all-pages logic.

### Tests
- Fetches initial page
- `fetchNextPage` appends
- `fetchPreviousPage` prepends
- `hasNextPage` / `hasPreviousPage` derived correctly
- Refetch re-fetches all existing pages sequentially
- `maxPages` evicts oldest pages

---

## File Structure After All Phases

```
lib/
├── vigil.dart
└── src/
    ├── core/
    │   ├── subscribable.dart          # Phase 1
    │   ├── notify_manager.dart        # Phase 1
    │   ├── focus_manager.dart         # Phase 2
    │   ├── online_manager.dart        # Phase 2
    │   ├── retryer.dart               # Phase 4
    │   ├── cancellation_token.dart    # Phase 4
    │   ├── network_mode.dart          # Phase 4
    │   ├── query_defaults.dart        # Phase 5
    │   └── mutation_cache.dart        # Phase 6
    ├── query_client.dart              # Modified: Phases 1,5
    ├── query_cache_entry.dart         # Modified: Phases 1,3,4
    ├── query_handle.dart              # Modified: Phases 3,4,5,7
    ├── query_state.dart               # Rewritten: Phase 3
    ├── query_mixin.dart               # Modified: Phases 2,5,7,8
    ├── mutation_handle.dart           # Modified: Phases 4,5,6
    ├── mutation_state.dart            # Minor updates
    ├── query_client_provider.dart     # Unchanged
    └── infinite_query_handle.dart     # Phase 8
```

---

## Cross-Cutting Concerns

### Testing strategy
- Each phase includes its own unit tests
- Retryer tests use a seeded `Random` for deterministic jitter verification
- NotifyManager tests use synchronous `scheduleFn` override
- FocusManager/OnlineManager tests use `setEventListener` override
- Existing tests updated as APIs evolve (especially Phase 3 state migration)

### Breaking changes
- **Phase 3 is the big one**: `QueryState` sealed class hierarchy → dual-axis data class. All `switch` expressions on `QueryState` break. This is intentional — the dual-axis model is fundamental.
- All other phases add new capabilities without removing existing API surface.

### What we're NOT porting
- **Tracked properties (Proxy)** — not available in Dart; use explicit `select()` instead (stretch goal)
- **Structural sharing** — less critical in Flutter than React; defer to stretch goals
- **Thenable / Suspense** — React-specific
- **Hydration / Dehydration** — defer until persistence adapter is needed
- **Builder widgets** — keeping the mixin API per user decision
