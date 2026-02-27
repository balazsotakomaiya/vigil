/// Sealed class representing the state of a mutation.
///
/// Use Dart 3 pattern matching to handle each state:
/// ```dart
/// switch (mutation.state) {
///   MutationIdle() => ...,
///   MutationLoading() => ...,
///   MutationSuccess(:final data) => ...,
///   MutationError(:final error) => ...,
/// }
/// ```
sealed class MutationState<T> {
  const MutationState();
}

/// The mutation has not been triggered yet, or has been reset.
class MutationIdle<T> extends MutationState<T> {
  const MutationIdle();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MutationIdle<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'MutationIdle<$T>()';
}

/// The mutation is currently in progress.
class MutationLoading<T> extends MutationState<T> {
  const MutationLoading();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MutationLoading<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'MutationLoading<$T>()';
}

/// The mutation completed successfully.
class MutationSuccess<T> extends MutationState<T> {
  final T data;

  const MutationSuccess(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutationSuccess<T> && data == other.data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'MutationSuccess<$T>($data)';
}

/// The mutation encountered an error.
class MutationError<T> extends MutationState<T> {
  final Object error;

  const MutationError(this.error);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutationError<T> && error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'MutationError<$T>($error)';
}
