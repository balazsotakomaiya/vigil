import 'package:flutter/widgets.dart';

import 'query_client.dart';

/// Provides a [QueryClient] to the widget tree via an [InheritedWidget].
///
/// Wrap your app (or a subtree) with this widget to supply a specific
/// [QueryClient] to all descendant widgets that use [QueryMixin]:
///
/// ```dart
/// QueryClientProvider(
///   client: QueryClient(),
///   child: MyApp(),
/// )
/// ```
///
/// If no [QueryClientProvider] is found in the tree, [QueryMixin] falls back
/// to [QueryClient.instance].
class QueryClientProvider extends InheritedWidget {
  const QueryClientProvider({
    super.key,
    required this.client,
    required super.child,
  });

  /// The [QueryClient] made available to descendant widgets.
  final QueryClient client;

  /// Retrieve the nearest [QueryClient] from the widget tree, or `null` if
  /// no [QueryClientProvider] exists above [context].
  static QueryClient? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<QueryClientProvider>()
        ?.client;
  }

  /// Retrieve the nearest [QueryClient] from the widget tree.
  ///
  /// Throws if no [QueryClientProvider] exists above [context].
  static QueryClient of(BuildContext context) {
    final client = maybeOf(context);
    assert(client != null, 'No QueryClientProvider found in the widget tree.');
    return client!;
  }

  @override
  bool updateShouldNotify(QueryClientProvider oldWidget) =>
      client != oldWidget.client;
}
