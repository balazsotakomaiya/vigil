# Vigil

[![pub version](https://img.shields.io/pub/v/vigil)](https://pub.dev/packages/vigil)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

TanStack Query for Flutter. Cached, stale-aware data fetching with a mixin-based
API — no code generation, no boilerplate, no ceremony.

```dart
class _TodosState extends State<TodosPage> with QueryMixin {
  late final todos = query<List<Todo>>(
    ['todos'],
    () => api.fetchTodos(),
    stale: Duration(minutes: 5),
  );

  @override
  Widget build(BuildContext context) {
    if (todos.isLoading) return CircularProgressIndicator();
    if (todos.isError) return Text('Something went wrong: ${todos.error}');
    return TodoList(todos.data!);
  }
}
```

---

## Table of Contents

- [Quick Start](#quick-start)
- [Why Vigil](#why-vigil)
- [Features](#features)
- [Platform Compatibility](#platform-compatibility)
- [Important Defaults](#important-defaults)
- [Core Concepts](#core-concepts)
  - [The Dual-Axis State Model](#the-dual-axis-state-model)
  - [Staleness and Caching](#staleness-and-caching)
- [Patterns](#patterns)
  - [Background Refetching](#background-refetching)
  - [Optimistic Updates](#optimistic-updates)
  - [Dependent Queries](#dependent-queries)
  - [Polling](#polling)
  - [Scoped Mutations](#scoped-mutations)
  - [Offline Support](#offline-support)
  - [Default Options Cascade](#default-options-cascade)
  - [Using Builders](#using-builders)
- [API Reference](#api-reference)
  - [`query()`](#query)
  - [`mutation()`](#mutation)
  - [`infiniteQuery()`](#infinitequery)
  - [`invalidateQueries()`](#invalidatequeries)
  - [QueryClient](#queryclient)
  - [QueryClientProvider](#queryclientprovider)
  - [QueryBuilder / MutationBuilder](#querybuilder--mutationbuilder)
- [Architecture](#architecture)
- [Development](#development)
- [License](#license)

---

## Quick Start

Add Vigil to your `pubspec.yaml`:

```yaml
dependencies:
  vigil: ^0.1.0
```

Wrap your app with a `QueryClientProvider`:

```dart
void main() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: MyApp(),
    ),
  );
}
```

Mix `QueryMixin` into any `State` and start fetching:

```dart
class _ProfileState extends State<ProfilePage> with QueryMixin {
  late final user = query<User>(
    ['user', widget.userId],
    () => api.fetchUser(widget.userId),
    stale: Duration(minutes: 10),
  );

  @override
  Widget build(BuildContext context) {
    if (user.isLoading) return CircularProgressIndicator();
    if (user.isError) return Text('Failed: ${user.error}');
    return Text(user.data!.name);
  }
}
```

That's it. Vigil handles caching, deduplication, retries, staleness, garbage collection, and refetch-on-focus automatically.

---

## Why Vigil

Every Flutter app fetches server data. You write a `fetchTodos()` in `initState`, store the result in a local variable, show a spinner — and then the edge cases pile up:

- Two screens show the same data, but only one is fresh.
- The network drops mid-request and the user sees a permanent error.
- The app is backgrounded for ten minutes and shows ancient data on resume.
- A list grows to 500 items and you need pagination.

You can solve each of these individually, or you can treat server state as what it actually is: **a cache that stays in sync with the source of truth.** That's what Vigil does.

## Features

| Feature | Description |
|---|---|
| **Stale-while-revalidate** | Show cached data instantly, refresh in the background |
| **Request deduplication** | Multiple widgets requesting the same key share a single fetch |
| **Automatic garbage collection** | Unused cache entries are evicted after a configurable timeout |
| **Retry with jitter** | Failed requests retry with exponential backoff and full jitter |
| **Optimistic updates** | Update the UI immediately, roll back on failure |
| **Mutations** | First-class write operations with invalidation and rollback |
| **Infinite queries** | Cursor and offset pagination with `fetchNextPage()` / `fetchPreviousPage()` |
| **Polling** | Refetch on an interval, with automatic pause when backgrounded or offline |
| **Network awareness** | Pause fetches when offline, resume on reconnect |
| **Focus refetching** | Refetch stale queries when the app returns to the foreground |
| **Scoped mutation serialization** | Prevent race conditions by serializing mutations with the same scope |
| **Three-layer option cascade** | Set defaults globally, per-key prefix, or per-call |

## Platform Compatibility

Vigil is pure Dart + Flutter. It works anywhere Flutter runs.

| Platform | Supported |
|---|---|
| Android | Yes |
| iOS | Yes |
| Web | Yes |
| macOS | Yes |
| Windows | Yes |
| Linux | Yes |

**Requirements:** Dart `^3.11.0`, Flutter `>=3.32.0`

---

## Important Defaults

Out of the box, Vigil is configured to be aggressive about keeping data fresh. This is intentional — it's better to start with fresh data and relax later than to start with stale data and not notice.

These are the defaults you should know about:

- **Queries are stale immediately.** The default `stale` time is `Duration.zero`. Every time a widget mounts with a query, it will trigger a background refetch — even if the data was just fetched a second ago. Set `stale` to a `Duration` that makes sense for your data.

- **Failed queries retry 3 times.** With exponential backoff and full jitter (randomized delays to avoid thundering herds). The max delay caps at 30 seconds.

- **Stale queries refetch automatically on mount.** When a widget mounts and finds stale cached data, it shows the cached data immediately (no loading spinner) and refetches in the background. You can disable this with `refetchOnMount: false`.

- **Stale queries refetch when the app resumes.** When the user switches back to your app, all mounted queries with stale data automatically refetch. This keeps data fresh after the user has been away.

- **Inactive queries are garbage collected after 5 minutes.** When the last widget observing a cache entry unmounts, a timer starts. If no widget re-subscribes within `gcTime` (default: 5 minutes), the entry is evicted. If the user navigates back before the timer fires, the cached data is still there.

- **Queries with no data fetch immediately.** If there's nothing in the cache for a key, the query fetches right away. If there *is* cached data, whether it refetches depends on whether the data is stale.

If you're seeing more network requests than expected, start by setting a stale time:

```dart
late final todos = query<List<Todo>>(
  ['todos'],
  () => api.fetchTodos(),
  stale: Duration(minutes: 5), // fresh for 5 minutes
);
```

---

## Core Concepts

### The Dual-Axis State Model

Most state models give you four states: initial, loading, data, error. That breaks down the moment you need to express *"I have data from five minutes ago and I'm refreshing in the background."*

Vigil tracks two axes independently:

```
Data axis (QueryStatus)         Network axis (FetchStatus)
-----------------------         --------------------------
pending  — no data yet          fetching — request in flight
success  — have data            paused   — waiting for network
error    — last fetch failed    idle     — nothing happening
```

The useful combinations:

| status  | fetchStatus | What it means | Convenience getter |
|---------|-------------|------|------|
| pending | fetching | First load — no data, loading | `isLoading` |
| success | idle | Fresh data, at rest | `isSuccess` |
| success | fetching | Showing cached data, refreshing in background | `isRefetching` |
| error | idle | Failed, showing error | `isError` |
| *any* | paused | Waiting for network connectivity | `isPaused` |

Most of the time, you only need the convenience getters on the handle:

```dart
if (todos.isLoading) ...    // pending + fetching
if (todos.isError) ...      // error state
if (todos.isRefetching) ... // success + fetching
```

For more nuanced control, access `todos.state` and use Dart pattern matching:

```dart
Widget build(BuildContext context) => switch (todos.state) {
  QueryState(isLoading: true) => Spinner(),
  QueryState(isError: true, :final error) => ErrorView(error),
  QueryState(isRefetching: true, :final data!) => TodoList(data, refreshing: true),
  QueryState(:final data!) => TodoList(data),
  _ => SizedBox.shrink(),
};
```

Both styles work — pick whichever reads better for your use case.

### Staleness and Caching

When you set `stale: Duration(minutes: 5)`, data is considered fresh for five minutes after it's fetched. During that window, mounting a new widget with the same key returns cached data with no network request.

After the stale time passes, the next mount shows the cached data immediately (no spinner) and refetches in the background. This is **stale-while-revalidate** — the same strategy used by HTTP caches and TanStack Query.

When the last widget using a cache entry unmounts, a garbage collection timer starts (default: 5 minutes). If no widget re-subscribes before it fires, the entry is evicted. If a widget mounts before then, the timer is cancelled and the entry stays alive.

```
Widget mounts      Widget unmounts       gcTime elapses
     │                    │                    │
     ▼                    ▼                    ▼
  entry created        GC timer starts      entry evicted
  or reused            (5 min default)       from cache
```

---

## Patterns

### Background Refetching

The most common pattern in Vigil: show cached data immediately, refresh silently.

```dart
late final todos = query<List<Todo>>(
  ['todos'],
  () => api.fetchTodos(),
  stale: Duration(minutes: 5),
);

@override
Widget build(BuildContext context) {
  if (todos.isLoading) return CircularProgressIndicator();
  if (todos.isError) return Text('${todos.error}');

  return Column(
    children: [
      if (todos.isRefetching) LinearProgressIndicator(), // subtle indicator
      Expanded(child: TodoList(todos.data!)),
    ],
  );
}
```

The user sees their data immediately. A thin progress bar lets them know a fresher version is on its way.

### Optimistic Updates

Update the UI immediately, roll back if the server rejects the change.

```dart
late final toggleTodo = mutation<void, Todo>(
  (todo) => api.updateTodo(todo.copyWith(done: !todo.done)),
  optimisticUpdate: (todo) {
    final client = QueryClient.instance;
    client.setQueryData<List<Todo>>(['todos'], (todos) =>
      todos.map((t) => t.id == todo.id ? t.copyWith(done: !t.done) : t).toList(),
    );
  },
  invalidates: [['todos']],
  onError: (error, rollback) => rollback(), // restores pre-mutation snapshot
);
```

The flow: snapshot the cache, apply your optimistic change, fire the mutation. If it fails, `rollback()` restores the snapshot. If it succeeds, the invalidation triggers a fresh fetch from the server.

### Dependent Queries

Use `enabled` to make one query wait for another.

```dart
late final user = query<User>(['user'], () => api.fetchUser());

late final posts = query<List<Post>>(
  ['posts', user.data?.id],
  () => api.fetchPosts(userId: user.data!.id),
  enabled: user.data != null, // only fetches once user data arrives
);

@override
Widget build(BuildContext context) {
  if (user.isLoading || posts.isLoading) return CircularProgressIndicator();
  return PostList(posts.data!);
}
```

### Polling

Refetch on a timer. The timer automatically pauses when the app is backgrounded
or the device goes offline.

```dart
late final stockPrice = query<double>(
  ['stock', 'AAPL'],
  () => api.fetchPrice('AAPL'),
  refetchInterval: Duration(seconds: 30),
);
```

### Scoped Mutations

Prevent race conditions when the same mutation can fire multiple times (e.g. rapid taps on a save button). Mutations with the same `scope` run one at a time.

```dart
late final saveDraft = mutation<void, Draft>(
  (draft) => api.saveDraft(draft),
  scope: 'save-draft', // second tap waits for first to finish
);
```

### Offline Support

Vigil supports three network modes:

| Mode | Behavior |
|---|---|
| `NetworkMode.online` | Only fetch when online. Pause and resume on reconnect. **(default)** |
| `NetworkMode.always` | Ignore connectivity. Useful for local databases. |
| `NetworkMode.offlineFirst` | Try the first fetch regardless. Pause retries if offline. |

To enable real connectivity tracking, plug in a listener:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

OnlineManager.instance.setEventListener((onOnlineChanged) {
  final sub = Connectivity().onConnectivityChanged.listen((result) {
    onOnlineChanged(result != ConnectivityResult.none);
  });
  return sub.cancel;
});
```

Without this, Vigil assumes you're always online (optimistic default).

### Default Options Cascade

Configuration flows through three layers, each overriding the one below:

```
Per-call options       →  highest priority
Per-key defaults       →  middle priority
Global defaults        →  lowest priority
```

```dart
// Global: all queries default to 1 minute stale time
final client = QueryClient(
  defaultQueryOptions: QueryDefaults(staleTime: Duration(minutes: 1)),
);

// Per-key: todo queries use 30 seconds
client.setQueryDefaults(['todos'], QueryDefaults(
  staleTime: Duration(seconds: 30),
));

// Per-call: this specific query uses 10 seconds
query(['todos', 'urgent'], fetchUrgent, stale: Duration(seconds: 10));
```

Per-key matching uses **prefix matching**: defaults set for `['todos']` apply to `['todos']`, `['todos', 42]`, `['todos', 'active']`, etc.

### Using Builders

If you prefer the builder pattern over reading handle properties directly, Vigil provides `QueryBuilder` and `MutationBuilder`:

```dart
class _TodosState extends State<TodosPage> with QueryMixin {
  late final todos = query<List<Todo>>(
    ['todos'],
    () => api.fetchTodos(),
    stale: Duration(minutes: 5),
  );

  @override
  Widget build(BuildContext context) {
    return QueryBuilder<List<Todo>>(
      query: todos,
      builder: (context, state, child) {
        if (state.isLoading) return CircularProgressIndicator();
        if (state.isError) return Text('${state.error}');
        return TodoList(state.data!);
      },
    );
  }
}
```

`MutationBuilder` works the same way — and since `MutationState` is a sealed class, exhaustive pattern matching is particularly clean:

```dart
MutationBuilder<Todo, String>(
  mutation: addTodo,
  builder: (context, state, child) => switch (state) {
    MutationIdle() => child!,
    MutationLoading() => CircularProgressIndicator(),
    MutationSuccess(:final data) => Text('Created: ${data.title}'),
    MutationError(:final error) => Text('Failed: $error'),
  },
  child: ElevatedButton(
    onPressed: () => addTodo.mutate('Buy milk'),
    child: Text('Add'),
  ),
)
```

Both builders accept a `child` parameter for subtrees that don't depend on the query/mutation state. You still need `QueryMixin` on your `State` — the builders are an organizational tool, not a replacement for the mixin.

---

## API Reference

### `query()`

Fetch and cache data. Returns a `QueryHandle<T>`.

```dart
late final todos = query<List<Todo>>(
  ['todos'],
  () => api.fetchTodos(),
);
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `key` | `List<dynamic>` | — | Cache key. Same key = same cache entry. |
| `queryFn` | `Future<T> Function()` | — | The async function that fetches data. |
| `stale` | `Duration` | `Duration.zero` | How long fetched data is considered fresh. |
| `gcTime` | `Duration` | `5 minutes` | How long an unused entry survives before eviction. |
| `refetchOnMount` | `bool` | `true` | Refetch stale data when a new widget mounts. |
| `enabled` | `bool` | `true` | Set `false` to disable automatic fetching. |
| `placeholderData` | `T?` | `null` | Data to show while the first fetch is in progress. |
| `retry` | `int` | `3` | Maximum retry attempts on failure. |
| `retryDelay` | `Duration Function(int)?` | exponential + jitter | Custom delay per attempt. |
| `shouldRetry` | `bool Function(Object)?` | `null` | Filter which errors are retryable. |
| `networkMode` | `NetworkMode` | `online` | `online`, `always`, or `offlineFirst`. |
| `refetchInterval` | `Duration?` | `null` | Polling interval. `null` disables polling. |
| `refetchIntervalInBackground` | `bool` | `false` | Keep polling when the app is backgrounded. |

**QueryHandle getters:**

| Getter | Type | Description |
|---|---|---|
| `state` | `QueryState<T>` | Full state object for pattern matching. |
| `data` | `T?` | Cached data, or `null`. |
| `error` | `Object?` | Error, or `null`. |
| `isLoading` | `bool` | No data yet, currently fetching. |
| `isError` | `bool` | In error state. |
| `isRefetching` | `bool` | Has data, fetching in background. |

**QueryHandle methods:**

| Method | Description |
|---|---|
| `refetch()` | Force a refetch regardless of staleness. |
| `refetchIfStale()` | Refetch only if the data is stale. |
| `setData(T Function(T) updater)` | Update cached data directly. |

---

### `mutation()`

Perform a write operation. Returns a `MutationHandle<TData, TInput>`.

```dart
late final addTodo = mutation<Todo, String>(
  (title) => api.createTodo(title),
  invalidates: [['todos']],
);

// In a callback:
addTodo.mutate('Buy groceries');
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `mutationFn` | `Future<TData> Function(TInput)` | — | The async write function. |
| `invalidates` | `List<List<dynamic>>?` | `null` | Query key prefixes to invalidate on success. |
| `onSuccess` | `void Function(TData)?` | `null` | Called after a successful mutation. |
| `onError` | `void Function(Object, void Function())?` | `null` | Called on failure. Second arg is a rollback function. |
| `optimisticUpdate` | `void Function(TInput)?` | `null` | Synchronous cache update applied before the mutation fires. |
| `scope` | `String?` | `null` | Mutations with the same scope run serially. |

**MutationHandle getters:**

| Getter | Type | Description |
|---|---|---|
| `state` | `MutationState<TData>` | Sealed type: `MutationIdle`, `MutationLoading`, `MutationSuccess`, `MutationError`. |
| `data` | `TData?` | Result data on success. |
| `error` | `Object?` | Error on failure. |
| `isMutating` | `bool` | Mutation is in flight. |
| `isError` | `bool` | Last mutation failed. |

---

### `infiniteQuery()`

Paginated fetching. Returns an `InfiniteQueryHandle<T, P>`.

```dart
late final todos = infiniteQuery<List<Todo>, int>(
  ['todos'],
  (page) => api.fetchTodos(page: page),
  initialPageParam: 1,
  getNextPageParam: (lastPage, allPages) =>
      lastPage.length == 20 ? allPages.length + 1 : null,
);
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `key` | `List<dynamic>` | — | Cache key. |
| `queryFn` | `Future<T> Function(P)` | — | Fetcher that receives a page parameter. |
| `initialPageParam` | `P` | — | Page parameter for the first page. |
| `getNextPageParam` | `P? Function(T, List<T>)` | — | Derive the next page param. Return `null` for no more pages. |
| `getPreviousPageParam` | `P? Function(T, List<T>)?` | `null` | Derive the previous page param. |
| `maxPages` | `int?` | `null` | Max pages kept in memory. Oldest pages are evicted (FIFO). |
| `stale` | `Duration` | `Duration.zero` | Stale time. |
| `enabled` | `bool` | `true` | Enable/disable auto-fetch. |

**InfiniteQueryHandle getters:**

| Getter | Type | Description |
|---|---|---|
| `pages` | `List<T>` | All fetched pages. |
| `data` | `InfiniteQueryData<T, P>?` | Pages and page params. |
| `hasNextPage` | `bool` | `getNextPageParam` returned non-null. |
| `hasPreviousPage` | `bool` | `getPreviousPageParam` returned non-null. |
| `isFetchingNextPage` | `bool` | Next page fetch in progress. |
| `isFetchingPreviousPage` | `bool` | Previous page fetch in progress. |

**InfiniteQueryHandle methods:**

| Method | Description |
|---|---|
| `fetchNextPage()` | Fetch the next page. |
| `fetchPreviousPage()` | Fetch the previous page. |
| `refetchAllPages()` | Re-fetch all existing pages sequentially. |
| `refetch()` | Force refetch of all pages. |

---

### `invalidateQueries()`

Mark cached queries as stale. Any mounted query matching the prefix will refetch immediately.

```dart
invalidateQueries(['todos']);            // Matches ['todos'], ['todos', 42], etc.
invalidateQueries(['todos', 'active']); // Only matches ['todos', 'active', ...]
```

---

### QueryClient

The global cache. Create one and provide it via `QueryClientProvider`.

```dart
final client = QueryClient(
  defaultQueryOptions: QueryDefaults(
    staleTime: Duration(minutes: 1),
    retry: 2,
  ),
);
```

| Method | Description |
|---|---|
| `getQueryData<T>(key)` | Read cached data for a key. |
| `setQueryData<T>(key, data)` | Write data into the cache directly. |
| `invalidateQueries(keyPrefix)` | Invalidate all entries matching a key prefix. |
| `removeQueries(keyPrefix)` | Remove entries from the cache entirely. |
| `setQueryDefaults(keyPrefix, defaults)` | Set default options for a key prefix. |
| `clear()` | Remove all cache entries. |

---

### QueryClientProvider

An `InheritedWidget` that provides a `QueryClient` to the widget tree.

```dart
QueryClientProvider(
  client: QueryClient(),
  child: MaterialApp(...),
)
```

The mixin looks for the nearest `QueryClientProvider` first, then falls back to `QueryClient.instance`.

---

### QueryBuilder / MutationBuilder

Optional convenience widgets for organizing your build method. See [Using Builders](#using-builders) for examples.

| Widget | Props | Description |
|---|---|---|
| `QueryBuilder<T>` | `query`, `builder`, `child?` | Rebuilds from `QueryState<T>`. |
| `MutationBuilder<TData, TInput>` | `mutation`, `builder`, `child?` | Rebuilds from `MutationState<TData>`. Exhaustive pattern matching since `MutationState` is sealed. |

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for a deep dive into how Vigil works —
the dual-axis state model, cache lifecycle, retry strategy, notification
batching, and all key design decisions with rationale.

### Monorepo structure

```
vigil/
├── pubspec.yaml                 # Workspace root
├── ARCHITECTURE.md
├── TODO.md
├── packages/
│   └── vigil/                   # Core library
│       ├── pubspec.yaml
│       ├── lib/
│       │   ├── vigil.dart       # Barrel export
│       │   └── src/
│       │       ├── core/        # Framework-agnostic primitives
│       │       ├── query_*.dart # Query handles, state, cache, client
│       │       ├── mutation_*.dart
│       │       └── infinite_*.dart
│       └── test/
```

---

## Development

```bash
# Get dependencies
cd packages/vigil && flutter pub get

# Run all tests
flutter test

# Run a specific test file
flutter test test/query_handle_test.dart

# Analyze
flutter analyze
```

### Adding a new feature

1. Core logic goes in `lib/src/core/` (pure Dart, no Flutter imports)
2. Handles go in `lib/src/` (user-facing API layer)
3. Export new public types from `lib/vigil.dart`
4. Add tests in `test/`

---

## License

MIT
