import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('OnlineManager', () {
    late OnlineManager manager;

    setUp(() {
      manager = OnlineManager();
    });

    test('defaults to online', () {
      expect(manager.isOnline, isTrue);
    });

    test('setOnline changes state and notifies listeners', () {
      var notified = false;
      manager.subscribe(() => notified = true);

      manager.setOnline(false);
      expect(manager.isOnline, isFalse);
      expect(notified, isTrue);
    });

    test('does not notify if state is unchanged', () {
      var notifyCount = 0;
      manager.subscribe(() => notifyCount++);

      manager.setOnline(true); // already true
      expect(notifyCount, 0);
    });

    test('setEventListener provides custom listener', () {
      late void Function(bool) notify;
      manager.setEventListener((onChanged) {
        notify = onChanged;
        return () {}; // teardown
      });

      // Need a subscriber to trigger attachment
      manager.subscribe(() {});

      notify(false);
      expect(manager.isOnline, isFalse);

      notify(true);
      expect(manager.isOnline, isTrue);
    });

    test('lazy attachment: setup called on first subscriber', () {
      var setupCalled = false;
      manager.setEventListener((onChanged) {
        setupCalled = true;
        return () {};
      });

      expect(setupCalled, isFalse);

      final unsub = manager.subscribe(() {});
      expect(setupCalled, isTrue);

      unsub();
    });
  });
}
