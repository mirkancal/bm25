// partitioned_bm25.dart
// Tiny façade when you want *per-file* IDF & zero wasted postings.
import 'dart:async';
import 'bm25.dart';
import 'bm25_document.dart';
import 'search_result.dart';

/// A partitioned BM25 index for improved search relevance across distinct document sets.
///
/// This class allows you to create separate BM25 indices for different partitions
/// of your document corpus. Each partition maintains its own term statistics,
/// which can improve search relevance when documents naturally fall into distinct
/// categories (e.g., different file types, sources, or topics).
///
/// Benefits of partitioning:
/// - Per-partition IDF calculations (terms rare in one partition score higher)
/// - More efficient memory usage (no wasted postings across unrelated documents)
/// - Ability to search specific partitions or merge results from multiple partitions
///
/// Example:
/// ```dart
/// // Partition documents by file type
/// final partitioned = await PartitionedBM25.build(
///   documents,
///   partitionBy: (doc) => doc.meta['fileType'] as String,
/// );
///
/// // Search only PDF files
/// final pdfResults = await partitioned.searchIn('pdf', 'query');
///
/// // Search across multiple partitions
/// final results = await partitioned.searchMany(['pdf', 'txt'], 'query');
/// ```
class PartitionedBM25 {
  final Map<String, BM25> _part; // key → sub-index

  PartitionedBM25._(this._part);

  /// Builds a partitioned BM25 index from a collection of documents.
  ///
  /// Documents are grouped into partitions based on the [partitionBy] function,
  /// and a separate BM25 index is created for each partition.
  ///
  /// Parameters:
  /// - [docs]: The documents to index
  /// - [partitionBy]: Function that returns the partition key for each document.
  ///   Documents with the same key will be indexed together.
  /// - [indexFields]: Metadata fields to index for filtering (default: ['filePath'])
  /// - [stopWords]: Optional set of words to ignore during indexing
  ///
  /// Returns a [Future] that completes with the built [PartitionedBM25] instance.
  ///
  /// Example:
  /// ```dart
  /// final partitioned = await PartitionedBM25.build(
  ///   documents,
  ///   partitionBy: (doc) => doc.meta['category'] as String,
  ///   indexFields: ['author', 'year'],
  /// );
  /// ```
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

  /// Searches within a specific partition.
  ///
  /// This method searches only the documents in the partition identified by [key].
  /// If the partition doesn't exist, returns an empty list.
  ///
  /// Parameters:
  /// - [key]: The partition key to search in
  /// - [query]: The search query
  /// - [limit]: Maximum number of results (default: 10)
  ///
  /// Returns a [Future] with search results from the specified partition.
  ///
  /// Example:
  /// ```dart
  /// // Search only in the 'technical' partition
  /// final results = await partitioned.searchIn(
  ///   'technical',
  ///   'machine learning',
  ///   limit: 20
  /// );
  /// ```
  Future<List<SearchResult>> searchIn(
    String key,
    String query, {
    int limit = 10,
  }) =>
      _part[key]?.search(query, limit: limit) ?? Future.value(const []);

  /// Searches across multiple partitions and merges results.
  ///
  /// This method performs parallel searches across the specified partitions
  /// and merges the results, returning the top-scoring documents across all
  /// searched partitions.
  ///
  /// Parameters:
  /// - [keys]: The partition keys to search in
  /// - [query]: The search query
  /// - [limit]: Maximum number of results after merging (default: 10)
  ///
  /// Returns a [Future] with merged search results sorted by score.
  ///
  /// The merging process:
  /// 1. Searches are performed in parallel across all partitions
  /// 2. Results are combined and sorted by score
  /// 3. Top [limit] results are returned
  ///
  /// Example:
  /// ```dart
  /// // Search across multiple document types
  /// final results = await partitioned.searchMany(
  ///   ['pdf', 'docx', 'txt'],
  ///   'quarterly report',
  ///   limit: 50
  /// );
  /// ```
  Future<List<SearchResult>> searchMany(
    Iterable<String> keys,
    String query, {
    int limit = 10,
  }) async {
    final futures = [
      for (final k in keys)
        if (_part[k] != null) _part[k]!.search(query)
    ];
    if (futures.isEmpty) return const [];
    final parts = await Future.wait(futures);

    // k-way merge (simple concat+sort is fine for ≤5 partitions)
    final merged = parts.expand((x) => x).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return merged.take(limit).toList();
  }

  /// Disposes all partition indices and releases resources.
  ///
  /// This method disposes each partition's BM25 index in parallel.
  /// After calling dispose, the instance cannot be used for searching.
  ///
  /// Always call this method when done to ensure proper cleanup:
  /// ```dart
  /// final partitioned = await PartitionedBM25.build(docs, ...);
  /// try {
  ///   // Use the index...
  /// } finally {
  ///   await partitioned.dispose();
  /// }
  /// ```
  Future<void> dispose() async {
    await Future.wait(_part.values.map((i) => i.dispose()));
  }
}
