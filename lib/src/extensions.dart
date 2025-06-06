import 'bm25_core.dart';
import 'search_result.dart' as sr;

extension BM25Advanced on BM25 {
  Future<List<sr.SearchResult>> searchWithFeedback(
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
