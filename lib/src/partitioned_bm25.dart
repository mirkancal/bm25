// partitioned_bm25.dart
// Tiny façade when you want *per-file* IDF & zero wasted postings.
import 'dart:async';
import 'bm25.dart';
import 'bm25_document.dart';
import 'search_result.dart';

class PartitionedBM25 {
  final Map<String, BM25> _part;   // key → sub-index

  PartitionedBM25._(this._part);

  static Future<PartitionedBM25> build(
    Iterable<BM25Document> docs, {
    required String Function(BM25Document) partitionBy,
    List<String> indexFields = const ['filePath'],
    Set<String>? stopWords,
  }) async {
    final groups = <String, List<BM25Document>>{};
    for (final d in docs) {
      final k = partitionBy(d);
      groups.putIfAbsent(k, () => []).add(d);
    }
    final map = <String, BM25>{};
    for (final e in groups.entries) {
      map[e.key] = await BM25.build(
        e.value,
        indexFields: indexFields,
        stopWords: stopWords,
      );
    }
    return PartitionedBM25._(map);
  }

  /// Search inside a single partition.
  Future<List<SearchResult>> searchIn(
    String key,
    String query, {
    int limit = 10,
  }) =>
      _part[key]?.search(query, limit: limit) ?? Future.value(const []);

  /// Search several partitions and merge top-k.
  Future<List<SearchResult>> searchMany(
    Iterable<String> keys,
    String query, {
    int limit = 10,
  }) async {
    final futures = [
      for (final k in keys) if (_part[k] != null) _part[k]!.search(query)
    ];
    if (futures.isEmpty) return const [];
    final parts = await Future.wait(futures);

    // k-way merge (simple concat+sort is fine for ≤5 partitions)
    final merged = parts.expand((x) => x).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return merged.take(limit).toList();
  }

  Future<void> dispose() async {
    await Future.wait(_part.values.map((i) => i.dispose()));
  }
}