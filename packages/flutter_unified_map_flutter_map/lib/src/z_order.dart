/// Sorted by [zIndex], keeping the iteration order of equal values (Google Maps' order for ties).
List<T> sortedByZ<T>(Iterable<T> items, double Function(T item) zIndex) {
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final byZ = zIndex(a.$2).compareTo(zIndex(b.$2));
      return byZ != 0 ? byZ : a.$1.compareTo(b.$1);
    });
  return List.unmodifiable(indexed.map((e) => e.$2));
}
