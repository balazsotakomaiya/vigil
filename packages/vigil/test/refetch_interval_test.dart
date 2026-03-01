import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('Refetch Interval', () {
    late QueryClient client;
    late List<String> stateLog;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      FocusManager.instance.setFocused(true);
      OnlineManager.instance.setOnline(true);
      client = QueryClient();
      stateLog = [];
    });

    tearDown(() {
      client.dispose();
    });

    test('refetches at the configured interval', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final handle = QueryHandle<String>(
          key: ['polling'],
          queryFn: () async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          client: client,
          onStateChanged: () => stateLog.add('changed'),
          staleTime: Duration.zero,
          retryConfig: const RetryConfig(maxRetries: 0),
          refetchInterval: const Duration(seconds: 5),
        );

        // Initial fetch happens immediately.
        async.flushMicrotasks();
        expect(fetchCount, 1);

        // After 5 seconds, another fetch should fire.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(fetchCount, 2);

        // After 5 more seconds, another.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(fetchCount, 3);

        handle.dispose();
      });
    });

    test('pauses when app loses focus (default)', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final handle = QueryHandle<String>(
          key: ['polling-focus'],
          queryFn: () async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          client: client,
          onStateChanged: () => stateLog.add('changed'),
          staleTime: Duration.zero,
          retryConfig: const RetryConfig(maxRetries: 0),
          refetchInterval: const Duration(seconds: 5),
        );

        async.flushMicrotasks();
        expect(fetchCount, 1);

        // Background the app.
        FocusManager.instance.setFocused(false);

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        // Should NOT have refetched.
        expect(fetchCount, 1);

        // Foreground again.
        FocusManager.instance.setFocused(true);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(fetchCount, 2);

        handle.dispose();
      });
    });

    test('continues in background when refetchIntervalInBackground=true', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final handle = QueryHandle<String>(
          key: ['polling-bg'],
          queryFn: () async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          client: client,
          onStateChanged: () => stateLog.add('changed'),
          staleTime: Duration.zero,
          retryConfig: const RetryConfig(maxRetries: 0),
          refetchInterval: const Duration(seconds: 5),
          refetchIntervalInBackground: true,
        );

        async.flushMicrotasks();
        expect(fetchCount, 1);

        FocusManager.instance.setFocused(false);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        // Should still refetch in background.
        expect(fetchCount, 2);

        handle.dispose();
      });
    });

    test('pauses when offline', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final handle = QueryHandle<String>(
          key: ['polling-offline'],
          queryFn: () async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          client: client,
          onStateChanged: () => stateLog.add('changed'),
          staleTime: Duration.zero,
          retryConfig: const RetryConfig(maxRetries: 0),
          refetchInterval: const Duration(seconds: 5),
        );

        async.flushMicrotasks();
        expect(fetchCount, 1);

        OnlineManager.instance.setOnline(false);

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        // No refetch while offline.
        expect(fetchCount, 1);

        OnlineManager.instance.setOnline(true);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(fetchCount, 2);

        handle.dispose();
      });
    });

    test('manual refetch resets the interval timer', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final handle = QueryHandle<String>(
          key: ['polling-reset'],
          queryFn: () async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          client: client,
          onStateChanged: () => stateLog.add('changed'),
          staleTime: Duration.zero,
          retryConfig: const RetryConfig(maxRetries: 0),
          refetchInterval: const Duration(seconds: 10),
        );

        async.flushMicrotasks();
        expect(fetchCount, 1);

        // Wait 7 seconds, then manually refetch.
        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();
        handle.refetch();
        async.flushMicrotasks();
        expect(fetchCount, 2);

        // The timer should be reset. 7 seconds after manual refetch,
        // the interval shouldn't fire yet (needs 10s).
        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();
        expect(fetchCount, 2);

        // 3 more seconds = 10 total since manual refetch.
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(fetchCount, 3);

        handle.dispose();
      });
    });

    test('stops polling on dispose', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final handle = QueryHandle<String>(
          key: ['polling-dispose'],
          queryFn: () async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          client: client,
          onStateChanged: () => stateLog.add('changed'),
          staleTime: Duration.zero,
          retryConfig: const RetryConfig(maxRetries: 0),
          refetchInterval: const Duration(seconds: 5),
        );

        async.flushMicrotasks();
        expect(fetchCount, 1);

        handle.dispose();

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        // No more fetches after dispose.
        expect(fetchCount, 1);
      });
    });

    test('no polling when enabled=false', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final handle = QueryHandle<String>(
          key: ['polling-disabled'],
          queryFn: () async {
            fetchCount++;
            return 'data-$fetchCount';
          },
          client: client,
          onStateChanged: () => stateLog.add('changed'),
          staleTime: Duration.zero,
          retryConfig: const RetryConfig(maxRetries: 0),
          refetchInterval: const Duration(seconds: 5),
          enabled: false,
        );

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        // Should not have fetched at all.
        expect(fetchCount, 0);

        handle.dispose();
      });
    });
  });
}
