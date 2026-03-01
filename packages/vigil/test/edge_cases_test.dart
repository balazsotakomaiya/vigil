import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

/// Edge case tests covering bug fixes identified during the codebase audit.
///
/// Each group targets a specific fix. These tests verify the bug is no longer
/// reproducible — i.e. they would have *failed* on the pre-fix code.
void main() {
  // -------------------------------------------------------------------------
  // 1. NotifyManager: exception in one callback must not skip others
  // -------------------------------------------------------------------------
  group('NotifyManager — exception isolation', () {
    late NotifyManager manager;

    setUp(() {
      manager = NotifyManager();
      manager.scheduleFn = (cb) => cb();
    });

    test('exception in one batch callback does not skip remaining callbacks',
        () {
      final log = <String>[];

      manager.batch(() {
        manager.notify(() => log.add('a'));
        manager.notify(() => throw Exception('boom'));
        manager.notify(() => log.add('c'));
      });

      // Pre-fix: only 'a' would appear because the thrown exception skipped 'c'.
      expect(log, ['a', 'c']);
    });

    test('exception in first callback does not block any others', () {
      final log = <String>[];

      manager.batch(() {
        manager.notify(() => throw Exception('first fails'));
        manager.notify(() => log.add('second'));
        manager.notify(() => log.add('third'));
      });

      expect(log, ['second', 'third']);
    });

    test('all callbacks throw — no unhandled exception escapes', () {
      // Should not throw.
      manager.batch(() {
        manager.notify(() => throw Exception('1'));
        manager.notify(() => throw Exception('2'));
        manager.notify(() => throw Exception('3'));
      });
    });
  });

  // -------------------------------------------------------------------------
  // 2. QueryClient.snapshotEntries: shallow copy prevents snapshot corruption
  // -------------------------------------------------------------------------
  group('QueryClient — snapshot shallow copy', () {
    late QueryClient client;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      client = QueryClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('mutating cached List after snapshot does not corrupt snapshot', () {
      final entry = client.getOrCreateEntry(['todos']);
      entry.data = [1, 2, 3];
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;

      final snapshot = client.snapshotEntries([
        ['todos']
      ]);

      // Mutate the live cache *in place*.
      (entry.data as List).add(4);

      // Pre-fix: snapshot would also contain [1,2,3,4] since it held the same
      // reference. Post-fix: snapshot has an independent copy.
      expect(snapshot['["todos"]'], [1, 2, 3]);
    });

    test('mutating cached Map after snapshot does not corrupt snapshot', () {
      final entry = client.getOrCreateEntry(['user']);
      entry.data = {'name': 'Alice'};
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;

      final snapshot = client.snapshotEntries([
        ['user']
      ]);

      // Mutate the live cache.
      (entry.data as Map)['name'] = 'Bob';

      expect(snapshot['["user"]'], {'name': 'Alice'});
    });

    test('restore after in-place mutation returns original values', () {
      final entry = client.getOrCreateEntry(['items']);
      entry.data = ['a', 'b'];
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;

      final snapshot = client.snapshotEntries([
        ['items']
      ]);

      // Simulate optimistic update that mutates in-place.
      (entry.data as List).add('c');
      expect(entry.data, ['a', 'b', 'c']);

      // Rollback.
      client.restoreSnapshot(snapshot);
      expect(entry.data, ['a', 'b']);
    });
  });

  // -------------------------------------------------------------------------
  // 3. InfiniteQueryHandle: _isFetchingDirection resets after exception
  // -------------------------------------------------------------------------
  group('InfiniteQueryHandle — direction flag cleanup', () {
    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      FocusManager.instance.setFocused(true);
      OnlineManager.instance.setOnline(true);
    });

    test('isFetchingNextPage resets after fetchNextPage throws', () async {
      var callCount = 0;
      final handle = InfiniteQueryHandle<String, int>(
        key: ['dir-test'],
        queryFn: (page) async {
          callCount++;
          if (callCount == 2) throw Exception('page 2 fails');
          return 'page-$page';
        },
        initialPageParam: 0,
        getNextPageParam: (_, allPages) => allPages.length,
        onStateChanged: () {},
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      // Initial fetch succeeds.
      await Future<void>.delayed(Duration.zero);
      expect(handle.pages.length, 1);

      // Second fetch should fail.
      await handle.fetchNextPage();

      // Pre-fix: _isFetchingDirection would be stuck as forward after throw.
      // This would cause isFetchingNextPage to be true forever and block
      // subsequent fetches.
      expect(handle.isFetchingNextPage, isFalse);
      expect(handle.isFetchingPreviousPage, isFalse);

      handle.dispose();
    });

    test('isFetchingPreviousPage resets after fetchPreviousPage throws',
        () async {
      var callCount = 0;
      final handle = InfiniteQueryHandle<String, int>(
        key: ['dir-test-prev'],
        queryFn: (page) async {
          callCount++;
          if (callCount == 2) throw Exception('prev page fails');
          return 'page-$page';
        },
        initialPageParam: 5,
        getNextPageParam: (_, __) => null,
        getPreviousPageParam: (_, allPages) {
          return allPages.length < 2 ? 4 : null;
        },
        onStateChanged: () {},
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      await Future<void>.delayed(Duration.zero);
      expect(handle.pages.length, 1);

      await handle.fetchPreviousPage();

      expect(handle.isFetchingPreviousPage, isFalse);
      expect(handle.isFetchingNextPage, isFalse);

      handle.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // 4. MutationHandle: onSuccess/onError callback exceptions don't propagate
  // -------------------------------------------------------------------------
  group('MutationHandle — callback exception isolation', () {
    late QueryClient client;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      client = QueryClient();
    });

    tearDown(() {
      client.dispose();
      MutationCache.instance.clear();
    });

    test('throwing onSuccess does not make mutate() throw', () async {
      final handle = MutationHandle<String, void>(
        mutationFn: (_) async => 'ok',
        client: client,
        onStateChanged: () {},
        onSuccess: (data) => throw Exception('callback error'),
      );

      // Pre-fix: this would throw because onSuccess exception propagated.
      await handle.mutate(null);

      // Mutation still ends in success state.
      expect(handle.state, isA<MutationSuccess<String>>());
      expect(handle.data, 'ok');

      handle.dispose();
    });

    test('throwing onError does not make mutate() throw', () async {
      final handle = MutationHandle<String, void>(
        mutationFn: (_) async => throw Exception('mutation fails'),
        client: client,
        onStateChanged: () {},
        onError: (error, rollback) => throw Exception('callback error'),
      );

      // Pre-fix: this would throw because onError exception propagated.
      await handle.mutate(null);

      // Mutation still ends in error state.
      expect(handle.state, isA<MutationError<String>>());

      handle.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // 5. MutationHandle: scope serialization — no double markDone
  // -------------------------------------------------------------------------
  group('MutationHandle — scope serialization lifecycle', () {
    late QueryClient client;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      client = QueryClient();
    });

    tearDown(() {
      client.dispose();
      MutationCache.instance.clear();
    });

    test('scoped mutations run serially (FIFO)', () async {
      final log = <String>[];

      final m1 = MutationHandle<String, String>(
        mutationFn: (input) async {
          log.add('start:$input');
          await Future<void>.delayed(Duration.zero);
          log.add('end:$input');
          return input;
        },
        client: client,
        onStateChanged: () {},
        scope: 'submit',
      );

      final m2 = MutationHandle<String, String>(
        mutationFn: (input) async {
          log.add('start:$input');
          await Future<void>.delayed(Duration.zero);
          log.add('end:$input');
          return input;
        },
        client: client,
        onStateChanged: () {},
        scope: 'submit',
      );

      final f1 = m1.mutate('first');
      final f2 = m2.mutate('second');

      await f1;
      await f2;

      // First mutation should complete before second starts.
      expect(log.indexOf('end:first'), lessThan(log.indexOf('start:second')));

      m1.dispose();
      m2.dispose();
    });

    test('failed scoped mutation still unblocks next mutation', () async {
      final log = <String>[];

      final m1 = MutationHandle<String, String>(
        mutationFn: (input) async {
          log.add('m1');
          throw Exception('m1 fails');
        },
        client: client,
        onStateChanged: () {},
        onError: (_, __) {},
        scope: 'submit',
      );

      final m2 = MutationHandle<String, String>(
        mutationFn: (input) async {
          log.add('m2');
          return 'ok';
        },
        client: client,
        onStateChanged: () {},
        scope: 'submit',
      );

      final f1 = m1.mutate('a');
      final f2 = m2.mutate('b');

      await f1;
      await f2;

      // Both should have run — m1 failure should not block m2.
      expect(log, ['m1', 'm2']);
      expect(m2.state, isA<MutationSuccess<String>>());

      m1.dispose();
      m2.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // 6. QueryHandle.refetchIfStale: respects isInvalidated flag
  // -------------------------------------------------------------------------
  group('QueryHandle — refetchIfStale respects invalidation', () {
    late QueryClient client;
    late List<String> stateLog;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      client = QueryClient();
      stateLog = [];
    });

    tearDown(() {
      client.dispose();
    });

    test('refetchIfStale triggers when entry is invalidated but not time-stale',
        () async {
      var fetchCount = 0;
      final handle = QueryHandle<String>(
        key: ['invalidate-check'],
        queryFn: () async {
          fetchCount++;
          return 'v$fetchCount';
        },
        client: client,
        onStateChanged: () => stateLog.add('changed'),
        staleTime: const Duration(minutes: 60), // Very long — not time-stale.
        retryConfig: const RetryConfig(maxRetries: 0),
      );

      await Future<void>.delayed(Duration.zero);
      expect(fetchCount, 1);
      expect(handle.data, 'v1');

      // Manually invalidate the entry.
      final entry =
          client.getEntry(QueryClient.serializeKey(['invalidate-check']));
      entry!.isInvalidated = true;

      // refetchIfStale should see the invalidation flag even though data
      // is not time-stale.
      handle.refetchIfStale();
      await Future<void>.delayed(Duration.zero);

      // Pre-fix: fetchCount would still be 1 because refetchIfStale only
      // checked time-based staleness and ignored the invalidation flag.
      expect(fetchCount, 2);
      expect(handle.data, 'v2');

      handle.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // 7. Retryer: _pauseCompleter captured in local variable
  // -------------------------------------------------------------------------
  group('Retryer — pause/resume safety', () {
    setUp(() {
      OnlineManager.instance.setOnline(true);
    });

    tearDown(() {
      OnlineManager.instance.reset();
    });

    test('retryer pauses offline and resumes when back online', () async {
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
      await Future<void>.delayed(Duration.zero);

      expect(pauseCalled, isTrue);

      // Come back online.
      OnlineManager.instance.setOnline(true);
      final result = await future;

      expect(result, 'ok');
      expect(continueCalled, isTrue);
    });

    test('cancel while paused offline completes without error', () async {
      OnlineManager.instance.setOnline(false);

      final retryer = Retryer<String>(
        fn: () async => 'ok',
        config: const RetryConfig(
          maxRetries: 0,
          networkMode: NetworkMode.online,
        ),
      );

      final future = retryer.start();
      await Future<void>.delayed(Duration.zero);

      // Cancel while paused — should not leave dangling completer.
      retryer.cancel();
      expect(future, throwsA(isA<RetryerCancelledException>()));
    });
  });

  // -------------------------------------------------------------------------
  // 8. FocusManager.reset() — test isolation
  // -------------------------------------------------------------------------
  group('FocusManager — reset', () {
    test('reset restores default focused state', () {
      final manager = FocusManager.instance;

      manager.setFocused(false);
      expect(manager.isFocused, isFalse);

      manager.reset();
      expect(manager.isFocused, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 9. OnlineManager.reset() — test isolation
  // -------------------------------------------------------------------------
  group('OnlineManager — reset', () {
    test('reset restores default online state and clears setup', () {
      final manager = OnlineManager.instance;

      manager.setOnline(false);
      expect(manager.isOnline, isFalse);

      var setupCalled = false;
      manager.setEventListener((onChanged) {
        setupCalled = true;
        return () {};
      });

      manager.reset();
      expect(manager.isOnline, isTrue);

      // After reset, adding a subscriber should NOT trigger old setup.
      setupCalled = false;
      final unsub = manager.subscribe(() {});
      expect(setupCalled, isFalse);
      unsub();
    });
  });

  // -------------------------------------------------------------------------
  // Bonus: MutationHandle optimistic update rollback with in-place mutation
  // -------------------------------------------------------------------------
  group('Optimistic rollback with in-place list mutation', () {
    late QueryClient client;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      client = QueryClient();
    });

    tearDown(() {
      client.dispose();
      MutationCache.instance.clear();
    });

    test('rollback restores original data after in-place optimistic mutation',
        () async {
      final entry = client.getOrCreateEntry(['items']);
      entry.data = ['a', 'b'];
      entry.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;

      void Function()? rollbackFn;

      final handle = MutationHandle<String, String>(
        mutationFn: (input) async => throw Exception('fail'),
        client: client,
        onStateChanged: () {},
        invalidates: [
          ['items']
        ],
        optimisticUpdate: (input) {
          // Use setQueryData which triggers the snapshot first.
          final current = client.getQueryData<List<String>>(['items'])!;
          client.setQueryData<List<String>>(['items'], [...current, input]);
        },
        onError: (error, rollback) {
          rollbackFn = rollback;
        },
      );

      await handle.mutate('c');

      expect(rollbackFn, isNotNull);
      rollbackFn!();

      // Snapshot was taken *before* the optimistic update, so this should
      // restore to ['a', 'b'] regardless of the _shallowCopy fix.
      expect(client.getQueryData<List<String>>(['items']), ['a', 'b']);

      handle.dispose();
    });
  });
}
