/// The data-availability axis of a query's state.
enum QueryStatus {
  /// No data has been received yet.
  pending,

  /// Data has been successfully received at least once.
  success,

  /// The last fetch attempt resulted in an error.
  error,
}

/// The network-activity axis of a query's state.
enum FetchStatus {
  /// A fetch is currently in progress.
  fetching,

  /// A fetch was attempted but is paused (e.g. offline).
  paused,

  /// No fetch is in progress.
  idle,
}

/// Immutable state of a query, using a dual-axis model.
///
/// The two axes are independent:
/// - [status] tracks **data availability** (pending / success / error)
/// - [fetchStatus] tracks **network activity** (fetching / paused / idle)
///
/// This allows representing states like "showing stale data while refetching
/// in the background" (`status: success, fetchStatus: fetching`).
///
/// Use the convenience getters for common checks:
/// ```dart
/// if (state.isLoading) ...   // pending + fetching (first load)
/// if (state.isRefetching) ... // success + fetching (background refetch)
/// if (state.isError) ...     // last fetch errored
/// ```
///
/// Pattern matching:
/// ```dart
/// switch (state) {
///   QueryState(isLoading: true) => CircularProgressIndicator(),
///   QueryState(isError: true, :final error) => Text('$error'),
///   QueryState(isSuccess: true, :final data!) => TodoList(data),
///   _ => SizedBox.shrink(),
/// }
/// ```
class QueryState<T> {
  const QueryState({
    this.status = QueryStatus.pending,
    this.fetchStatus = FetchStatus.idle,
    this.data,
    this.error,
    this.stackTrace,
    this.dataUpdatedAt = 0,
    this.errorUpdatedAt = 0,
    this.isInvalidated = false,
    this.fetchFailureCount = 0,
    this.fetchFailureReason,
  });

  // ---------------------------------------------------------------------------
  // Data axis
  // ---------------------------------------------------------------------------

  /// The data-availability status.
  final QueryStatus status;

  /// The cached data, if any.
  final T? data;

  /// The last error, if any.
  final Object? error;

  /// Stack trace of the last error, if any.
  final StackTrace? stackTrace;

  /// Timestamp (millisecondsSinceEpoch) when data was last successfully
  /// fetched. `0` means never.
  final int dataUpdatedAt;

  /// Timestamp (millisecondsSinceEpoch) when the last error occurred.
  /// `0` means never.
  final int errorUpdatedAt;

  /// Whether the query has been explicitly invalidated.
  final bool isInvalidated;

  // ---------------------------------------------------------------------------
  // Network axis
  // ---------------------------------------------------------------------------

  /// The network-activity status.
  final FetchStatus fetchStatus;

  /// How many consecutive fetch attempts have failed (resets on success).
  final int fetchFailureCount;

  /// The reason for the most recent fetch failure, if any.
  final Object? fetchFailureReason;

  // ---------------------------------------------------------------------------
  // Convenience getters — data axis
  // ---------------------------------------------------------------------------

  /// No data has been received yet.
  bool get isPending => status == QueryStatus.pending;

  /// Data has been successfully received at least once.
  bool get isSuccess => status == QueryStatus.success;

  /// The last fetch resulted in an error.
  bool get isError => status == QueryStatus.error;

  // ---------------------------------------------------------------------------
  // Convenience getters — network axis
  // ---------------------------------------------------------------------------

  /// A fetch is currently in progress.
  bool get isFetching => fetchStatus == FetchStatus.fetching;

  /// A fetch is paused (e.g. offline).
  bool get isPaused => fetchStatus == FetchStatus.paused;

  /// No fetch is in progress.
  bool get isIdle => fetchStatus == FetchStatus.idle;

  // ---------------------------------------------------------------------------
  // Convenience getters — combined
  // ---------------------------------------------------------------------------

  /// First load: no data yet and currently fetching.
  bool get isLoading => isPending && isFetching;

  /// Background refetch: have data and currently fetching.
  bool get isRefetching => isSuccess && isFetching;

  /// Have data (from success or previous success before error).
  bool get hasData => data != null;

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  QueryState<T> copyWith({
    QueryStatus? status,
    FetchStatus? fetchStatus,
    T? Function()? data,
    Object? Function()? error,
    StackTrace? Function()? stackTrace,
    int? dataUpdatedAt,
    int? errorUpdatedAt,
    bool? isInvalidated,
    int? fetchFailureCount,
    Object? Function()? fetchFailureReason,
  }) {
    return QueryState<T>(
      status: status ?? this.status,
      fetchStatus: fetchStatus ?? this.fetchStatus,
      data: data != null ? data() : this.data,
      error: error != null ? error() : this.error,
      stackTrace: stackTrace != null ? stackTrace() : this.stackTrace,
      dataUpdatedAt: dataUpdatedAt ?? this.dataUpdatedAt,
      errorUpdatedAt: errorUpdatedAt ?? this.errorUpdatedAt,
      isInvalidated: isInvalidated ?? this.isInvalidated,
      fetchFailureCount: fetchFailureCount ?? this.fetchFailureCount,
      fetchFailureReason: fetchFailureReason != null
          ? fetchFailureReason()
          : this.fetchFailureReason,
    );
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryState<T> &&
          status == other.status &&
          fetchStatus == other.fetchStatus &&
          data == other.data &&
          error == other.error &&
          dataUpdatedAt == other.dataUpdatedAt &&
          errorUpdatedAt == other.errorUpdatedAt &&
          isInvalidated == other.isInvalidated &&
          fetchFailureCount == other.fetchFailureCount &&
          fetchFailureReason == other.fetchFailureReason;

  @override
  int get hashCode => Object.hash(
        status,
        fetchStatus,
        data,
        error,
        dataUpdatedAt,
        errorUpdatedAt,
        isInvalidated,
        fetchFailureCount,
        fetchFailureReason,
      );

  @override
  String toString() =>
      'QueryState<$T>(status: $status, fetchStatus: $fetchStatus, '
      'data: $data, error: $error, '
      'dataUpdatedAt: $dataUpdatedAt, isInvalidated: $isInvalidated)';
}
