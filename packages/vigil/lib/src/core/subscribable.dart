/// Foundational pub/sub primitive.
///
/// Nearly every reactive class in Vigil extends this. It provides a
/// type-safe listener set with subscribe/unsubscribe lifecycle hooks.
class Subscribable<T extends Function> {
  final _listeners = <T>{};

  /// Subscribe [listener] and return an unsubscribe function.
  void Function() subscribe(T listener) {
    _listeners.add(listener);
    onSubscribe();
    return () {
      _listeners.remove(listener);
      onUnsubscribe();
    };
  }

  /// Whether any listeners are currently registered.
  bool get hasListeners => _listeners.isNotEmpty;

  /// The number of active listeners.
  int get listenerCount => _listeners.length;

  /// All current listeners. Returns a copy to allow safe iteration
  /// even if listeners are added/removed during notification.
  Iterable<T> get listeners => List<T>.of(_listeners);

  /// Called after a listener is added. Override for setup logic.
  void onSubscribe() {}

  /// Called after a listener is removed. Override for teardown logic.
  void onUnsubscribe() {}
}
