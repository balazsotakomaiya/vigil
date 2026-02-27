import 'dart:async';
import 'dart:math' as math;

import 'network_mode.dart';
import 'online_manager.dart';

/// Default retry delay using full jitter exponential backoff.
///
/// Full jitter (from the AWS Architecture Blog) picks a random value in
/// `[0, min(1000 * 2^attempt, 30000)]`. This decorrelates retries from
/// multiple callers hitting the same endpoint, producing lower average
/// delay and better spread under contention than equal jitter.
///
/// | Attempt | Base    | Jitter range |
/// |---------|---------|--------------|
/// | 0       | 1 000ms | [0, 1 000ms] |
/// | 1       | 2 000ms | [0, 2 000ms] |
/// | 2       | 4 000ms | [0, 4 000ms] |
/// | 3       | 8 000ms | [0, 8 000ms] |
/// | 4       | 16 000ms| [0, 16 000ms]|
/// | 5+      | 30 000ms| [0, 30 000ms]|
Duration defaultRetryDelay(int attempt, {math.Random? random}) {
  final cap = math.min(1000 * math.pow(2, attempt).toInt(), 30000);
  final r = random ?? _sharedRandom;
  return Duration(milliseconds: r.nextInt(cap + 1));
}

final _sharedRandom = math.Random();

/// Whether the given error should be retried by default.
///
/// Default: always retry. Override with a custom predicate to skip
/// retries for non-transient errors (e.g. 4xx HTTP status codes).
bool defaultShouldRetry(Object error) => true;

/// Configuration for retry behavior.
class RetryConfig {
  const RetryConfig({
    this.maxRetries = 3,
    this.retryDelay = defaultRetryDelay,
    this.shouldRetry = defaultShouldRetry,
    this.networkMode = NetworkMode.online,
  });

  /// Maximum number of retries after the initial attempt.
  /// Default: 3 for queries, 0 for mutations.
  final int maxRetries;

  /// Computes the delay before the next retry attempt.
  /// Receives the current attempt number (0-indexed).
  final Duration Function(int attempt, {math.Random? random}) retryDelay;

  /// Whether to retry the given error. Return `false` to fail immediately.
  final bool Function(Object error) shouldRetry;

  /// How to interact with network connectivity.
  final NetworkMode networkMode;
}

/// Stateful fetch controller that handles execution, retry with exponential
/// backoff + jitter, pause/resume on connectivity changes, and cancellation.
class Retryer<T> {
  Retryer({
    required Future<T> Function() fn,
    this.config = const RetryConfig(),
    void Function()? onSuccess,
    void Function(Object error)? onError,
    void Function(int failureCount, Object error)? onFailed,
    void Function()? onPause,
    void Function()? onContinue,
    math.Random? random,
  })  : _fn = fn,
        _onSuccess = onSuccess,
        _onError = onError,
        _onFailed = onFailed,
        _onPause = onPause,
        _onContinue = onContinue,
        _random = random;

  final Future<T> Function() _fn;
  final RetryConfig config;
  final void Function()? _onSuccess;
  final void Function(Object error)? _onError;
  final void Function(int failureCount, Object error)? _onFailed;
  final void Function()? _onPause;
  final void Function()? _onContinue;
  final math.Random? _random;

  bool _cancelled = false;
  Completer<void>? _pauseCompleter;
  void Function()? _onlineUnsub;

  /// Start execution. Returns the result or throws on final failure.
  Future<T> start() async {
    for (var attempt = 0;; attempt++) {
      // Check if we should wait for online status before attempting.
      if (!_cancelled) {
        await _waitForOnlineIfNeeded(attempt);
      }

      if (_cancelled) {
        throw RetryerCancelledException();
      }

      try {
        final result = await _fn();
        if (_cancelled) throw RetryerCancelledException();
        _onSuccess?.call();
        return result;
      } catch (e) {
        if (_cancelled) throw RetryerCancelledException();
        if (e is RetryerCancelledException) rethrow;

        final canRetry = attempt < config.maxRetries && config.shouldRetry(e);
        if (!canRetry) {
          _onError?.call(e);
          rethrow;
        }

        // Non-terminal failure — will retry.
        _onFailed?.call(attempt + 1, e);

        // Wait with backoff before retrying.
        final delay = config.retryDelay(attempt, random: _random);
        if (delay > Duration.zero) {
          await _delayWithCancellation(delay);
        }

        if (_cancelled) throw RetryerCancelledException();
      }
    }
  }

  /// Cancel the retryer. In-flight futures will throw [RetryerCancelledException].
  void cancel() {
    _cancelled = true;
    _resumeIfPaused();
  }

  /// Whether this retryer has been cancelled.
  bool get isCancelled => _cancelled;

  // ---------------------------------------------------------------------------
  // Network-aware pause/resume
  // ---------------------------------------------------------------------------

  Future<void> _waitForOnlineIfNeeded(int attempt) async {
    if (config.networkMode == NetworkMode.always) return;
    if (config.networkMode == NetworkMode.offlineFirst && attempt == 0) return;

    if (!OnlineManager.instance.isOnline) {
      _pause();
      await _waitForOnline();
      _resume();
    }
  }

  void _pause() {
    _onPause?.call();
    _pauseCompleter = Completer<void>();
  }

  void _resume() {
    _onContinue?.call();
    _resumeIfPaused();
  }

  void _resumeIfPaused() {
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
    _pauseCompleter = null;
    _onlineUnsub?.call();
    _onlineUnsub = null;
  }

  Future<void> _waitForOnline() async {
    if (_pauseCompleter == null) return;
    _onlineUnsub = OnlineManager.instance.subscribe(() {
      if (OnlineManager.instance.isOnline) {
        _resumeIfPaused();
      }
    });
    await _pauseCompleter!.future;
  }

  Future<void> _delayWithCancellation(Duration delay) async {
    final completer = Completer<void>();
    final timer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete();
    });

    // If we go offline during the delay, pause.
    void Function()? unsub;
    if (config.networkMode != NetworkMode.always) {
      unsub = OnlineManager.instance.subscribe(() {
        if (!OnlineManager.instance.isOnline && !completer.isCompleted) {
          timer.cancel();
          completer.complete(); // break out of delay to enter pause loop
        }
      });
    }

    try {
      await completer.future;
    } finally {
      timer.cancel();
      unsub?.call();
    }
  }
}

/// Thrown when a [Retryer] is cancelled.
class RetryerCancelledException implements Exception {
  @override
  String toString() => 'RetryerCancelledException';
}
