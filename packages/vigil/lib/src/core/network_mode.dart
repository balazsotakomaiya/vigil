/// Controls how a query/mutation interacts with network connectivity.
enum NetworkMode {
  /// Only fetch when the device is online (default).
  online,

  /// Fetch regardless of network state.
  always,

  /// Try the first request regardless of network state, then respect
  /// online/offline for retries. Useful with offline persistence.
  offlineFirst,
}
