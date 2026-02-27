import 'dart:ui' show VoidCallback;

/// Singleton that batches all notifications.
///
/// During a [batch] call, notifications are queued. When the outermost batch
/// completes, all queued notifications are flushed together via [scheduleFn].
/// This prevents cascading rebuilds when multiple queries are invalidated
/// at once.
class NotifyManager {
  NotifyManager();

  static final instance = NotifyManager();

  int _transactions = 0;
  final _queue = <VoidCallback>[];

  /// Execute [callback] inside a batch transaction.
  ///
  /// Notifications emitted via [notify] during the callback are queued
  /// and flushed once after the outermost batch completes.
  T batch<T>(T Function() callback) {
    _transactions++;
    try {
      return callback();
    } finally {
      _transactions--;
      if (_transactions == 0) {
        _flush();
      }
    }
  }

  /// Schedule a notification. If inside a [batch], it is queued.
  /// Otherwise it is dispatched immediately via [scheduleFn].
  void notify(VoidCallback callback) {
    if (_transactions > 0) {
      _queue.add(callback);
    } else {
      scheduleFn(callback);
    }
  }

  void _flush() {
    final queued = List<VoidCallback>.of(_queue);
    _queue.clear();
    if (queued.isEmpty) return;
    scheduleFn(() {
      for (final cb in queued) {
        cb();
      }
    });
  }

  /// Scheduling function. Override for testing (e.g. synchronous execution).
  ///
  /// Default: execute synchronously. Flutter adapters can replace this with
  /// `WidgetsBinding.instance.addPostFrameCallback`.
  void Function(VoidCallback) scheduleFn = _defaultSchedule;

  static void _defaultSchedule(VoidCallback cb) {
    cb();
  }
}
