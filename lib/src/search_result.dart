import 'bm25_document.dart';

/// Search result with document and relevance score
class SearchResult {
  final BM25Document doc;
  final double score;

  const SearchResult(this.doc, this.score);
}
