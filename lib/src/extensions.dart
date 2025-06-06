import 'bm25.dart';
import 'search_result.dart';

extension BM25Advanced on BM25 {
  Future<List<SearchResult>> searchWithFeedback(
    String query, {
    List<String> relevantDocIds = const [],
    double alpha = 1.0,
    double beta = 0.75,
    int? limit,
  }) {
    // Implementation here...
    return search(query, limit: limit ?? 10); // Simplified
  }
}
