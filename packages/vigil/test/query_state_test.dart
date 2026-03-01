import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('QueryState', () {
    test('default state is pending + idle', () {
      const state = QueryState<int>();
      expect(state.isPending, isTrue);
      expect(state.isIdle, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.data, isNull);
      expect(state.error, isNull);
    });

    test('isLoading = pending + fetching', () {
      const state = QueryState<int>(
        status: QueryStatus.pending,
        fetchStatus: FetchStatus.fetching,
      );
      expect(state.isLoading, isTrue);
      expect(state.isPending, isTrue);
      expect(state.isFetching, isTrue);
    });

    test('isRefetching = success + fetching', () {
      const state = QueryState<int>(
        status: QueryStatus.success,
        fetchStatus: FetchStatus.fetching,
        data: 42,
      );
      expect(state.isRefetching, isTrue);
      expect(state.isSuccess, isTrue);
      expect(state.isFetching, isTrue);
    });

    test('error state', () {
      const state = QueryState<int>(
        status: QueryStatus.error,
        fetchStatus: FetchStatus.idle,
        error: 'fail',
      );
      expect(state.isError, isTrue);
      expect(state.error, 'fail');
      expect(state.isIdle, isTrue);
    });

    test('paused state', () {
      const state = QueryState<int>(
        status: QueryStatus.pending,
        fetchStatus: FetchStatus.paused,
      );
      expect(state.isPaused, isTrue);
      expect(state.isFetching, isFalse);
    });

    test('error with stale data', () {
      const state = QueryState<int>(
        status: QueryStatus.error,
        fetchStatus: FetchStatus.idle,
        data: 42,
        error: 'fail',
      );
      expect(state.isError, isTrue);
      expect(state.hasData, isTrue);
      expect(state.data, 42);
      expect(state.error, 'fail');
    });

    test('equality', () {
      expect(
        const QueryState<int>(status: QueryStatus.success, data: 42),
        equals(const QueryState<int>(status: QueryStatus.success, data: 42)),
      );
      expect(
        const QueryState<int>(status: QueryStatus.success, data: 42),
        isNot(equals(const QueryState<int>(status: QueryStatus.success, data: 99))),
      );
      expect(
        const QueryState<int>(
          status: QueryStatus.success,
          fetchStatus: FetchStatus.fetching,
          data: 42,
        ),
        isNot(equals(const QueryState<int>(
          status: QueryStatus.success,
          fetchStatus: FetchStatus.idle,
          data: 42,
        ))),
      );
    });

    test('copyWith preserves unchanged fields', () {
      const original = QueryState<int>(
        status: QueryStatus.success,
        fetchStatus: FetchStatus.idle,
        data: 42,
        dataUpdatedAt: 1000,
      );
      final copied = original.copyWith(fetchStatus: FetchStatus.fetching);
      expect(copied.status, QueryStatus.success);
      expect(copied.data, 42);
      expect(copied.dataUpdatedAt, 1000);
      expect(copied.fetchStatus, FetchStatus.fetching);
    });

    test('copyWith can set data to null via closure', () {
      const original = QueryState<int>(
        status: QueryStatus.success,
        data: 42,
      );
      final copied = original.copyWith(data: () => null);
      expect(copied.data, isNull);
    });

    test('pattern matching works with convenience getters', () {
      const QueryState<int> state = QueryState<int>(
        status: QueryStatus.success,
        data: 42,
      );
      final result = switch (state) {
        QueryState(isLoading: true) => 'loading',
        QueryState(isError: true, :final error) => 'error: $error',
        QueryState(isSuccess: true, :final data) => 'data: $data',
        _ => 'other',
      };
      expect(result, 'data: 42');
    });

    test('pattern matching with refetching', () {
      const QueryState<int> state = QueryState<int>(
        status: QueryStatus.success,
        fetchStatus: FetchStatus.fetching,
        data: 42,
      );
      final result = switch (state) {
        QueryState(isRefetching: true, :final data) =>
          'refetching: $data',
        _ => 'other',
      };
      expect(result, 'refetching: 42');
    });
  });
}
