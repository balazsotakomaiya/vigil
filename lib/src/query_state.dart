/// Sealed class representing the state of a query.
///
/// Use Dart 3 pattern matching to handle each state:
/// ```dart
/// switch (query.state) {
///   QueryInitial() => ...,
///   QueryLoading() => ...,
///   QueryData(:final data) => ...,
///   QueryError(:final error) => ...,
/// }
/// ```
sealed class QueryState<T> {
  const QueryState();
}

/// The query has not yet started fetching.
///
/// This is the state when [enabled] is `false` and no cached data exists.
class QueryInitial<T> extends QueryState<T> {
  const QueryInitial();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueryInitial<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'QueryInitial<$T>()';
}

/// The query is loading data for the first time (no cached data available).
class QueryLoading<T> extends QueryState<T> {
  const QueryLoading();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueryLoading<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'QueryLoading<$T>()';
}

/// The query has data available.
class QueryData<T> extends QueryState<T> {
  final T data;

  /// `true` when stale data is shown while a background refetch is in progress.
  final bool isRefetching;

  const QueryData(this.data, {this.isRefetching = false});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryData<T> &&
          data == other.data &&
          isRefetching == other.isRefetching;

  @override
  int get hashCode => Object.hash(data, isRefetching);

  @override
  String toString() =>
      'QueryData<$T>($data${isRefetching ? ', isRefetching: true' : ''})';
}

/// The query encountered an error.
class QueryError<T> extends QueryState<T> {
  final Object error;
  final StackTrace? stackTrace;

  /// Previous data if available, enabling stale-while-revalidate patterns.
  final T? staleData;

  const QueryError(this.error, {this.stackTrace, this.staleData});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryError<T> &&
          error == other.error &&
          staleData == other.staleData;

  @override
  int get hashCode => Object.hash(error, staleData);

  @override
  String toString() =>
      'QueryError<$T>($error${staleData != null ? ', staleData: $staleData' : ''})';
}
