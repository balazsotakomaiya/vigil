import 'dart:math' as math;

import 'network_mode.dart';
import 'retryer.dart';

/// Default options for queries, used in the three-layer option cascade:
/// global defaults → per-key defaults → per-call options.
///
/// All fields are nullable so that unset values can be inherited from the
/// previous layer via [merge].
class QueryDefaults {
  const QueryDefaults({
    this.staleTime,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.shouldRetry,
    this.networkMode,
    this.refetchOnMount,
    this.refetchOnFocus,
    this.refetchOnReconnect,
    this.enabled,
  });

  /// How long fetched data is considered fresh.
  final Duration? staleTime;

  /// How long unused cache entries survive after all listeners unsubscribe.
  final Duration? gcTime;

  /// Maximum number of retries on failure.
  final int? retry;

  /// Computes the delay before each retry attempt.
  final Duration Function(int attempt, {math.Random? random})? retryDelay;

  /// Whether a given error should be retried.
  final bool Function(Object error)? shouldRetry;

  /// How to interact with network connectivity.
  final NetworkMode? networkMode;

  /// Whether to refetch on mount when data is stale.
  final bool? refetchOnMount;

  /// Whether to refetch when the app regains focus.
  final bool? refetchOnFocus;

  /// Whether to refetch when the device reconnects.
  final bool? refetchOnReconnect;

  /// Whether automatic fetching is enabled.
  final bool? enabled;

  /// Merge [other] on top of this, with [other]'s non-null values winning.
  QueryDefaults merge(QueryDefaults? other) {
    if (other == null) return this;
    return QueryDefaults(
      staleTime: other.staleTime ?? staleTime,
      gcTime: other.gcTime ?? gcTime,
      retry: other.retry ?? retry,
      retryDelay: other.retryDelay ?? retryDelay,
      shouldRetry: other.shouldRetry ?? shouldRetry,
      networkMode: other.networkMode ?? networkMode,
      refetchOnMount: other.refetchOnMount ?? refetchOnMount,
      refetchOnFocus: other.refetchOnFocus ?? refetchOnFocus,
      refetchOnReconnect: other.refetchOnReconnect ?? refetchOnReconnect,
      enabled: other.enabled ?? enabled,
    );
  }

  /// Build a [RetryConfig] from the resolved values.
  RetryConfig toRetryConfig() {
    return RetryConfig(
      maxRetries: retry ?? 3,
      retryDelay: retryDelay ?? defaultRetryDelay,
      shouldRetry: shouldRetry ?? defaultShouldRetry,
      networkMode: networkMode ?? NetworkMode.online,
    );
  }
}
