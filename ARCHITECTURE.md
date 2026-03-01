# Vigil Architecture

> A deep dive into how Vigil works, why it's designed the way it is, and how the
> pieces fit together. Written for contributors and curious users — no prior
> TanStack Query knowledge required.

---

## Table of Contents

1. [The Big Idea](#the-big-idea)
2. [Monorepo Layout](#monorepo-layout)
3. [Layer Cake: How the Code is Organized](#layer-cake-how-the-code-is-organized)
4. [The Dual-Axis State Model](#the-dual-axis-state-model)
5. [Core Primitives](#core-primitives)
6. [The Query Lifecycle](#the-query-lifecycle)
7. [Retry with Exponential Backoff + Jitter](#retry-with-exponential-backoff--jitter)
8. [The Three-Layer Option Cascade](#the-three-layer-option-cascade)
9. [Mutations](#mutations)
10. [Refetch Interval (Polling)](#refetch-interval-polling)
11. [Infinite Queries (Pagination)](#infinite-queries-pagination)
12. [Integration with Flutter](#integration-with-flutter)
13. [Key Design Decisions](#key-design-decisions)

---

## The Big Idea

Every app fetches server data. The naive approach — fetch in `initState`, store
in a local variable, show a spinner — works until it doesn't:

- **Two screens show the same data.** You update it on one screen, navigate to
  the other, and see stale data. Now you need a shared cache.
- **The user's network drops.** Your fetch fails, the screen shows an error, and
  there's no recovery path. Now you need retries.
- **The user backgrounds the app for 10 minutes.** The data they see when they
  return is ancient. Now you need refetch-on-focus.
- **A list endpoint returns 500 items.** You only want 20 at a time. Now you
  need pagination.

Vigil solves all of these with a single coherent model: **server state is a
cache that stays in sync with the source of truth (the server) via automatic,
configurable fetching.**

The mental model:

```
  Server (source of truth)
     |
     v
  +--------------------------------------+
  |          QueryClient (cache)         |
  |  +---------+  +---------+  +-----+  |
  |  | ["todos"]|  |["user",1]|  | ... |  |
  |  +---------+  +---------+  +-----+  |
  +--------------------------------------+
     |              |
     v              v
  Widget A       Widget B       <-- both see the same cached data
```

When Widget A fetches `["todos"]`, the result is cached. When Widget B later
asks for `["todos"]`, it gets the cached data instantly and optionally triggers
a background refetch if the data is stale. When a mutation invalidates
`["todos"]`, *both* widgets are notified and re-render.

---

## Monorepo Layout

```
vigil/
├── pubspec.yaml                    # Workspace root
├── ARCHITECTURE.md                 # You are here
├── PLAN.md                         # Implementation plan (historical)
├── TODO.md                         # Planned features
│
└── packages/
    └── vigil/                      # Core library
        ├── pubspec.yaml
        ├── analysis_options.yaml
        ├── lib/
        │   ├── vigil.dart          # Barrel export
        │   └── src/
        │       ├── core/           # Framework-agnostic primitives
        │       │   ├── subscribable.dart
        │       │   ├── notify_manager.dart
        │       │   ├── focus_manager.dart
        │       │   ├── online_manager.dart
        │       │   ├── network_mode.dart
        │       │   ├── retryer.dart
        │       │   ├── query_defaults.dart
        │       │   └── mutation_cache.dart
        │       │
        │       ├── query_client.dart
        │       ├── query_cache_entry.dart
        │       ├── query_handle.dart
        │       ├── query_state.dart
        │       ├── query_mixin.dart
        │       ├── query_client_provider.dart
        │       │
        │       ├── mutation_handle.dart
        │       ├── mutation_state.dart
        │       │
        │       ├── infinite_query_data.dart
        │       └── infinite_query_handle.dart
        │
        └── test/
            ├── subscribable_test.dart
            ├── notify_manager_test.dart
            ├── online_manager_test.dart
            ├── retryer_test.dart
            ├── query_state_test.dart
            ├── query_cache_entry_test.dart
            ├── query_client_test.dart
            ├── query_handle_test.dart
            ├── query_mixin_test.dart
            ├── mutation_handle_test.dart
            ├── mutation_state_test.dart
            ├── mutation_cache_test.dart
            ├── refetch_interval_test.dart
            └── infinite_query_test.dart
```

The workspace uses Dart's native workspace feature (`resolution: workspace`).
Future packages (e.g. `vigil_devtools`) are added as siblings under `packages/`
with shared dependency resolution.

---

## Layer Cake: How the Code is Organized

The code separates into three layers. Each layer only depends on layers below
it — never above.

```
+-----------------------------------------------------+
|  Layer 3: Flutter Integration                       |
|  QueryMixin, QueryClientProvider, FocusManager      |
|  (knows about Widget, State, BuildContext)           |
+--------------------------+--------------------------+
|  Layer 2: Handles (User-facing API)                 |
|  QueryHandle, MutationHandle, InfiniteQueryHandle   |
|  (knows about state, lifecycle, refetching)         |
+--------------------------+--------------------------+
|  Layer 1: Core (Framework-agnostic)                 |
|  Subscribable, NotifyManager, OnlineManager         |
|  Retryer, QueryClient, QueryCacheEntry              |
|  QueryState, MutationCache, QueryDefaults           |
|  (pure Dart, no Flutter imports)                    |
+-----------------------------------------------------+
```

**Why this matters:** The core layer can be tested without Flutter. It can also
be reused in non-Flutter Dart contexts (CLI tools, server-side). The Flutter
integration layer is a thin adapter that wires the core into the widget tree.

---

## The Dual-Axis State Model

This is the single most important concept in Vigil. If you understand this,
everything else falls into place.

### The Problem with Single-Axis State

A naive state model has four states: `initial -> loading -> data | error`. This
seems fine until you try to represent **"I have data from 5 minutes ago, and
I'm fetching fresh data in the background."** You can't — you're either
`loading` or `data`, never both.

### Two Independent Axes

Vigil tracks two things separately:

```
Data axis (QueryStatus)          Network axis (FetchStatus)
-----------------------          --------------------------
pending  - no data yet           fetching - request in flight
success  - have data             paused   - waiting for network
error    - last fetch failed     idle     - nothing happening
```

These combine into a 3x3 matrix. The most useful combinations:

| Status    | FetchStatus | Meaning                                | Getter        |
|-----------|-------------|----------------------------------------|---------------|
| pending   | fetching    | First load (no data, loading)          | `isLoading`   |
| pending   | idle        | Disabled query (no data, not fetching) | -             |
| success   | idle        | Fresh data, at rest                    | `isSuccess`   |
| success   | fetching    | Stale data, refreshing in background   | `isRefetching`|
| error     | idle        | Failed, showing error                  | `isError`     |
| error     | fetching    | Failed, retrying                       | -             |
| *any*     | paused      | Waiting for network connectivity       | `isPaused`    |

### In Code

```dart
class QueryState<T> {
  final QueryStatus status;      // data axis
  final FetchStatus fetchStatus; // network axis
  final T? data;
  final Object? error;
  // ...
}
```

Pattern matching in widgets:

```dart
switch (query.state) {
  QueryState(isLoading: true) => CircularProgressIndicator(),
  QueryState(isError: true, :final error) => Text('$error'),
  QueryState(isSuccess: true, :final data!) => TodoList(data),
  _ => SizedBox.shrink(),
}
```

### Why Not Sealed Classes?

The original Vigil used a sealed class hierarchy (`QueryInitial`, `QueryLoading`,
`QueryData`, `QueryError`). This was replaced because:

1. **9 combinations can't be modeled with 4 classes.** You'd need
   `QueryDataRefetching`, `QueryErrorRetrying`, `QueryDataPaused`, etc. The
   class explosion is unsustainable.
2. **copyWith is cleaner than reconstructing.** State transitions only change
   one or two fields; `copyWith` expresses this naturally.
3. **The axes are orthogonal.** Treating them as independent fields, not as
   subtypes, is the correct domain model.

---

## Core Primitives

### Subscribable

**File:** `core/subscribable.dart`

The foundational pub/sub base class. Nearly every reactive component extends it.

```dart
class Subscribable<T extends Function> {
  void Function() subscribe(T listener);  // returns unsubscribe fn
  bool get hasListeners;
  int get listenerCount;
  void onSubscribe() {}   // override for setup
  void onUnsubscribe() {} // override for teardown
}
```

**Why it exists:** Consistent subscription lifecycle across the entire system.
The `onSubscribe`/`onUnsubscribe` hooks enable lazy resource management — for
example, `FocusManager` only attaches a `WidgetsBindingObserver` when its first
subscriber arrives and detaches it when the last one leaves.

**Key detail:** `listeners` returns a defensive *copy* of the listener set. This
allows listeners to unsubscribe themselves during notification without causing
concurrent-modification errors.

### NotifyManager

**File:** `core/notify_manager.dart`

Batches notifications to prevent cascading rebuilds.

**The problem it solves:** Calling `invalidateQueries(['todos'])` might match 5
cache entries. Without batching, each entry notifies its listeners immediately,
causing 5 `setState` calls and 5 widget rebuilds — all in the same frame.

**How it works:**

```
invalidateQueries(['todos'])
  +-- NotifyManager.batch(() {
        entry1.invalidate()  ->  notify() queued
        entry2.invalidate()  ->  notify() queued
        entry3.invalidate()  ->  notify() queued
      })
      +-- batch ends -> flush all 3 at once -> 1 scheduleFn call
```

The `scheduleFn` is pluggable:
- **Default:** Execute synchronously (suitable for tests and non-Flutter)
- **Flutter adapter:** Replace with `addPostFrameCallback` to coalesce with the
  rendering pipeline

Batches can nest. Only the outermost batch triggers a flush:

```dart
NotifyManager.instance.batch(() {
  // outer batch
  NotifyManager.instance.batch(() {
    // inner batch - won't flush yet
    notify(a);
  });
  notify(b);
}); // <-- flush happens here (a and b together)
```

### FocusManager & OnlineManager

**Files:** `core/focus_manager.dart`, `core/online_manager.dart`

Pluggable singletons that track app focus and network connectivity.

```
+------------------+       +-------------------+
|   FocusManager   |       |  OnlineManager    |
|                  |       |                   |
| isFocused: bool  |       | isOnline: bool    |
| subscribe()      |       | subscribe()       |
| setFocused()     |       | setOnline()       |
| setEventListener |       | setEventListener  |
+------------------+       +-------------------+
       |                          |
       v                          v
  Refetch stale             Pause/resume
  queries on                retries and
  app resume                polling
```

**Why singletons?** Focus and connectivity are inherently global state. There's
one app, one network connection. Making them singletons with `setEventListener`
overrides keeps the core testable while allowing platform-specific listeners.

**Lazy attachment:** The platform listener (e.g. `WidgetsBindingObserver`) is
only attached when the first subscriber arrives. If no queries are active, no
system resources are consumed.

**OnlineManager defaults to `true`** (optimistic). This means if you don't plug
in a connectivity listener, Vigil assumes you're always online and never pauses
fetches. To get real connectivity awareness:

```dart
OnlineManager.instance.setEventListener((onOnlineChanged) {
  final sub = Connectivity().onConnectivityChanged.listen((result) {
    onOnlineChanged(result != ConnectivityResult.none);
  });
  return sub.cancel;
});
```

---

## The Query Lifecycle

### Cache Entries and Deduplication

**File:** `query_cache_entry.dart`

Every unique query key maps to exactly one `QueryCacheEntry`. The entry stores:

- `data` — the cached result (untyped; callers cast via generics)
- `error` / `stackTrace` — last fetch error
- `dataUpdatedAt` — timestamp of last successful fetch (millisecondsSinceEpoch)
- `isInvalidated` — explicitly marked stale
- listeners — a set of callbacks (one per `QueryHandle` observing this entry)

**Fetch deduplication** is the critical behavior: if Widget A triggers a fetch
for `["todos"]` and Widget B mounts a moment later requesting the same key, the
second call reuses the in-flight future. Only one network request fires.

```
Widget A: fetch(["todos"]) -+
                             +--> single HTTP request
Widget B: fetch(["todos"]) -+
```

This happens in `QueryCacheEntry.fetch()`:

```dart
Future<void> fetch(queryFn, ...) {
  _activeFetch ??= _executeFetch(queryFn, ...);
  return _activeFetch!;
}
```

The `??=` operator is the entire deduplication mechanism.

### QueryHandle: The Observer

**File:** `query_handle.dart`

A `QueryHandle<T>` is the user-facing object returned by `query()`. It observes
a `QueryCacheEntry` and maintains a typed `QueryState<T>`.

```
QueryMixin.query()
  +-- creates QueryHandle<T>
        +-- registers listener on QueryCacheEntry
        +-- computes initial QueryState<T>
        +-- maybe triggers auto-fetch
```

**The observer pattern** decouples the cache from the UI. Multiple handles can
observe the same cache entry. Each handle has its own configuration (stale time,
retry settings, etc.) but they all share the same underlying data.

**Initial state computation** follows a priority waterfall:

```
Has cached data?
  +-- Yes -> status: success, maybe refetch if stale
  +-- No
      Has cached error?
        +-- Yes -> status: error, maybe retry if enabled
        +-- No
            Has placeholder data?
              +-- Yes -> status: success (placeholder), fetch real data
              +-- No
                  Enabled?
                    +-- Yes -> status: pending, fetchStatus: fetching
                    +-- No  -> status: pending, fetchStatus: idle
```

**State propagation:** When the cache entry changes (data arrives, error occurs,
invalidation), the handle's `_onCacheEntryChanged` method recomputes the state
and calls `_onStateChanged` — which in the mixin triggers `setState`.

### Staleness and Garbage Collection

**Staleness** is time-based. A cache entry is "stale" if
`now - dataUpdatedAt >= staleTime` or if it's been explicitly invalidated.

```
staleTime = 5 minutes

  fetch ---------- 5 min ----------> stale
  <---- fresh ---->                   |
                                      v
                                next mount triggers
                                background refetch
```

**Stale-while-revalidate**: When a handle mounts and finds stale data, it
*shows the stale data immediately* (no loading spinner) and refetches in the
background. The state is `status: success, fetchStatus: fetching` — the
`isRefetching` state from the dual-axis model.

**Garbage collection** uses a timer-based ref-counting approach:

1. Each listener (handle) registration cancels the GC timer.
2. When the last listener unsubscribes, a GC timer starts (`gcTime`, default 5
   minutes).
3. If no new listeners arrive before the timer fires, the entry is evicted from
   the cache.
4. If a new listener arrives, the timer is cancelled and the entry stays alive.

This means cached data persists for `gcTime` after the last widget using it
unmounts. If the user navigates back, they see cached data instantly.

```
Widget mounts      Widget unmounts       GC timer fires
     |                    |                    |
     v                    v                    v
  listener++           listener--          entry evicted
  cancel GC timer      start GC timer       from cache
                       (5 min default)
```

---

## Retry with Exponential Backoff + Jitter

**File:** `core/retryer.dart`

When a fetch fails, the retryer automatically retries with increasing delays.

### Why Jitter Matters

Without jitter, if 100 clients all fail at the same time (e.g. server goes
down), they all retry at exactly the same intervals:

```
Without jitter (thundering herd):
  Client 1: ----fail--1s--retry--2s--retry--4s--retry
  Client 2: ----fail--1s--retry--2s--retry--4s--retry
  Client 3: ----fail--1s--retry--2s--retry--4s--retry
                       ^         ^         ^
                    100 requests hit server simultaneously each time
```

With **full jitter**, each client picks a random delay in `[0, cap]`:

```
With full jitter (spread load):
  Client 1: ----fail--0.3s--retry--1.7s--retry--3.1s--retry
  Client 2: ----fail--0.8s--retry--0.2s--retry--2.9s--retry
  Client 3: ----fail--0.1s--retry--1.9s--retry--0.5s--retry
                       ^            ^            ^
                    requests spread across the time window
```

### The Algorithm

```dart
Duration defaultRetryDelay(int attempt) {
  final cap = min(1000 * pow(2, attempt), 30000); // exponential cap
  return Duration(milliseconds: random.nextInt(cap + 1)); // full jitter
}
```

| Attempt | Cap   | Jitter Range |
|---------|-------|--------------|
| 0       | 1s    | [0, 1s]      |
| 1       | 2s    | [0, 2s]      |
| 2       | 4s    | [0, 4s]      |
| 3       | 8s    | [0, 8s]      |
| 4       | 16s   | [0, 16s]     |
| 5+      | 30s   | [0, 30s]     |

### Network Modes

The retryer respects three network modes:

- **`online`** (default) — Only fetch when `OnlineManager.isOnline` is true.
  If offline, pause and wait for reconnection.
- **`always`** — Ignore connectivity. Always attempt the fetch. Useful for
  local databases or service workers.
- **`offlineFirst`** — Try the first attempt regardless of connectivity (for
  offline-first caches). If it fails and we're offline, pause and wait.

### Pause/Resume Flow

```
start()
  +-- Check canFetch (based on networkMode)
  |    +-- Can't fetch -> dispatch(paused) -> wait for OnlineManager
  |    +-- Can fetch -> run queryFn()
  |         +-- Success -> done
  |         +-- Failure
  |              +-- shouldRetry(error) && attempt < maxRetries?
  |              |    +-- Yes -> wait(retryDelay) -> loop
  |              |    +-- No  -> give up -> dispatch(error)
  |              +-- During retry wait: if goes offline ->
  |                   pause delay timer, resume on reconnect
  +-- cancel() -> throw RetryerCancelledException
```

---

## The Three-Layer Option Cascade

**File:** `core/query_defaults.dart`

Configuration flows through three layers, each overriding the previous:

```
Layer 1: Global defaults          (set in QueryClient constructor)
  +-- Layer 2: Per-key defaults   (set via client.setQueryDefaults)
       +-- Layer 3: Per-call      (set in each query() call)
```

Example:

```dart
// Layer 1: All queries default to 1 minute stale time
final client = QueryClient(
  defaultQueryOptions: QueryDefaults(staleTime: Duration(minutes: 1)),
);

// Layer 2: Todo queries use 30 seconds
client.setQueryDefaults(['todos'], QueryDefaults(
  staleTime: Duration(seconds: 30),
));

// Layer 3: This specific query uses 10 seconds
query(['todos', 'urgent'], queryFn, stale: Duration(seconds: 10));
```

Result for `['todos', 'urgent']`: staleTime = 10s (per-call wins).
Result for `['todos', 'archive']`: staleTime = 30s (per-key wins).
Result for `['users']`: staleTime = 1m (global wins).

**Per-key matching uses prefix matching:** defaults set for `['todos']` apply to
`['todos']`, `['todos', 'active']`, `['todos', 1]`, etc. The most specific
(longest) matching prefix wins.

All fields in `QueryDefaults` are nullable. The `merge()` method uses
null-coalescing: a non-null value in the higher layer overrides the lower.

---

## Mutations

**File:** `mutation_handle.dart`

Mutations represent write operations (POST, PUT, DELETE). Unlike queries, they:

- Are **triggered manually** (not on mount)
- Have **no caching** (each `mutate()` call fires a fresh request)
- Support **optimistic updates** with rollback
- Can **invalidate queries** on success

```dart
final addTodo = mutation<Todo, CreateTodoInput>(
  (input) => api.createTodo(input),
  invalidates: [['todos']],
  optimisticUpdate: (input) {
    client.setQueryData(['todos'], (todos) => [...todos, input.toTodo()]);
  },
  onError: (error, rollback) => rollback(),
);
```

### Optimistic Updates and Rollback

The optimistic update flow:

```
mutate(input)
  |
  +-- 1. Snapshot current cache state (for rollback)
  +-- 2. Apply optimistic update (modify cache immediately)
  +-- 3. Start mutation (network request)
  |
  +-- Success:
  |    +-- 4a. Update state to MutationSuccess
  |    +-- 5a. Invalidate queries -> triggers refetch with real server data
  |    +-- 6a. Call onSuccess callback
  |
  +-- Error:
       +-- 4b. Update state to MutationError
       +-- 5b. Call onError(error, rollback)
                              |
                              +-- rollback() restores the snapshot
```

The snapshot/rollback mechanism captures the cache state *before* the optimistic
update. If the mutation fails, calling `rollback()` in `onError` restores the
pre-mutation data.

### Scoped Serialization

**File:** `core/mutation_cache.dart`

Without scoping, if a user double-taps a "Save" button, two mutations fire
concurrently. They might arrive at the server out of order, causing race
conditions.

**Scoped mutations** with the same `scope` string run serially (FIFO). The
second mutation waits for the first to complete before executing.

```dart
final saveTodo = mutation<void, Todo>(
  (todo) => api.updateTodo(todo),
  scope: 'todo-save',  // same scope = serial execution
);
```

```
Without scope:
  tap 1: ----mutate------------------complete
  tap 2: ------mutate--complete          <-- arrives first! Race condition.

With scope 'todo-save':
  tap 1: ----mutate------------------complete
  tap 2:                                     ----mutate----complete
                                    ^
                                    waits for tap 1
```

Mutations with *different* scopes (or no scope) run concurrently as expected.

---

## Refetch Interval (Polling)

Queries can be configured to refetch at a regular interval:

```dart
query(['stock', 'AAPL'], fetchPrice,
  refetchInterval: Duration(seconds: 30),
);
```

The interval timer:

- **Pauses** when the app is backgrounded (unless
  `refetchIntervalInBackground: true`)
- **Pauses** when the device goes offline
- **Resets** on manual `refetch()` calls
- **Stops** when the handle is disposed

```
Timer fires every 30s:
  --fetch--30s--fetch--30s--fetch--| app backgrounded |--focus--30s--fetch--
                                   ^ timer paused      ^ timer resumes
```

The handle subscribes to `FocusManager` and `OnlineManager` to know when to
pause and resume the timer. This avoids wasted network requests when the app
isn't visible or the device is offline.

---

## Infinite Queries (Pagination)

**Files:** `infinite_query_handle.dart`, `infinite_query_data.dart`

Infinite queries accumulate pages of data over time.

### Data Model

```dart
class InfiniteQueryData<T, P> {
  final List<T> pages;       // [page0, page1, page2, ...]
  final List<P> pageParams;  // [param0, param1, param2, ...]
}
```

`T` is the data type for each page, `P` is the page parameter type (often
`int` for page numbers, or `String` for cursor-based pagination).

### Page Param Derivation

Instead of hardcoding pagination logic, the user provides functions that derive
the next/previous page parameter from the data:

```dart
infiniteQuery<List<Todo>, int>(
  ['todos'],
  (page) => api.fetchTodos(page: page),
  initialPageParam: 1,
  getNextPageParam: (lastPage, allPages) =>
      lastPage.length == 20 ? allPages.length + 1 : null,  // null = no more
  getPreviousPageParam: (firstPage, allPages) =>
      allPages.length > 1 ? 1 : null,
);
```

**`hasNextPage`** and **`hasPreviousPage`** are derived booleans: they're `true`
when the respective `getPageParam` function returns non-null.

### Page Lifecycle

```
Initial mount:
  fetchNextPage() with initialPageParam
    +-- pages: [[page 0 data]]

User scrolls down:
  fetchNextPage()
    +-- pages: [[page 0], [page 1]]

User scrolls more:
  fetchNextPage()
    +-- pages: [[page 0], [page 1], [page 2]]

Invalidation -> refetchAllPages():
  Re-fetches page 0, then page 1, then page 2 sequentially
    +-- pages: [[fresh page 0], [fresh page 1], [fresh page 2]]
```

### MaxPages Eviction

To prevent memory from growing unboundedly, `maxPages` limits the number of
pages kept. When a new page is appended and the count exceeds `maxPages`, the
oldest page is dropped (FIFO):

```
maxPages: 2

pages: [[page 0], [page 1]]   <-- at limit
fetchNextPage()
pages: [[page 1], [page 2]]   <-- page 0 evicted
```

---

## Integration with Flutter

### QueryMixin

**File:** `query_mixin.dart`

The primary API surface. Mixed into a `State` subclass:

```dart
class _TodosState extends State<TodosPage> with QueryMixin {
  late final todos = query(['todos'], () => api.fetchTodos(),
    stale: Duration(minutes: 5),
  );

  @override
  Widget build(BuildContext context) {
    if (todos.isLoading) return CircularProgressIndicator();
    return ListView(children: todos.data!.map(TodoTile.new).toList());
  }
}
```

The mixin handles:

1. **Lifecycle management** — Subscribes to `FocusManager` in `initState`,
   disposes all handles in `dispose`.
2. **State synchronization** — Each handle's `onStateChanged` callback calls
   `setState(() {})`, triggering a rebuild.
3. **Factory methods** — `query()`, `mutation()`, `infiniteQuery()` create
   configured handles and track them for disposal.

### QueryClientProvider

An `InheritedWidget` that makes a `QueryClient` available to the widget subtree.
The mixin checks for an inherited client first, falling back to the static
singleton `QueryClient.instance`.

```dart
QueryClientProvider(
  client: queryClient,
  child: MaterialApp(...),
)
```

---

## Key Design Decisions

### 1. Mixin over Builder/Hook Pattern

Vigil uses `with QueryMixin` instead of `QueryBuilder` widgets or hook-style
APIs. This keeps the API surface minimal — you call `query()` in your state
class and access the result directly. No extra widget nesting, no hook rules.

### 2. Framework-Agnostic Core

Everything in `src/core/` is pure Dart with no Flutter imports (except
`FocusManager`, which needs `WidgetsBindingObserver`). The caching, retry, and
notification logic can be tested without a Flutter test harness and reused in
non-Flutter Dart contexts.

### 3. Singletons with Override Points

`NotifyManager.instance`, `FocusManager.instance`, and `OnlineManager.instance`
are singletons. This is intentional — they represent inherently global state
(notification scheduling, app focus, network connectivity). Each provides
override points (`scheduleFn`, `setEventListener`, `setOnline`) for testing and
platform adaptation.

### 4. `void Function()` over `VoidCallback`

The codebase uses `void Function()` directly instead of importing `VoidCallback`
from `dart:ui`. This removes a fragile dependency on the Flutter engine for
files that are otherwise pure Dart.

### 5. `QueryState<Never>` as Initial State

`QueryHandle` initializes its state as `const QueryState<Never>()`. This works
because Dart's generics are covariant: `QueryState<Never>` is a subtype of
`QueryState<T>` for all `T` (since `Never` is a subtype of every type). This
avoids the need for a nullable state field or a separate "uninitialized"
sentinel.

### 6. JSON-Serialized Cache Keys

Query keys like `['todos', 42]` are serialized to `'["todos",42]'` via
`jsonEncode`. This gives us:

- **Canonical ordering** — `['a', 'b']` always produces the same string
- **Cheap equality** — string comparison instead of deep list equality
- **Prefix matching** — invalidating `['todos']` (serialized `'["todos"]'`) can
  match `'["todos",42]'` via string prefix checking

### 7. Get-or-Create Cache Pattern

`QueryClient.getOrCreateEntry(key)` follows the get-or-create pattern: if a
cache entry exists for the key, return it; otherwise create a new one. This
means the first widget to request a key "builds" the entry, and subsequent
widgets share it. Combined with fetch deduplication, this ensures at most one
network request per unique key at any time.

### 8. Full Jitter over Equal Jitter

The retry delay uses the "full jitter" strategy (uniform random in `[0, cap]`)
rather than "equal jitter" (half base + half random). Full jitter produces
lower average delay and better load distribution under contention, as
demonstrated in the AWS Architecture Blog's analysis of exponential backoff
strategies.

### 9. Time-Based Staleness over Version Counters

Staleness is measured by comparing timestamps (`dataUpdatedAt` vs. `now`)
rather than version counters or ETags. This is simpler, works without server
cooperation, and handles clock skew gracefully (worst case: data is considered
stale slightly early or late, triggering an extra refetch — no correctness
issue).

### 10. Immutable State with copyWith

`QueryState` is immutable. State transitions produce a new instance via
`copyWith()`. This enables:

- **Equality comparison** — `_dispatch` can skip no-op updates
- **Safe reference sharing** — no risk of mutation
- **Debuggability** — each state is a snapshot that can be logged or diffed

The `copyWith` uses a closure pattern for nullable fields:
`T? Function()? data` instead of `T? data`. This distinguishes "not provided"
(parameter omitted, keep current value) from "set to null" (pass `() => null`).
