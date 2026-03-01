import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('QueryCacheEntry', () {
    late QueryCacheEntry entry;

    setUp(() {
      // Use synchronous scheduling for tests.
      NotifyManager.instance.scheduleFn = (cb) => cb();
      entry = QueryCacheEntry(serializedKey: '["todos"]');
    });

    tearDown(() {
      entry.dispose();
    });

    test('starts with no data', () {
      expect(entry.hasData, isFalse);
      expect(entry.hasError, isFalse);
      expect(entry.data, isNull);
      expect(entry.dataUpdatedAt, 0);
    });

    test('isStaleFor returns true when no data fetched', () {
      expect(entry.isStaleFor(const Duration(minutes: 5)), isTrue);
    });

    test('isStaleFor returns false for fresh data', () {
      entry.data = [1, 2, 3];
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      expect(entry.isStaleFor(const Duration(minutes: 5)), isFalse);
    });

    test('isStaleFor returns true for old data', () {
      entry.data = [1, 2, 3];
      entry.dataUpdatedAt = DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch;
      expect(entry.isStaleFor(const Duration(minutes: 5)), isTrue);
    });

    test('isStaleFor returns true when invalidated', () {
      entry.data = [1, 2, 3];
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      entry.isInvalidated = true;
      expect(entry.isStaleFor(const Duration(minutes: 5)), isTrue);
    });

    group('listeners', () {
      test('notifies listeners on change', () {
        var notified = false;
        entry.addListener(() => notified = true);
        entry.notifyListeners();
        expect(notified, isTrue);
      });

      test('tracks listener count', () {
        void listener1() {}
        void listener2() {}

        expect(entry.listenerCount, 0);
        entry.addListener(listener1);
        expect(entry.listenerCount, 1);
        entry.addListener(listener2);
        expect(entry.listenerCount, 2);
        entry.removeListener(listener1);
        expect(entry.listenerCount, 1);
      });

      test('does not notify removed listeners', () {
        var notified = false;
        void listener() => notified = true;

        entry.addListener(listener);
        entry.removeListener(listener);
        entry.notifyListeners();
        expect(notified, isFalse);
      });
    });

    group('fetch deduplication', () {
      test('only executes one fetch at a time', () async {
        var fetchCount = 0;
        final completer = Completer<dynamic>();

        Future<dynamic> queryFn() {
          fetchCount++;
          return completer.future;
        }

        // Start two fetches simultaneously.
        final f1 = entry.fetch(queryFn);
        final f2 = entry.fetch(queryFn);

        expect(fetchCount, 1); // Only one actual fetch.

        completer.complete('result');
        await f1;
        await f2;

        expect(entry.data, 'result');
        expect(entry.hasError, isFalse);
      });

      test('stores data on successful fetch', () async {
        await entry.fetch(
          () async => 'hello',
          retryConfig: const RetryConfig(maxRetries: 0),
        );
        expect(entry.data, 'hello');
        expect(entry.hasData, isTrue);
        expect(entry.dataUpdatedAt, isNot(0));
      });

      test('stores error on failed fetch', () async {
        await entry.fetch(
          () async => throw Exception('boom'),
          retryConfig: const RetryConfig(maxRetries: 0),
        );
        expect(entry.hasError, isTrue);
        expect(entry.error, isA<Exception>());
        expect(entry.stackTrace, isNotNull);
      });

      test('notifies listeners after fetch', () async {
        var notifications = 0;
        entry.addListener(() => notifications++);

        await entry.fetch(
          () async => 42,
          retryConfig: const RetryConfig(maxRetries: 0),
        );
        expect(notifications, 1);
      });

      test('allows new fetch after previous completes', () async {
        await entry.fetch(
          () async => 'first',
          retryConfig: const RetryConfig(maxRetries: 0),
        );
        expect(entry.data, 'first');

        await entry.fetch(
          () async => 'second',
          retryConfig: const RetryConfig(maxRetries: 0),
        );
        expect(entry.data, 'second');
      });
    });

    group('garbage collection', () {
      test('calls onEvict after gcTime with no listeners', () {
        fakeAsync((async) {
          String? evictedKey;
          entry.onEvict = (key) => evictedKey = key;
          entry.gcTime = const Duration(seconds: 30);

          // Add and remove a listener to trigger GC timer.
          void listener() {}
          entry.addListener(listener);
          entry.removeListener(listener);

          // Advance time but not enough.
          async.elapse(const Duration(seconds: 20));
          expect(evictedKey, isNull);

          // Advance past gcTime.
          async.elapse(const Duration(seconds: 15));
          expect(evictedKey, '["todos"]');
        });
      });

      test('cancels GC timer when new listener subscribes', () {
        fakeAsync((async) {
          String? evictedKey;
          entry.onEvict = (key) => evictedKey = key;
          entry.gcTime = const Duration(seconds: 30);

          void listener1() {}
          void listener2() {}

          entry.addListener(listener1);
          entry.removeListener(listener1); // starts GC timer

          // New listener before timer fires.
          async.elapse(const Duration(seconds: 10));
          entry.addListener(listener2);

          // Advance past original gcTime.
          async.elapse(const Duration(seconds: 30));
          expect(evictedKey, isNull); // timer was cancelled
        });
      });
    });
  });
}
