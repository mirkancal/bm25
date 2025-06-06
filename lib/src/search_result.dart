import 'document.dart';

/// Search result with document and relevance score
class SearchResult {
  final Document doc;
  final double score;

  const SearchResult(this.doc, this.score);
}
