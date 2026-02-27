import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('MutationHandle', () {
    late QueryClient client;
    late List<String> stateLog;

    setUp(() {
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
    }) {
      return MutationHandle<TData, TInput>(
        mutationFn: mutationFn,
        client: client,
        onStateChanged: () => stateLog.add('changed'),
        invalidates: invalidates,
        onSuccess: onSuccess,
        onError: onError,
        optimisticUpdate: optimisticUpdate,
      );
    }

    test('starts in idle state', () {
      final m = createMutation<String, void>(
        mutationFn: (_) async => 'ok',
      );
      expect(m.state, isA<MutationIdle<String>>());
      expect(m.isMutating, isFalse);
      m.dispose();
    });

    test('transitions through loading → success', () async {
      final completer = Completer<String>();
      final m = createMutation<String, void>(
        mutationFn: (_) => completer.future,
      );

      final future = m.mutate(null);
      expect(m.state, isA<MutationLoading<String>>());
      expect(m.isMutating, isTrue);

      completer.complete('done');
      await future;

      expect(m.state, isA<MutationSuccess<String>>());
      expect(m.data, 'done');
      expect(m.isMutating, isFalse);

      m.dispose();
    });

    test('transitions through loading → error', () async {
      final m = createMutation<String, void>(
        mutationFn: (_) async => throw Exception('fail'),
      );

      await m.mutate(null);

      expect(m.state, isA<MutationError<String>>());
      expect(m.isError, isTrue);
      expect(m.error, isA<Exception>());

      m.dispose();
    });

    test('calls onSuccess callback', () async {
      String? successData;
      final m = createMutation<String, void>(
        mutationFn: (_) async => 'result',
        onSuccess: (data) => successData = data,
      );

      await m.mutate(null);
      expect(successData, 'result');

      m.dispose();
    });

    test('calls onError callback with rollback', () async {
      Object? receivedError;
      void Function()? receivedRollback;

      final m = createMutation<String, void>(
        mutationFn: (_) async => throw Exception('fail'),
        onError: (error, rollback) {
          receivedError = error;
          receivedRollback = rollback;
        },
      );

      await m.mutate(null);
      expect(receivedError, isA<Exception>());
      expect(receivedRollback, isNotNull);

      m.dispose();
    });

    test('invalidates queries on success', () async {
      final entry = client.getOrCreateEntry(['todos']);
      entry.data = [1, 2, 3];
      entry.fetchedAt = DateTime.now();

      final m = createMutation<String, void>(
        mutationFn: (_) async => 'ok',
        invalidates: [
          ['todos']
        ],
      );

      await m.mutate(null);

      // Entry should have been invalidated (fetchedAt cleared).
      expect(entry.fetchedAt, isNull);

      m.dispose();
    });

    test('does not invalidate on error', () async {
      final entry = client.getOrCreateEntry(['todos']);
      entry.data = [1, 2, 3];
      final before = DateTime.now();
      entry.fetchedAt = before;

      final m = createMutation<String, void>(
        mutationFn: (_) async => throw Exception('fail'),
        invalidates: [
          ['todos']
        ],
        onError: (_, __) {},
      );

      await m.mutate(null);

      // Entry should NOT have been invalidated.
      expect(entry.fetchedAt, before);

      m.dispose();
    });

    group('optimistic updates', () {
      test('applies optimistic update before mutation completes', () async {
        final entry = client.getOrCreateEntry(['todos']);
        entry.data = [1, 2, 3];
        entry.fetchedAt = DateTime.now();

        final completer = Completer<String>();
        late List<dynamic> dataAfterOptimistic;

        final m = createMutation<String, int>(
          mutationFn: (input) => completer.future,
          invalidates: [
            ['todos']
          ],
          optimisticUpdate: (input) {
            client.setQueryData<List<int>>(
              ['todos'],
              [...(client.getQueryData<List<int>>(['todos'])!), input],
            );
            dataAfterOptimistic = client.getQueryData<List<int>>(['todos'])!;
          },
        );

        final future = m.mutate(4);
        expect(dataAfterOptimistic, [1, 2, 3, 4]);

        completer.complete('ok');
        await future;

        m.dispose();
      });

      test('rollback restores data on error', () async {
        final entry = client.getOrCreateEntry(['todos']);
        entry.data = [1, 2, 3];
        entry.fetchedAt = DateTime.now();

        void Function()? rollbackFn;

        final m = createMutation<String, int>(
          mutationFn: (input) async => throw Exception('fail'),
          invalidates: [
            ['todos']
          ],
          optimisticUpdate: (input) {
            client.setQueryData<List<int>>(
              ['todos'],
              [...(client.getQueryData<List<int>>(['todos'])!), input],
            );
          },
          onError: (error, rollback) {
            rollbackFn = rollback;
          },
        );

        await m.mutate(4);

        // Data was optimistically updated.
        // Now the error handler has the rollback.
        expect(rollbackFn, isNotNull);

        // After rollback, data should be restored.
        rollbackFn!();
        expect(client.getQueryData<List<int>>(['todos']), [1, 2, 3]);

        m.dispose();
      });
    });

    test('reset returns to idle', () async {
      final m = createMutation<String, void>(
        mutationFn: (_) async => 'ok',
      );

      await m.mutate(null);
      expect(m.state, isA<MutationSuccess<String>>());

      m.reset();
      expect(m.state, isA<MutationIdle<String>>());

      m.dispose();
    });

    test('passes input to mutation function', () async {
      String? receivedInput;
      final m = createMutation<String, String>(
        mutationFn: (input) async {
          receivedInput = input;
          return 'ok';
        },
      );

      await m.mutate('hello');
      expect(receivedInput, 'hello');

      m.dispose();
    });
  });
}
