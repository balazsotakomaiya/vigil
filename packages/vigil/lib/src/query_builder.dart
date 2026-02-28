import 'package:flutter/widgets.dart';

import 'mutation_handle.dart';
import 'mutation_state.dart';
import 'query_handle.dart';
import 'query_state.dart';

/// A convenience widget that rebuilds based on a [QueryHandle]'s state.
///
/// Use this as an alternative to reading handle properties directly in your
/// build method. The parent widget must still use [QueryMixin] — the builder
/// is purely organizational, not a separate subscription mechanism.
///
/// ```dart
/// QueryBuilder<List<Todo>>(
///   query: todos,
///   builder: (context, state, child) {
///     if (state.isLoading) return CircularProgressIndicator();
///     if (state.isError) return Text('${state.error}');
///     return TodoList(state.data!);
///   },
/// )
/// ```
///
/// Pass a [child] widget for parts of the subtree that don't depend on the
/// query state — it won't be rebuilt when the state changes.
class QueryBuilder<T> extends StatelessWidget {
  const QueryBuilder({
    super.key,
    required this.query,
    required this.builder,
    this.child,
  });

  /// The query handle to observe. Created via [QueryMixin.query].
  final QueryHandle<T> query;

  /// Called on every rebuild with the current [QueryState].
  ///
  /// The [child] parameter is the widget passed to the constructor — use it
  /// for subtrees that don't depend on query state.
  final Widget Function(
    BuildContext context,
    QueryState<T> state,
    Widget? child,
  ) builder;

  /// An optional child widget that doesn't depend on the query state.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return builder(context, query.state, child);
  }
}

/// A convenience widget that rebuilds based on a [MutationHandle]'s state.
///
/// Since [MutationState] is a sealed class with four subtypes, the builder
/// receives the full state for pattern matching:
///
/// ```dart
/// MutationBuilder<Todo, String>(
///   mutation: addTodo,
///   builder: (context, state, child) => switch (state) {
///     MutationIdle() => child!,
///     MutationLoading() => CircularProgressIndicator(),
///     MutationSuccess(:final data) => Text('Created: ${data.title}'),
///     MutationError(:final error) => Text('Failed: $error'),
///   },
///   child: ElevatedButton(
///     onPressed: () => addTodo.mutate('Buy milk'),
///     child: Text('Add'),
///   ),
/// )
/// ```
class MutationBuilder<TData, TInput> extends StatelessWidget {
  const MutationBuilder({
    super.key,
    required this.mutation,
    required this.builder,
    this.child,
  });

  /// The mutation handle to observe. Created via [QueryMixin.mutation].
  final MutationHandle<TData, TInput> mutation;

  /// Called on every rebuild with the current [MutationState].
  final Widget Function(
    BuildContext context,
    MutationState<TData> state,
    Widget? child,
  ) builder;

  /// An optional child widget that doesn't depend on the mutation state.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return builder(context, mutation.state, child);
  }
}
