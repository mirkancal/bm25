import 'bm25_document.dart';

class SearchResult {
  /// The document that matched.
  final BM25Document doc;

  /// BM25 score (higher = better).
  final double score;

  const SearchResult(this.doc, this.score);
}
