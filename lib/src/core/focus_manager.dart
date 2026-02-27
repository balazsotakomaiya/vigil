import 'dart:ui' show VoidCallback;

import 'package:flutter/widgets.dart';

import 'subscribable.dart';

/// Tracks app focus/visibility state.
///
/// Lazy: only attaches the platform observer when the first subscriber arrives,
/// detaches on last unsubscribe.
///
/// Override platform behavior with [setEventListener] for tests or
/// non-standard platforms (e.g. desktop, React Native-style).
class FocusManager extends Subscribable<VoidCallback> {
  FocusManager();

  static final instance = FocusManager();

  bool _focused = true;
  _FocusObserver? _observer;
  VoidCallback? _teardown;

  /// Whether the app is currently focused/visible.
  bool get isFocused => _focused;

  /// Manually set the focused state. Notifies all listeners.
  void setFocused(bool focused) {
    final changed = _focused != focused;
    _focused = focused;
    if (changed) {
      _notifyListeners();
    }
  }

  /// Replace the default platform listener.
  ///
  /// [setup] receives a callback that should be called with the new focus
  /// state whenever it changes. It should return a teardown function.
  void setEventListener(
    VoidCallback Function(void Function(bool focused) onFocusChanged) setup,
  ) {
    _removePlatformListener();
    _teardown = setup((focused) => setFocused(focused));
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
    if (_observer != null || _teardown != null) return;
    _observer = _FocusObserver((focused) => setFocused(focused));
    WidgetsBinding.instance.addObserver(_observer!);
  }

  void _removePlatformListener() {
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
    _teardown?.call();
    _teardown = null;
  }

  void _notifyListeners() {
    for (final listener in listeners) {
      listener();
    }
  }
}

class _FocusObserver extends WidgetsBindingObserver {
  _FocusObserver(this._onChanged);

  final void Function(bool focused) _onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onChanged(state == AppLifecycleState.resumed);
  }
}
