import 'dart:math' as math;
import 'bm25_core.dart';
import 'document.dart';
import 'search_result.dart';

extension BM25Advanced on BM25 {
  List<SearchResult> searchWithFeedback(
    String query, {
    List<String> relevantDocIds = const [],
    double alpha = 1.0,
    double beta = 0.75,
    int? limit,
  }) {
    // Implementation here...
    return search(query, limit: limit); // Simplified
  }
}
