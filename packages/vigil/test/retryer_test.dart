import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('defaultRetryDelay', () {
    test('produces values within expected ranges', () {
      final random = math.Random(42); // seeded for determinism

      // Attempt 0: base = 1000ms, range [0, 1000]
      final d0 = defaultRetryDelay(0, random: random);
      expect(d0.inMilliseconds, greaterThanOrEqualTo(0));
      expect(d0.inMilliseconds, lessThanOrEqualTo(1000));

      // Attempt 1: base = 2000ms, range [0, 2000]
      final d1 = defaultRetryDelay(1, random: random);
      expect(d1.inMilliseconds, greaterThanOrEqualTo(0));
      expect(d1.inMilliseconds, lessThanOrEqualTo(2000));

      // Attempt 2: base = 4000ms, range [0, 4000]
      final d2 = defaultRetryDelay(2, random: random);
      expect(d2.inMilliseconds, greaterThanOrEqualTo(0));
      expect(d2.inMilliseconds, lessThanOrEqualTo(4000));

      // Attempt 3: base = 8000ms, range [0, 8000]
      final d3 = defaultRetryDelay(3, random: random);
      expect(d3.inMilliseconds, greaterThanOrEqualTo(0));
      expect(d3.inMilliseconds, lessThanOrEqualTo(8000));
    });

    test('caps at 30 seconds', () {
      final random = math.Random(42);

      // Attempt 10: base would be 1024000ms, but capped at 30000
      final d = defaultRetryDelay(10, random: random);
      expect(d.inMilliseconds, greaterThanOrEqualTo(0));
      expect(d.inMilliseconds, lessThanOrEqualTo(30000));
    });

    test('full jitter produces varied values across calls', () {
      final random = math.Random(42);
      final values = <int>{};
      for (var i = 0; i < 20; i++) {
        values.add(defaultRetryDelay(2, random: random).inMilliseconds);
      }
      // With 20 samples in [0, 4000], we should see more than 1 distinct value
      expect(values.length, greaterThan(1));
    });
  });

  group('Retryer', () {
    test('succeeds on first try', () async {
      var successCalled = false;
      final retryer = Retryer<String>(
        fn: () async => 'ok',
        config: const RetryConfig(maxRetries: 3),
        onSuccess: () => successCalled = true,
      );

      final result = await retryer.start();
      expect(result, 'ok');
      expect(successCalled, isTrue);
    });

    test('retries on failure and eventually succeeds', () async {
      var attempt = 0;
      final failures = <int>[];

      final retryer = Retryer<String>(
        fn: () async {
          attempt++;
          if (attempt < 3) throw Exception('fail $attempt');
          return 'ok';
        },
        config: RetryConfig(
          maxRetries: 3,
          retryDelay: (_, {random}) => Duration.zero, // no delay for tests
        ),
        onFailed: (count, error) => failures.add(count),
      );

      final result = await retryer.start();
      expect(result, 'ok');
      expect(attempt, 3);
      expect(failures, [1, 2]);
    });

    test('gives up after maxRetries and throws', () async {
      var errorCalled = false;

      final retryer = Retryer<String>(
        fn: () async => throw Exception('always fails'),
        config: RetryConfig(
          maxRetries: 2,
          retryDelay: (_, {random}) => Duration.zero,
        ),
        onError: (_) => errorCalled = true,
      );

      expect(() => retryer.start(), throwsException);
      await Future<void>.delayed(Duration.zero);
      expect(errorCalled, isTrue);
    });

    test('retry: 0 means no retries', () async {
      var attempts = 0;

      final retryer = Retryer<String>(
        fn: () async {
          attempts++;
          throw Exception('fail');
        },
        config: const RetryConfig(maxRetries: 0),
      );

      expect(() => retryer.start(), throwsException);
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
    });

    test('shouldRetry: false skips retries', () async {
      var attempts = 0;

      final retryer = Retryer<String>(
        fn: () async {
          attempts++;
          throw Exception('fail');
        },
        config: RetryConfig(
          maxRetries: 3,
          retryDelay: (_, {random}) => Duration.zero,
          shouldRetry: (_) => false,
        ),
      );

      expect(() => retryer.start(), throwsException);
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
    });

    test('cancel throws RetryerCancelledException', () async {
      final retryer = Retryer<String>(
        fn: () async {
          await Future<void>.delayed(const Duration(seconds: 10));
          return 'ok';
        },
        config: const RetryConfig(maxRetries: 0),
      );

      final future = retryer.start();
      retryer.cancel();

      expect(future, throwsA(isA<RetryerCancelledException>()));
    });

    group('network modes', () {
      setUp(() {
        OnlineManager.instance.setOnline(true);
      });

      test('online mode pauses when offline', () async {
        OnlineManager.instance.setOnline(false);

        var pauseCalled = false;
        var continueCalled = false;

        final retryer = Retryer<String>(
          fn: () async => 'ok',
          config: const RetryConfig(
            maxRetries: 0,
            networkMode: NetworkMode.online,
          ),
          onPause: () => pauseCalled = true,
          onContinue: () => continueCalled = true,
        );

        final future = retryer.start();

        // Should be paused
        await Future<void>.delayed(Duration.zero);
        expect(pauseCalled, isTrue);

        // Come back online
        OnlineManager.instance.setOnline(true);
        final result = await future;
        expect(result, 'ok');
        expect(continueCalled, isTrue);
      });

      test('always mode ignores offline state', () async {
        OnlineManager.instance.setOnline(false);

        final retryer = Retryer<String>(
          fn: () async => 'ok',
          config: const RetryConfig(
            maxRetries: 0,
            networkMode: NetworkMode.always,
          ),
        );

        final result = await retryer.start();
        expect(result, 'ok');
      });

      test('offlineFirst tries first request regardless', () async {
        OnlineManager.instance.setOnline(false);

        var attempts = 0;
        final retryer = Retryer<String>(
          fn: () async {
            attempts++;
            if (attempts == 1) throw Exception('offline');
            return 'ok';
          },
          config: RetryConfig(
            maxRetries: 1,
            retryDelay: (_, {random}) => Duration.zero,
            networkMode: NetworkMode.offlineFirst,
          ),
        );

        // First attempt goes through (offlineFirst), fails, then
        // second attempt waits for online since we're offline
        final future = retryer.start();
        await Future<void>.delayed(Duration.zero);
        expect(attempts, 1); // first attempt ran even though offline

        // Come online for retry
        OnlineManager.instance.setOnline(true);
        final result = await future;
        expect(result, 'ok');
        expect(attempts, 2);
      });
    });
  });
}
