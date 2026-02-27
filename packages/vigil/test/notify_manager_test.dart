import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('NotifyManager', () {
    late NotifyManager manager;

    setUp(() {
      manager = NotifyManager();
      manager.scheduleFn = (cb) => cb(); // synchronous for tests
    });

    test('notify executes immediately outside a batch', () {
      var called = false;
      manager.notify(() => called = true);
      expect(called, isTrue);
    });

    test('batch queues notifications and flushes at end', () {
      final log = <String>[];

      manager.batch(() {
        manager.notify(() => log.add('a'));
        manager.notify(() => log.add('b'));
        expect(log, isEmpty); // queued, not yet flushed
      });

      expect(log, ['a', 'b']); // flushed after batch
    });

    test('nested batches flush only on outermost completion', () {
      final log = <String>[];

      manager.batch(() {
        manager.notify(() => log.add('outer'));

        manager.batch(() {
          manager.notify(() => log.add('inner'));
          expect(log, isEmpty);
        });

        // Inner batch completed but outer hasn't yet.
        expect(log, isEmpty);
      });

      expect(log, ['outer', 'inner']);
    });

    test('batch returns the callback value', () {
      final result = manager.batch(() => 42);
      expect(result, 42);
    });

    test('empty batch does not call scheduleFn', () {
      var scheduleCalled = false;
      manager.scheduleFn = (cb) {
        scheduleCalled = true;
        cb();
      };

      manager.batch(() {
        // No notifications inside
      });

      expect(scheduleCalled, isFalse);
    });

    test('multiple invalidations in one batch produce one flush', () {
      var flushCount = 0;
      manager.scheduleFn = (cb) {
        flushCount++;
        cb();
      };

      final log = <String>[];

      manager.batch(() {
        manager.notify(() => log.add('1'));
        manager.notify(() => log.add('2'));
        manager.notify(() => log.add('3'));
      });

      expect(flushCount, 1); // One scheduleFn call for all three
      expect(log, ['1', '2', '3']);
    });
  });
}
