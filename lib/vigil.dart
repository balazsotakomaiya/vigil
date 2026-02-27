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
///     final s = todos.state;
///     if (s.isLoading) return CircularProgressIndicator();
///     if (s.isError) return Text('${s.error}');
///     return TodoList(s.data!);
///   }
/// }
/// ```
library vigil;

// Core infrastructure
export 'src/core/subscribable.dart';
export 'src/core/notify_manager.dart';
export 'src/core/focus_manager.dart';
export 'src/core/online_manager.dart';
export 'src/core/network_mode.dart';
export 'src/core/retryer.dart';
export 'src/core/query_defaults.dart';

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
