import 'document.dart';

/// Search result with document and relevance score
class SearchResult {
  final Document document;
  final double score;
  
  SearchResult({required this.document, required this.score});
}
