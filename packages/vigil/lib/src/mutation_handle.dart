import 'dart:async';

import 'core/mutation_cache.dart';
import 'mutation_state.dart';
import 'query_client.dart';

/// Handle returned by [QueryMixin.mutation] that manages the lifecycle of an
/// async mutation including optimistic updates and rollback.
///
/// If a [scope] is provided, mutations with the same scope run serially
/// (FIFO). This prevents race conditions on the same resource — e.g. two
/// rapid taps submitting a form.
class MutationHandle<TData, TInput> {
  MutationHandle({
    required Future<TData> Function(TInput input) mutationFn,
    required QueryClient client,
    required void Function() onStateChanged,
    List<List<dynamic>>? invalidates,
    void Function(TData data)? onSuccess,
    void Function(Object error, void Function() rollback)? onError,
    void Function(TInput input)? optimisticUpdate,
    String? scope,
  })  : _mutationFn = mutationFn,
        _client = client,
        _onStateChanged = onStateChanged,
        _invalidates = invalidates,
        _onSuccess = onSuccess,
        _onError = onError,
        _optimisticUpdate = optimisticUpdate,
        _scope = scope;

  final Future<TData> Function(TInput input) _mutationFn;
  final QueryClient _client;
  final void Function() _onStateChanged;
  final List<List<dynamic>>? _invalidates;
  final void Function(TData data)? _onSuccess;
  final void Function(Object error, void Function() rollback)? _onError;
  final void Function(TInput input)? _optimisticUpdate;
  final String? _scope;

  bool _disposed = false;
  MutationCacheEntry? _cacheEntry;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  MutationState<TData> _state = const MutationIdle();

  /// The current state of this mutation.
  MutationState<TData> get state => _state;

  /// `true` while the mutation is in flight.
  bool get isMutating => _state is MutationLoading<TData>;

  /// `true` if the last mutation resulted in an error.
  bool get isError => _state is MutationError<TData>;

  /// The result data if the mutation succeeded, otherwise `null`.
  TData? get data => switch (_state) {
        MutationSuccess<TData>(:final data) => data,
        _ => null,
      };

  /// The error if the mutation failed, otherwise `null`.
  Object? get error => switch (_state) {
        MutationError<TData>(:final error) => error,
        _ => null,
      };

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Execute the mutation with [input].
  ///
  /// If this mutation has a [scope] and another mutation with the same scope
  /// is already running, this call waits for its turn before executing.
  Future<void> mutate(TInput input) async {
    if (_disposed) return;

    _updateState(const MutationLoading());

    // Register in the mutation cache for scope serialization.
    _cacheEntry?.dispose();
    _cacheEntry = MutationCache.instance.add(scope: _scope);

    // Wait for scope if needed.
    if (!MutationCache.instance.canRun(_cacheEntry!)) {
      final completer = Completer<void>();
      _cacheEntry!.markWaiting(() => completer.complete());
      await completer.future;
      if (_disposed) {
        _cacheEntry?.dispose();
        _cacheEntry = null;
        return;
      }
    }

    _cacheEntry!.markExecuting();

    // --- Optimistic update with snapshot for rollback ---
    Map<String, dynamic>? snapshot;
    if (_optimisticUpdate != null && _invalidates != null) {
      snapshot = _client.snapshotEntries(_invalidates!);
    }
    _optimisticUpdate?.call(input);

    final entry = _cacheEntry;
    try {
      final data = await _mutationFn(input);
      if (_disposed) return;

      _updateState(MutationSuccess<TData>(data));

      // Invalidate affected queries so they refetch.
      if (_invalidates != null) {
        for (final key in _invalidates!) {
          _client.invalidateQueries(key);
        }
      }

      try {
        _onSuccess?.call(data);
      } catch (_) {
        // Don't let a callback exception break the mutation lifecycle.
      }
    } catch (e) {
      if (_disposed) return;

      _updateState(MutationError<TData>(e));

      void rollback() {
        if (snapshot != null) {
          _client.restoreSnapshot(snapshot);
        }
      }

      try {
        _onError?.call(e, rollback);
      } catch (_) {
        // Don't let a callback exception break the mutation lifecycle.
      }
    } finally {
      entry?.markDone();
      _cacheEntry = null;
    }
  }

  /// Reset to [MutationIdle] state.
  void reset() {
    if (_disposed) return;
    _updateState(const MutationIdle());
  }

  /// Clean up. Called by [QueryMixin.dispose].
  void dispose() {
    _disposed = true;
    _cacheEntry?.dispose();
    _cacheEntry = null;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _updateState(MutationState<TData> newState) {
    _state = newState;
    if (!_disposed) {
      _onStateChanged();
    }
  }
}
