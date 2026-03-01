import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class QueryBuilderWidget extends StatefulWidget {
  const QueryBuilderWidget({
    super.key,
    required this.queryFn,
  });

  final Future<String> Function() queryFn;

  @override
  State<QueryBuilderWidget> createState() => _QueryBuilderWidgetState();
}

class _QueryBuilderWidgetState extends State<QueryBuilderWidget>
    with QueryMixin {
  late final data = query<String>(
    ['builder-test'],
    widget.queryFn,
    retry: 0,
  );

  @override
  Widget build(BuildContext context) {
    return QueryBuilder<String>(
      query: data,
      builder: (context, state, child) {
        if (state.isLoading) {
          return const Text('loading', textDirection: TextDirection.ltr);
        }
        if (state.isError) {
          return Text('error:${state.error}',
              textDirection: TextDirection.ltr);
        }
        return Text('data:${state.data}', textDirection: TextDirection.ltr);
      },
    );
  }
}

class QueryBuilderChildWidget extends StatefulWidget {
  const QueryBuilderChildWidget({super.key});

  @override
  State<QueryBuilderChildWidget> createState() =>
      _QueryBuilderChildWidgetState();
}

class _QueryBuilderChildWidgetState extends State<QueryBuilderChildWidget>
    with QueryMixin {
  late final data = query<String>(
    ['child-test'],
    () async => 'hello',
    retry: 0,
  );

  @override
  Widget build(BuildContext context) {
    return QueryBuilder<String>(
      query: data,
      child: const Text('static-child', textDirection: TextDirection.ltr),
      builder: (context, state, child) {
        return Column(
          textDirection: TextDirection.ltr,
          children: [
            if (child != null) child,
            Text('state:${state.status.name}',
                textDirection: TextDirection.ltr),
          ],
        );
      },
    );
  }
}

class MutationBuilderWidget extends StatefulWidget {
  const MutationBuilderWidget({
    super.key,
    required this.mutationFn,
  });

  final Future<String> Function(String input) mutationFn;

  @override
  State<MutationBuilderWidget> createState() => MutationBuilderWidgetState();
}

class MutationBuilderWidgetState extends State<MutationBuilderWidget>
    with QueryMixin {
  late final addItem = mutation<String, String>(widget.mutationFn);

  void doMutate(String input) => addItem.mutate(input);

  @override
  Widget build(BuildContext context) {
    return MutationBuilder<String, String>(
      mutation: addItem,
      builder: (context, state, child) => switch (state) {
        MutationIdle() =>
          const Text('idle', textDirection: TextDirection.ltr),
        MutationLoading() =>
          const Text('loading', textDirection: TextDirection.ltr),
        MutationSuccess(:final data) =>
          Text('success:$data', textDirection: TextDirection.ltr),
        MutationError(:final error) =>
          Text('error:$error', textDirection: TextDirection.ltr),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    NotifyManager.instance.scheduleFn = (cb) => cb();
  });

  group('QueryBuilder', () {
    late QueryClient client;

    setUp(() {
      client = QueryClient();
      QueryClient.instance = client;
    });

    tearDown(() {
      client.dispose();
      QueryClient.resetInstance();
    });

    testWidgets('renders loading then data', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(QueryBuilderWidget(
        queryFn: () => completer.future,
      ));

      expect(find.text('loading'), findsOneWidget);

      completer.complete('hello');
      await tester.pump();

      expect(find.text('data:hello'), findsOneWidget);
    });

    testWidgets('renders error state', (tester) async {
      await tester.pumpWidget(QueryBuilderWidget(
        queryFn: () async => throw 'boom',
      ));

      await tester.pump();

      expect(find.text('error:boom'), findsOneWidget);
    });

    testWidgets('passes child through to builder', (tester) async {
      await tester.pumpWidget(const QueryBuilderChildWidget());

      await tester.pump();

      expect(find.text('static-child'), findsOneWidget);
      expect(find.text('state:success'), findsOneWidget);
    });
  });

  group('MutationBuilder', () {
    late QueryClient client;

    setUp(() {
      client = QueryClient();
      QueryClient.instance = client;
    });

    tearDown(() {
      client.dispose();
      QueryClient.resetInstance();
    });

    testWidgets('renders idle then loading then success', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(MutationBuilderWidget(
        mutationFn: (_) => completer.future,
      ));

      expect(find.text('idle'), findsOneWidget);

      final state = tester.state<MutationBuilderWidgetState>(
        find.byType(MutationBuilderWidget),
      );
      state.doMutate('test');
      await tester.pump();

      expect(find.text('loading'), findsOneWidget);

      completer.complete('done');
      await tester.pump();

      expect(find.text('success:done'), findsOneWidget);
    });

    testWidgets('renders error state', (tester) async {
      await tester.pumpWidget(MutationBuilderWidget(
        mutationFn: (_) async => throw 'nope',
      ));

      final state = tester.state<MutationBuilderWidgetState>(
        find.byType(MutationBuilderWidget),
      );
      state.doMutate('test');
      await tester.pump();
      await tester.pump();

      expect(find.text('error:nope'), findsOneWidget);
    });
  });
}
