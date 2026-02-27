import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('QueryHandle', () {
    late QueryClient client;
    late List<String> stateLog;

    setUp(() {
      client = QueryClient();
      stateLog = [];
    });

    tearDown(() {
      client.dispose();
    });

    QueryHandle<T> createHandle<T>({
      required List<dynamic> key,
      required Future<T> Function() queryFn,
      Duration staleTime = Duration.zero,
      bool refetchOnMount = true,
      bool enabled = true,
      T? placeholderData,
    }) {
      return QueryHandle<T>(
        key: key,
        queryFn: queryFn,
        client: client,
        onStateChanged: () => stateLog.add('changed'),
        staleTime: staleTime,
        refetchOnMount: refetchOnMount,
        enabled: enabled,
        placeholderData: placeholderData,
      );
    }

    group('initial fetch', () {
      test('starts in loading state and transitions to data', () async {
        final handle = createHandle<String>(
          key: ['test'],
          queryFn: () async => 'hello',
        );

        expect(handle.state, isA<QueryLoading<String>>());
        expect(handle.isLoading, isTrue);

        // Let the microtask queue flush.
        await Future<void>.delayed(Duration.zero);

        expect(handle.state, isA<QueryData<String>>());
        expect(handle.data, 'hello');
        expect(handle.isLoading, isFalse);
        expect(stateLog, isNotEmpty);

        handle.dispose();
      });

      test('transitions to error on fetch failure', () async {
        final handle = createHandle<String>(
          key: ['fail'],
          queryFn: () async => throw Exception('boom'),
        );

        await Future<void>.delayed(Duration.zero);

        expect(handle.state, isA<QueryError<String>>());
        expect(handle.isError, isTrue);
        expect(handle.error, isA<Exception>());

        handle.dispose();
      });
    });

    group('cache hit', () {
      test('returns fresh data immediately without refetch', () async {
        // Prime the cache.
        final entry = client.getOrCreateEntry(['cached']);
        entry.data = 'cached-value';
        entry.fetchedAt = DateTime.now();

        var fetchCount = 0;
        final handle = createHandle<String>(
          key: ['cached'],
          queryFn: () async {
            fetchCount++;
            return 'new-value';
          },
          staleTime: const Duration(minutes: 5),
        );

        // Should have data immediately, no fetch triggered.
        expect(handle.state, isA<QueryData<String>>());
        expect(handle.data, 'cached-value');
        expect((handle.state as QueryData).isRefetching, isFalse);

        await Future<void>.delayed(Duration.zero);
        expect(fetchCount, 0);

        handle.dispose();
      });
    });

    group('stale-while-revalidate', () {
      test('shows stale data with isRefetching while fetching', () async {
        // Prime cache with stale data.
        final entry = client.getOrCreateEntry(['stale']);
        entry.data = 'old';
        entry.fetchedAt =
            DateTime.now().subtract(const Duration(minutes: 10));

        final completer = Completer<String>();
        final handle = createHandle<String>(
          key: ['stale'],
          queryFn: () => completer.future,
          staleTime: const Duration(minutes: 5),
        );

        // Should show stale data with isRefetching.
        expect(handle.state, isA<QueryData<String>>());
        expect(handle.data, 'old');
        expect(handle.isRefetching, isTrue);

        // Complete the fetch.
        completer.complete('new');
        await Future<void>.delayed(Duration.zero);

        expect(handle.data, 'new');
        expect(handle.isRefetching, isFalse);

        handle.dispose();
      });

      test('shows stale data in error state on refetch failure', () async {
        final entry = client.getOrCreateEntry(['stale-err']);
        entry.data = 'old';
        entry.fetchedAt =
            DateTime.now().subtract(const Duration(minutes: 10));

        final handle = createHandle<String>(
          key: ['stale-err'],
          queryFn: () async => throw Exception('network'),
          staleTime: const Duration(minutes: 5),
        );

        await Future<void>.delayed(Duration.zero);

        expect(handle.state, isA<QueryError<String>>());
        final errorState = handle.state as QueryError<String>;
        expect(errorState.staleData, 'old');

        handle.dispose();
      });
    });

    group('deduplication', () {
      test('two handles for same key share one fetch', () async {
        var fetchCount = 0;
        final completer = Completer<String>();

        Future<String> queryFn() {
          fetchCount++;
          return completer.future;
        }

        final h1 = createHandle<String>(key: ['dedup'], queryFn: queryFn);
        final h2 = createHandle<String>(key: ['dedup'], queryFn: queryFn);

        expect(fetchCount, 1); // Only one fetch.

        completer.complete('shared');
        await Future<void>.delayed(Duration.zero);

        expect(h1.data, 'shared');
        expect(h2.data, 'shared');

        h1.dispose();
        h2.dispose();
      });
    });

    group('enabled', () {
      test('does not fetch when disabled', () async {
        var fetched = false;
        final handle = createHandle<String>(
          key: ['disabled'],
          queryFn: () async {
            fetched = true;
            return 'data';
          },
          enabled: false,
        );

        expect(handle.state, isA<QueryInitial<String>>());

        await Future<void>.delayed(Duration.zero);
        expect(fetched, isFalse);

        handle.dispose();
      });
    });

    group('placeholderData', () {
      test('uses placeholder while loading', () async {
        final completer = Completer<String>();
        final handle = createHandle<String>(
          key: ['placeholder'],
          queryFn: () => completer.future,
          placeholderData: 'placeholder',
        );

        expect(handle.state, isA<QueryData<String>>());
        expect(handle.data, 'placeholder');
        expect(handle.isRefetching, isTrue);

        completer.complete('real');
        await Future<void>.delayed(Duration.zero);

        expect(handle.data, 'real');
        expect(handle.isRefetching, isFalse);

        handle.dispose();
      });
    });

    group('refetch', () {
      test('forces a new fetch regardless of stale time', () async {
        final entry = client.getOrCreateEntry(['refetch']);
        entry.data = 'initial';
        entry.fetchedAt = DateTime.now();

        var fetchCount = 0;
        final handle = createHandle<String>(
          key: ['refetch'],
          queryFn: () async {
            fetchCount++;
            return 'refreshed';
          },
          staleTime: const Duration(minutes: 60),
          refetchOnMount: false,
        );

        // Data is fresh, no auto-fetch.
        await Future<void>.delayed(Duration.zero);
        expect(fetchCount, 0);

        handle.refetch();
        await Future<void>.delayed(Duration.zero);

        expect(fetchCount, 1);
        expect(handle.data, 'refreshed');

        handle.dispose();
      });
    });

    group('setData', () {
      test('optimistically updates data', () async {
        final entry = client.getOrCreateEntry(['optimistic']);
        entry.data = [1, 2, 3];
        entry.fetchedAt = DateTime.now();

        final handle = createHandle<List<int>>(
          key: ['optimistic'],
          queryFn: () async => [1, 2, 3],
          staleTime: const Duration(minutes: 5),
        );

        handle.setData((prev) => [...prev, 4]);
        expect(handle.data, [1, 2, 3, 4]);

        handle.dispose();
      });
    });

    group('dispose', () {
      test('stops receiving updates after dispose', () async {
        final handle = createHandle<String>(
          key: ['dispose-test'],
          queryFn: () async => 'data',
        );

        handle.dispose();
        stateLog.clear();

        // Trigger a cache change.
        client.setQueryData(['dispose-test'], 'updated');

        await Future<void>.delayed(Duration.zero);
        expect(stateLog, isEmpty);
      });
    });

    group('invalidation triggers refetch', () {
      test('refetches when cache entry is invalidated', () async {
        var fetchCount = 0;
        final handle = createHandle<String>(
          key: ['invalidate'],
          queryFn: () async {
            fetchCount++;
            return 'v$fetchCount';
          },
        );

        await Future<void>.delayed(Duration.zero);
        expect(fetchCount, 1);
        expect(handle.data, 'v1');

        client.invalidateQueries(['invalidate']);
        await Future<void>.delayed(Duration.zero);

        expect(fetchCount, 2);
        expect(handle.data, 'v2');

        handle.dispose();
      });
    });
  });
}
