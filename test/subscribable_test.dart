import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

class _TestSubscribable extends Subscribable<void Function()> {
  int subscribeCount = 0;
  int unsubscribeCount = 0;

  @override
  void onSubscribe() {
    subscribeCount++;
  }

  @override
  void onUnsubscribe() {
    unsubscribeCount++;
  }
}

void main() {
  group('Subscribable', () {
    late _TestSubscribable sub;

    setUp(() {
      sub = _TestSubscribable();
    });

    test('starts with no listeners', () {
      expect(sub.hasListeners, isFalse);
      expect(sub.listenerCount, 0);
    });

    test('subscribe adds a listener and returns unsubscribe', () {
      final unsub = sub.subscribe(() {});
      expect(sub.hasListeners, isTrue);
      expect(sub.listenerCount, 1);
      unsub();
      expect(sub.hasListeners, isFalse);
      expect(sub.listenerCount, 0);
    });

    test('calls onSubscribe and onUnsubscribe hooks', () {
      final unsub = sub.subscribe(() {});
      expect(sub.subscribeCount, 1);
      expect(sub.unsubscribeCount, 0);

      unsub();
      expect(sub.unsubscribeCount, 1);
    });

    test('multiple listeners', () {
      final unsub1 = sub.subscribe(() {});
      final unsub2 = sub.subscribe(() {});
      expect(sub.listenerCount, 2);

      unsub1();
      expect(sub.listenerCount, 1);

      unsub2();
      expect(sub.listenerCount, 0);
    });

    test('listeners returns a copy', () {
      var called = false;
      sub.subscribe(() => called = true);
      for (final listener in sub.listeners) {
        listener();
      }
      expect(called, isTrue);
    });
  });
}
