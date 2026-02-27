/// Vigil — TanStack Query-inspired data fetching for Flutter.
///
/// Provides cached, stale-aware queries and mutations via a simple mixin API:
///
/// ```dart
/// class _MyState extends State<MyWidget> with QueryMixin {
///   late final todos = query<List<Todo>>(
///     ['todos'],
///     () => api.fetchTodos(),
///     stale: Duration(minutes: 5),
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
library vigil;

// State types
export 'src/query_state.dart';
export 'src/mutation_state.dart';

// Core
export 'src/query_client.dart';
export 'src/query_cache_entry.dart';

// Handles
export 'src/query_handle.dart';
export 'src/mutation_handle.dart';

// Mixin & provider
export 'src/query_mixin.dart';
export 'src/query_client_provider.dart';
