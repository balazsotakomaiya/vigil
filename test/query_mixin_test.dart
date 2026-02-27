import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// A minimal widget that uses [QueryMixin] for testing.
class TestWidget extends StatefulWidget {
  const TestWidget({
    super.key,
    required this.queryKey,
    required this.queryFn,
    this.stale = Duration.zero,
    this.refetchOnMount = true,
    this.enabled = true,
    this.placeholderData,
  });

  final List<dynamic> queryKey;
  final Future<String> Function() queryFn;
  final Duration stale;
  final bool refetchOnMount;
  final bool enabled;
  final String? placeholderData;

  @override
  State<TestWidget> createState() => TestWidgetState();
}

class TestWidgetState extends State<TestWidget> with QueryMixin {
  late final data = query<String>(
    widget.queryKey,
    widget.queryFn,
    stale: widget.stale,
    refetchOnMount: widget.refetchOnMount,
    enabled: widget.enabled,
    placeholderData: widget.placeholderData,
  );

  @override
  Widget build(BuildContext context) {
    return switch (data.state) {
      QueryInitial() => const Text('initial', textDirection: TextDirection.ltr),
      QueryLoading() => const Text('loading', textDirection: TextDirection.ltr),
      QueryData(:final data, :final isRefetching) => Text(
          isRefetching ? 'refetching:$data' : 'data:$data',
          textDirection: TextDirection.ltr,
        ),
      QueryError(:final error, :final staleData) => Text(
          staleData != null
              ? 'error:$error stale:$staleData'
              : 'error:$error',
          textDirection: TextDirection.ltr,
        ),
    };
  }
}

/// Widget that uses a mutation.
class MutationWidget extends StatefulWidget {
  const MutationWidget({
    super.key,
    required this.mutationFn,
    this.invalidates,
    this.onSuccess,
    this.onError,
    this.optimisticUpdate,
  });

  final Future<String> Function(String input) mutationFn;
  final List<List<dynamic>>? invalidates;
  final void Function(String data)? onSuccess;
  final void Function(Object error, void Function() rollback)? onError;
  final void Function(String input)? optimisticUpdate;

  @override
  State<MutationWidget> createState() => MutationWidgetState();
}

class MutationWidgetState extends State<MutationWidget> with QueryMixin {
  late final doMutation = mutation<String, String>(
    widget.mutationFn,
    invalidates: widget.invalidates,
    onSuccess: widget.onSuccess,
    onError: widget.onError,
    optimisticUpdate: widget.optimisticUpdate,
  );

  @override
  Widget build(BuildContext context) {
    return switch (doMutation.state) {
      MutationIdle() => const Text('idle', textDirection: TextDirection.ltr),
      MutationLoading() =>
        const Text('mutating', textDirection: TextDirection.ltr),
      MutationSuccess(:final data) =>
        Text('success:$data', textDirection: TextDirection.ltr),
      MutationError(:final error) =>
        Text('error:$error', textDirection: TextDirection.ltr),
    };
  }
}

void main() {
  group('QueryMixin widget tests', () {
    late QueryClient client;

    setUp(() {
      client = QueryClient();
      QueryClient.instance = client;
    });

    tearDown(() {
      client.dispose();
      QueryClient.resetInstance();
    });

    testWidgets('shows loading then data', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(TestWidget(
        queryKey: ['test'],
        queryFn: () => completer.future,
      ));

      expect(find.text('loading'), findsOneWidget);

      completer.complete('hello');
      await tester.pump();

      expect(find.text('data:hello'), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      await tester.pumpWidget(TestWidget(
        queryKey: ['error'],
        queryFn: () async => throw Exception('boom'),
      ));

      await tester.pump();

      expect(find.textContaining('error:'), findsOneWidget);
    });

    testWidgets('shows cached data immediately', (tester) async {
      // Prime the cache.
      final entry = client.getOrCreateEntry(['cached']);
      entry.data = 'cached-value';
      entry.fetchedAt = DateTime.now();

      await tester.pumpWidget(TestWidget(
        queryKey: ['cached'],
        queryFn: () async => 'should-not-fetch',
        stale: const Duration(minutes: 5),
      ));

      // Should show cached data immediately, no loading.
      expect(find.text('data:cached-value'), findsOneWidget);
    });

    testWidgets('stale-while-revalidate pattern', (tester) async {
      // Prime cache with stale data.
      final entry = client.getOrCreateEntry(['swr']);
      entry.data = 'old';
      entry.fetchedAt =
          DateTime.now().subtract(const Duration(minutes: 10));

      final completer = Completer<String>();

      await tester.pumpWidget(TestWidget(
        queryKey: ['swr'],
        queryFn: () => completer.future,
        stale: const Duration(minutes: 5),
      ));

      // Shows stale data with refetching indicator.
      expect(find.text('refetching:old'), findsOneWidget);

      completer.complete('new');
      await tester.pump();

      expect(find.text('data:new'), findsOneWidget);
    });

    testWidgets('disabled query shows initial state', (tester) async {
      await tester.pumpWidget(TestWidget(
        queryKey: ['disabled'],
        queryFn: () async => 'nope',
        enabled: false,
      ));

      expect(find.text('initial'), findsOneWidget);

      await tester.pump();
      // Still initial — no fetch triggered.
      expect(find.text('initial'), findsOneWidget);
    });

    testWidgets('placeholder data shown while loading', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(TestWidget(
        queryKey: ['ph'],
        queryFn: () => completer.future,
        placeholderData: 'placeholder',
      ));

      expect(find.text('refetching:placeholder'), findsOneWidget);

      completer.complete('real');
      await tester.pump();

      expect(find.text('data:real'), findsOneWidget);
    });

    testWidgets('disposes handles on widget removal', (tester) async {
      await tester.pumpWidget(TestWidget(
        queryKey: ['dispose'],
        queryFn: () async => 'data',
      ));

      await tester.pump();

      // Remove the widget.
      await tester.pumpWidget(
        const SizedBox(key: Key('empty')),
      );

      // The entry should have zero listeners now, GC timer started.
      final entry = client.getEntry('["dispose"]');
      expect(entry?.listenerCount, 0);
    });
  });

  group('MutationMixin widget tests', () {
    late QueryClient client;

    setUp(() {
      client = QueryClient();
      QueryClient.instance = client;
    });

    tearDown(() {
      client.dispose();
      QueryClient.resetInstance();
    });

    testWidgets('mutation idle → loading → success', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(MutationWidget(
        mutationFn: (input) => completer.future,
      ));

      expect(find.text('idle'), findsOneWidget);

      final state =
          tester.state<MutationWidgetState>(find.byType(MutationWidget));
      state.doMutation.mutate('input');
      await tester.pump();

      expect(find.text('mutating'), findsOneWidget);

      completer.complete('done');
      await tester.pump();

      expect(find.text('success:done'), findsOneWidget);
    });

    testWidgets('mutation idle → loading → error', (tester) async {
      await tester.pumpWidget(MutationWidget(
        mutationFn: (input) async => throw Exception('fail'),
      ));

      final state =
          tester.state<MutationWidgetState>(find.byType(MutationWidget));
      state.doMutation.mutate('input');
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('error:'), findsOneWidget);
    });

    testWidgets('mutation calls onSuccess', (tester) async {
      String? successResult;

      await tester.pumpWidget(MutationWidget(
        mutationFn: (input) async => 'result',
        onSuccess: (data) => successResult = data,
      ));

      final state =
          tester.state<MutationWidgetState>(find.byType(MutationWidget));
      await state.doMutation.mutate('input');
      await tester.pump();

      expect(successResult, 'result');
    });

    testWidgets('mutation invalidates queries on success', (tester) async {
      final entry = client.getOrCreateEntry(['todos']);
      entry.data = [1, 2, 3];
      entry.fetchedAt = DateTime.now();

      await tester.pumpWidget(MutationWidget(
        mutationFn: (input) async => 'ok',
        invalidates: [
          ['todos']
        ],
      ));

      final state =
          tester.state<MutationWidgetState>(find.byType(MutationWidget));
      await state.doMutation.mutate('input');
      await tester.pump();

      expect(entry.fetchedAt, isNull); // invalidated
    });
  });

  group('QueryClientProvider', () {
    testWidgets('provides client to descendants', (tester) async {
      final customClient = QueryClient();

      // Prime data on custom client.
      final entry = customClient.getOrCreateEntry(['provided']);
      entry.data = 'from-provider';
      entry.fetchedAt = DateTime.now();

      await tester.pumpWidget(QueryClientProvider(
        client: customClient,
        child: TestWidget(
          queryKey: ['provided'],
          queryFn: () async => 'should-not-fetch',
          stale: const Duration(minutes: 5),
        ),
      ));

      expect(find.text('data:from-provider'), findsOneWidget);

      customClient.dispose();
    });
  });
}
