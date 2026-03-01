import 'subscribable.dart';

/// Tracks network connectivity state.
///
/// Defaults to online (optimistic). For real connectivity detection,
/// plug in a listener:
///
/// ```dart
/// OnlineManager.instance.setEventListener((onOnlineChanged) {
///   final sub = Connectivity().onConnectivityChanged.listen((result) {
///     onOnlineChanged(result != ConnectivityResult.none);
///   });
///   return sub.cancel;
/// });
/// ```
///
/// Lazy: only calls [setEventListener]'s setup when first subscriber arrives.
class OnlineManager extends Subscribable<void Function()> {
  OnlineManager();

  static final instance = OnlineManager();

  bool _online = true;
  void Function()? _teardown;
  void Function() Function(void Function(bool online) onOnlineChanged)? _setup;

  /// Whether the device is currently online.
  bool get isOnline => _online;

  /// Manually set the online state. Notifies all listeners.
  void setOnline(bool online) {
    final changed = _online != online;
    _online = online;
    if (changed) {
      _notifyListeners();
    }
  }

  /// Replace the default connectivity listener.
  ///
  /// [setup] receives a callback that should be called with the new online
  /// state whenever it changes. It should return a teardown function.
  void setEventListener(
    void Function() Function(void Function(bool online) onOnlineChanged) setup,
  ) {
    _removePlatformListener();
    _setup = setup;
    if (hasListeners) {
      _attachPlatformListener();
    }
  }

  @override
  void onSubscribe() {
    if (listenerCount == 1) {
      _attachPlatformListener();
    }
  }

  @override
  void onUnsubscribe() {
    if (!hasListeners) {
      _removePlatformListener();
    }
  }

  void _attachPlatformListener() {
    if (_setup != null && _teardown == null) {
      _teardown = _setup!((online) => setOnline(online));
    }
  }

  void _removePlatformListener() {
    _teardown?.call();
    _teardown = null;
  }

  /// Reset to default state. Intended for test teardown.
  void reset() {
    _removePlatformListener();
    _setup = null;
    _online = true;
  }

  void _notifyListeners() {
    for (final listener in listeners) {
      listener();
    }
  }
}
