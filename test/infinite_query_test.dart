import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('InfiniteQueryData', () {
    test('appendPage adds to end', () {
      var data = const InfiniteQueryData<List<int>, int>();
      data = data.appendPage([1, 2, 3], 1);
      expect(data.pages.length, 1);
      expect(data.pages[0], [1, 2, 3]);
      expect(data.pageParams, [1]);

      data = data.appendPage([4, 5, 6], 2);
      expect(data.pages.length, 2);
      expect(data.pageParams, [1, 2]);
    });

    test('prependPage adds to beginning', () {
      var data = const InfiniteQueryData<List<int>, int>();
      data = data.appendPage([4, 5, 6], 2);
      data = data.prependPage([1, 2, 3], 1);

      expect(data.pages.length, 2);
      expect(data.pages[0], [1, 2, 3]);
      expect(data.pages[1], [4, 5, 6]);
      expect(data.pageParams, [1, 2]);
    });

    test('evict removes oldest pages', () {
      var data = const InfiniteQueryData<String, int>();
      data = data.appendPage('page1', 1);
      data = data.appendPage('page2', 2);
      data = data.appendPage('page3', 3);

      data = data.evict(2);
      expect(data.pages, ['page2', 'page3']);
      expect(data.pageParams, [2, 3]);
    });

    test('evict no-op when under limit', () {
      var data = const InfiniteQueryData<String, int>();
      data = data.appendPage('page1', 1);
      final evicted = data.evict(5);
      expect(identical(evicted, data), isTrue);
    });

    test('equality', () {
      var a = const InfiniteQueryData<String, int>();
      a = a.appendPage('page1', 1);

      var b = const InfiniteQueryData<String, int>();
      b = b.appendPage('page1', 1);

      expect(a, equals(b));
    });
  });

  group('InfiniteQueryHandle', () {
    late List<String> stateLog;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      FocusManager.instance.setFocused(true);
      OnlineManager.instance.setOnline(true);
      stateLog = [];
    });

    test('fetches initial page on creation', () async {
      final handle = InfiniteQueryHandle<List<int>, int>(
        key: ['items'],
        queryFn: (page) async => List.generate(10, (i) => page * 10 + i),
        initialPageParam: 0,
        getNextPageParam: (lastPage, allPages) =>
            lastPage.length == 10 ? allPages.length : null,
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      // Wait for the initial fetch.
      await Future<void>.delayed(Duration.zero);

      expect(handle.state.isSuccess, isTrue);
      expect(handle.pages.length, 1);
      expect(handle.pages[0].length, 10);
      expect(handle.pageParams, [0]);

      handle.dispose();
    });

    test('fetchNextPage appends pages', () async {
      final handle = InfiniteQueryHandle<List<int>, int>(
        key: ['items-next'],
        queryFn: (page) async => List.generate(10, (i) => page * 10 + i),
        initialPageParam: 0,
        getNextPageParam: (lastPage, allPages) =>
            allPages.length < 3 ? allPages.length : null,
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      await Future<void>.delayed(Duration.zero);
      expect(handle.pages.length, 1);

      await handle.fetchNextPage();
      expect(handle.pages.length, 2);
      expect(handle.pageParams, [0, 1]);

      await handle.fetchNextPage();
      expect(handle.pages.length, 3);
      expect(handle.pageParams, [0, 1, 2]);

      handle.dispose();
    });

    test('hasNextPage returns false when no more pages', () async {
      final handle = InfiniteQueryHandle<List<int>, int>(
        key: ['items-has-next'],
        queryFn: (page) async => List.generate(10, (i) => page * 10 + i),
        initialPageParam: 0,
        getNextPageParam: (lastPage, allPages) =>
            allPages.length < 2 ? allPages.length : null,
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      await Future<void>.delayed(Duration.zero);
      expect(handle.hasNextPage, isTrue);

      await handle.fetchNextPage();
      expect(handle.hasNextPage, isFalse);
      expect(handle.pages.length, 2);

      // fetchNextPage should be a no-op now.
      await handle.fetchNextPage();
      expect(handle.pages.length, 2);

      handle.dispose();
    });

    test('fetchPreviousPage prepends pages', () async {
      final handle = InfiniteQueryHandle<List<int>, int>(
        key: ['items-prev'],
        queryFn: (page) async => List.generate(5, (i) => page * 5 + i),
        initialPageParam: 2,
        getNextPageParam: (_, __) => null,
        getPreviousPageParam: (firstPage, allPages) {
          final firstParam = allPages.length > 0 ? 2 - allPages.length : null;
          return firstParam != null && firstParam >= 0 ? firstParam : null;
        },
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      await Future<void>.delayed(Duration.zero);
      expect(handle.pages.length, 1);
      expect(handle.pageParams, [2]);

      await handle.fetchPreviousPage();
      expect(handle.pages.length, 2);
      // Previous page should be prepended.
      expect(handle.pageParams[0], 1);
      expect(handle.pageParams[1], 2);

      handle.dispose();
    });

    test('maxPages applies FIFO eviction', () async {
      final handle = InfiniteQueryHandle<String, int>(
        key: ['items-max'],
        queryFn: (page) async => 'page-$page',
        initialPageParam: 0,
        getNextPageParam: (_, allPages) => allPages.length,
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
        maxPages: 2,
      );

      await Future<void>.delayed(Duration.zero);
      expect(handle.pages, ['page-0']);

      await handle.fetchNextPage();
      expect(handle.pages, ['page-0', 'page-1']);

      await handle.fetchNextPage();
      // Oldest page evicted.
      expect(handle.pages, ['page-1', 'page-2']);

      handle.dispose();
    });

    test('refetchAllPages re-fetches each page in order', () async {
      var callCount = 0;
      final handle = InfiniteQueryHandle<String, int>(
        key: ['items-refetch'],
        queryFn: (page) async {
          callCount++;
          return 'page-$page-v$callCount';
        },
        initialPageParam: 0,
        getNextPageParam: (_, allPages) =>
            allPages.length < 2 ? allPages.length : null,
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      await Future<void>.delayed(Duration.zero);
      await handle.fetchNextPage();
      expect(handle.pages.length, 2);
      callCount = 0;

      await handle.refetchAllPages();
      // Both pages should be re-fetched.
      expect(callCount, 2);
      expect(handle.pages.length, 2);
      // Data should be updated.
      expect(handle.pages[0], contains('v'));
      expect(handle.pages[1], contains('v'));

      handle.dispose();
    });

    test('error state on fetch failure', () async {
      final handle = InfiniteQueryHandle<String, int>(
        key: ['items-error'],
        queryFn: (page) async => throw Exception('network error'),
        initialPageParam: 0,
        getNextPageParam: (_, __) => null,
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      await Future<void>.delayed(Duration.zero);

      expect(handle.isError, isTrue);
      expect(handle.error, isA<Exception>());

      handle.dispose();
    });

    test('enabled=false prevents fetching', () async {
      var fetchCount = 0;
      final handle = InfiniteQueryHandle<String, int>(
        key: ['items-disabled'],
        queryFn: (page) async {
          fetchCount++;
          return 'page-$page';
        },
        initialPageParam: 0,
        getNextPageParam: (_, __) => null,
        onStateChanged: () => stateLog.add('changed'),
        retryConfig: const RetryConfig(maxRetries: 0),
        enabled: false,
      );

      await Future<void>.delayed(Duration.zero);
      expect(fetchCount, 0);
      expect(handle.state.isPending, isTrue);
      expect(handle.state.isIdle, isTrue);

      handle.dispose();
    });
  });
}
