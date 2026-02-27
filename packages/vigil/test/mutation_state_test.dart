import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/vigil.dart';

void main() {
  group('MutationState', () {
    test('MutationIdle equality', () {
      expect(const MutationIdle<int>(), equals(const MutationIdle<int>()));
    });

    test('MutationLoading equality', () {
      expect(
        const MutationLoading<int>(),
        equals(const MutationLoading<int>()),
      );
    });

    test('MutationSuccess equality', () {
      expect(
        const MutationSuccess<int>(42),
        equals(const MutationSuccess<int>(42)),
      );
      expect(
        const MutationSuccess<int>(42),
        isNot(equals(const MutationSuccess<int>(99))),
      );
    });

    test('MutationError equality', () {
      expect(
        const MutationError<int>('fail'),
        equals(const MutationError<int>('fail')),
      );
    });

    test('pattern matching works', () {
      final MutationState<int> state = const MutationSuccess<int>(42);
      final result = switch (state) {
        MutationIdle() => 'idle',
        MutationLoading() => 'loading',
        MutationSuccess(:final data) => 'success: $data',
        MutationError(:final error) => 'error: $error',
      };
      expect(result, 'success: 42');
    });
  });
}
