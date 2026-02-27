import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('QueryState', () {
    test('QueryInitial equality', () {
      expect(const QueryInitial<int>(), equals(const QueryInitial<int>()));
    });

    test('QueryLoading equality', () {
      expect(const QueryLoading<int>(), equals(const QueryLoading<int>()));
    });

    test('QueryData equality', () {
      expect(const QueryData<int>(42), equals(const QueryData<int>(42)));
      expect(
        const QueryData<int>(42),
        isNot(equals(const QueryData<int>(99))),
      );
      expect(
        const QueryData<int>(42, isRefetching: true),
        isNot(equals(const QueryData<int>(42))),
      );
    });

    test('QueryError equality', () {
      expect(
        const QueryError<int>('fail'),
        equals(const QueryError<int>('fail')),
      );
      expect(
        const QueryError<int>('fail', staleData: 42),
        equals(const QueryError<int>('fail', staleData: 42)),
      );
      expect(
        const QueryError<int>('fail'),
        isNot(equals(const QueryError<int>('other'))),
      );
    });

    test('pattern matching works', () {
      final QueryState<int> state = const QueryData<int>(42);
      final result = switch (state) {
        QueryInitial() => 'initial',
        QueryLoading() => 'loading',
        QueryData(:final data) => 'data: $data',
        QueryError(:final error) => 'error: $error',
      };
      expect(result, 'data: 42');
    });

    test('pattern matching with isRefetching', () {
      final QueryState<int> state =
          const QueryData<int>(42, isRefetching: true);
      final result = switch (state) {
        QueryData(:final data, :final isRefetching) =>
          'data: $data, refetching: $isRefetching',
        _ => 'other',
      };
      expect(result, 'data: 42, refetching: true');
    });

    test('QueryError exposes staleData', () {
      final QueryState<int> state =
          const QueryError<int>('fail', staleData: 42);
      final result = switch (state) {
        QueryError(:final error, :final staleData) =>
          'error: $error, stale: $staleData',
        _ => 'other',
      };
      expect(result, 'error: fail, stale: 42');
    });
  });
}
