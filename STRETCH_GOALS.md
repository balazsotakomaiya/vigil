# Vigil — Stretch Goals

Features to implement in future iterations:

## `infiniteQuery()` for pagination
- Add `InfiniteQueryHandle<T>` with `fetchNextPage()` / `fetchPreviousPage()`
- `getNextPageParam` / `getPreviousPageParam` callbacks
- Accumulates pages in a list, cache stores all pages as a unit
- `hasNextPage` / `hasPreviousPage` derived booleans
- `InfiniteQueryData` state variant with `pages` list

## `refetchInterval` for polling
- Add `refetchInterval: Duration?` parameter to `query()`
- When set, a periodic timer refetches the query at the given interval
- Should only run while at least one listener is active
- Should pause when app is backgrounded and resume on foreground
- Consider `refetchIntervalInBackground: bool` option

## `select` for derived / computed queries
- Add `select: R Function(T data)?` parameter to `query()`
- Returns a `QueryHandle<R>` instead of `QueryHandle<T>`
- Only triggers rebuilds when the selected portion changes (deep equality)
- Reduces unnecessary widget rebuilds for large data sets
- Consider memoization of the selector

## DevTools extension
- Build a Flutter DevTools extension showing:
  - All active cache entries with their keys, data, and status
  - Stale/fresh indicators with countdown timers
  - Active listeners per entry
  - Mutation history log
  - Manual invalidation / refetch controls
- Use the `dart:developer` extension APIs

## Additional ideas
- **`prefetchQuery()`** — Warm the cache before a widget mounts (e.g. on hover)
- **`suspense`-style API** — Return a `Future<Widget>` or integrate with `FutureBuilder`-like wrappers
- **Retry with backoff** — Configurable retry count and backoff strategy on query failure
- **Structural sharing** — Only update references that actually changed (deep diff)
- **Persistence adapter** — Serialize/deserialize cache to local storage (Hive, SharedPreferences)
- **Network-aware refetching** — Automatically refetch when connectivity is restored
- **Dependent queries** — `enabled` as a reactive expression so one query waits for another
- **Mutation queues** — Serial execution of mutations to prevent race conditions
