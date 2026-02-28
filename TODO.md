# Vigil — TODO

Planned features and improvements, roughly prioritized.

---

## `select` for derived / computed queries

- Add `select: R Function(T data)?` parameter to `query()`
- Returns a `QueryHandle<R>` instead of `QueryHandle<T>`
- Only triggers rebuilds when the selected portion changes (deep equality)
- Reduces unnecessary widget rebuilds for large data sets
- Consider memoization of the selector

## `prefetchQuery()` for cache warming

- Warm the cache before a widget mounts (e.g. on hover, or on the previous screen)
- `client.prefetchQuery(['todos'], () => api.fetchTodos())`
- Returns a `Future<void>` — no handle, no subscription
- The data is cached and available immediately when a widget later calls `query()` with the same key

## DevTools extension

- Build a Flutter DevTools extension showing:
  - All active cache entries with their keys, data, and status
  - Stale/fresh indicators with countdown timers
  - Active listeners per entry
  - Mutation history log
  - Manual invalidation / refetch controls
- Use the `dart:developer` extension APIs
- Separate package: `packages/vigil_devtools`

## Persistence adapter

- Serialize/deserialize cache to local storage (Hive, SharedPreferences, Isar)
- `QueryClient(persistor: HivePersistor())` — restores cache on cold start
- Selective persistence via key prefix filtering
- Consider async hydration timing (show stale persisted data while refetching)

## Structural sharing

- Only update references that actually changed (deep diff)
- Avoids unnecessary widget rebuilds when a refetch returns the same data
- Needs a configurable `structuralSharing: bool` flag (default on)
- Consider using `identical()` checks on sub-trees

## `staleTime` as a function

- Allow `stale: Duration Function(T data)?` in addition to `Duration`
- The function receives the current data and returns a dynamic stale time
- Use case: server-driven cache hints (e.g. API returns a `Cache-Control` header)

## Query key factories

- Type-safe key builder pattern to avoid stringly-typed keys:
  ```dart
  abstract class TodoKeys {
    static List<dynamic> all() => ['todos'];
    static List<dynamic> byId(int id) => ['todos', id];
    static List<dynamic> byFilter(String filter) => ['todos', 'filter', filter];
  }
  ```
- Could be a codegen step or just a documented pattern

## Hydration / dehydration for testing and SSR

- `client.dehydrate()` → serializable map of the entire cache
- `client.hydrate(map)` → restore cache from a serialized map
- Useful for pre-populating cache in tests without mocking
- Enables server-side rendering if Flutter ever supports it

## Web-specific focus events

- On web, `FocusManager` should listen to the `visibilitychange` DOM event
  via `dart:js_interop` instead of (or in addition to) `WidgetsBindingObserver`
- More reliable tab-switching detection than app lifecycle events

## Query cancellation

- Cancel in-flight queries when the handle is disposed
- Requires `CancellationToken` or `AbortController` pattern
- `queryFn` would receive a token: `Future<T> Function(CancelToken token)`
- Cancelled queries don't update the cache or trigger error state
