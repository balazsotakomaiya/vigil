/// Holds the accumulated pages for an infinite query.
///
/// [T] is the data type for each page, [P] is the page parameter type.
class InfiniteQueryData<T, P> {
  const InfiniteQueryData({
    this.pages = const [],
    this.pageParams = const [],
  });

  /// All fetched pages in order (first fetched → last fetched).
  final List<T> pages;

  /// The page parameter used to fetch each page, in the same order as [pages].
  final List<P> pageParams;

  /// Whether any pages have been fetched.
  bool get isEmpty => pages.isEmpty;

  /// The number of fetched pages.
  int get length => pages.length;

  /// Create a copy with an appended page.
  InfiniteQueryData<T, P> appendPage(T page, P param) {
    return InfiniteQueryData<T, P>(
      pages: [...pages, page],
      pageParams: [...pageParams, param],
    );
  }

  /// Create a copy with a prepended page.
  InfiniteQueryData<T, P> prependPage(T page, P param) {
    return InfiniteQueryData<T, P>(
      pages: [page, ...pages],
      pageParams: [param, ...pageParams],
    );
  }

  /// Apply FIFO eviction to keep at most [maxPages] pages.
  InfiniteQueryData<T, P> evict(int maxPages) {
    if (pages.length <= maxPages) return this;
    // Remove the oldest pages (from the beginning).
    final excess = pages.length - maxPages;
    return InfiniteQueryData<T, P>(
      pages: pages.sublist(excess),
      pageParams: pageParams.sublist(excess),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfiniteQueryData<T, P> &&
          _listEquals(pages, other.pages) &&
          _listEquals(pageParams, other.pageParams);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(pages),
        Object.hashAll(pageParams),
      );

  @override
  String toString() =>
      'InfiniteQueryData(pages: ${pages.length}, params: $pageParams)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
