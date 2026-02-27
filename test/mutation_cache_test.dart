import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('MutationCache', () {
    late MutationCache cache;

    setUp(() {
      cache = MutationCache.instance;
      cache.clear();
    });

    test('unscoped entries can always run', () {
      final a = cache.add();
      final b = cache.add();

      expect(cache.canRun(a), isTrue);
      expect(cache.canRun(b), isTrue);

      a.markExecuting();
      expect(cache.canRun(b), isTrue);

      a.dispose();
      b.dispose();
    });

    test('scoped entry blocks other entries with same scope', () {
      final a = cache.add(scope: 'todos');
      final b = cache.add(scope: 'todos');

      expect(cache.canRun(a), isTrue);
      a.markExecuting();

      expect(cache.canRun(b), isFalse);

      a.markDone();
      expect(cache.canRun(b), isTrue);

      a.dispose();
      b.dispose();
    });

    test('different scopes run concurrently', () {
      final a = cache.add(scope: 'todos');
      final b = cache.add(scope: 'users');

      a.markExecuting();
      expect(cache.canRun(b), isTrue);

      a.dispose();
      b.dispose();
    });

    test('markDone triggers runNext for waiting entries', () {
      var proceeded = false;
      final a = cache.add(scope: 'todos');
      final b = cache.add(scope: 'todos');

      a.markExecuting();
      b.markWaiting(() => proceeded = true);

      expect(proceeded, isFalse);
      a.markDone();
      expect(proceeded, isTrue);

      a.dispose();
      b.dispose();
    });

    test('dispose of executing entry triggers runNext', () {
      var proceeded = false;
      final a = cache.add(scope: 'todos');
      final b = cache.add(scope: 'todos');

      a.markExecuting();
      b.markWaiting(() => proceeded = true);

      a.dispose();
      expect(proceeded, isTrue);

      b.dispose();
    });
  });

  group('MutationHandle with scope', () {
    late QueryClient client;
    late List<String> stateLog;

    setUp(() {
      NotifyManager.instance.scheduleFn = (cb) => cb();
      MutationCache.instance.clear();
      client = QueryClient();
      stateLog = [];
    });

    tearDown(() {
      client.dispose();
    });

    MutationHandle<TData, TInput> createMutation<TData, TInput>({
      required Future<TData> Function(TInput input) mutationFn,
      List<List<dynamic>>? invalidates,
      void Function(TData data)? onSuccess,
      void Function(Object error, void Function() rollback)? onError,
      void Function(TInput input)? optimisticUpdate,
      String? scope,
    }) {
      return MutationHandle<TData, TInput>(
        mutationFn: mutationFn,
        client: client,
        onStateChanged: () => stateLog.add('changed'),
        invalidates: invalidates,
        onSuccess: onSuccess,
        onError: onError,
        optimisticUpdate: optimisticUpdate,
        scope: scope,
      );
    }

    test('mutations without scope run concurrently', () async {
      final completerA = Completer<String>();
      final completerB = Completer<String>();

      final a = createMutation<String, void>(
        mutationFn: (_) => completerA.future,
      );
      final b = createMutation<String, void>(
        mutationFn: (_) => completerB.future,
      );

      final futureA = a.mutate(null);
      final futureB = b.mutate(null);

      // Both should be loading concurrently.
      expect(a.isMutating, isTrue);
      expect(b.isMutating, isTrue);

      completerA.complete('a');
      completerB.complete('b');

      await futureA;
      await futureB;

      expect(a.data, 'a');
      expect(b.data, 'b');

      a.dispose();
      b.dispose();
    });

    test('mutations with same scope run serially', () async {
      final executionOrder = <String>[];
      final completerA = Completer<String>();
      final completerB = Completer<String>();

      final a = createMutation<String, void>(
        mutationFn: (_) {
          executionOrder.add('a-start');
          return completerA.future;
        },
        scope: 'my-scope',
      );
      final b = createMutation<String, void>(
        mutationFn: (_) {
          executionOrder.add('b-start');
          return completerB.future;
        },
        scope: 'my-scope',
      );

      final futureA = a.mutate(null);
      final futureB = b.mutate(null);

      // A should be running, B should be waiting.
      expect(executionOrder, ['a-start']);

      completerA.complete('a');
      await futureA;

      // After A completes, B should start.
      expect(executionOrder, ['a-start', 'b-start']);

      completerB.complete('b');
      await futureB;

      expect(a.data, 'a');
      expect(b.data, 'b');

      a.dispose();
      b.dispose();
    });

    test('mutations with different scopes run concurrently', () async {
      final executionOrder = <String>[];
      final completerA = Completer<String>();
      final completerB = Completer<String>();

      final a = createMutation<String, void>(
        mutationFn: (_) {
          executionOrder.add('a-start');
          return completerA.future;
        },
        scope: 'scope-a',
      );
      final b = createMutation<String, void>(
        mutationFn: (_) {
          executionOrder.add('b-start');
          return completerB.future;
        },
        scope: 'scope-b',
      );

      a.mutate(null);
      b.mutate(null);

      // Both should start immediately.
      expect(executionOrder, ['a-start', 'b-start']);

      completerA.complete('a');
      completerB.complete('b');

      a.dispose();
      b.dispose();
    });

    test('scope serialization survives errors', () async {
      final executionOrder = <String>[];
      final completerB = Completer<String>();

      final a = createMutation<String, void>(
        mutationFn: (_) {
          executionOrder.add('a-start');
          return Future.error(Exception('fail'));
        },
        scope: 'my-scope',
        onError: (_, __) {},
      );
      final b = createMutation<String, void>(
        mutationFn: (_) {
          executionOrder.add('b-start');
          return completerB.future;
        },
        scope: 'my-scope',
      );

      await a.mutate(null);
      b.mutate(null);

      // After A errors, B should start.
      expect(executionOrder, ['a-start', 'b-start']);

      completerB.complete('b');

      a.dispose();
      b.dispose();
    });
  });
}
