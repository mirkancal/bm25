/// A Dart implementation of the BM25 ranking algorithm for full-text search.
///
/// This library provides high-performance document search capabilities using the
/// Okapi BM25 algorithm, which is widely used in information retrieval systems.
///
/// Features:
/// - Fast full-text search with BM25 scoring
/// - Support for metadata filtering on indexed fields
/// - Unicode-aware tokenization
/// - Stop word filtering
/// - Concurrent search operations via isolates
///
/// Example usage:
/// ```dart
/// import 'package:bm25/bm25.dart';
///
/// final corpus = [
///   BM25Document(
///     id: 0,
///     text: 'The quick brown fox',
///     terms: ['quick', 'brown', 'fox'],
///     meta: {'category': 'animals'}
///   ),
///   // ... more documents
/// ];
///
/// final bm25 = await BM25.build(
///   corpus,
///   indexFields: ['category']
/// );
///
/// final results = await bm25.search(
///   'brown fox',
///   filter: {'category': 'animals'}
/// );
/// ```
library bm25;

export 'src/bm25_document.dart';
export 'src/bm25.dart';
export 'src/partitioned_bm25.dart';
export 'src/search_result.dart';
export 'src/extensions.dart';
