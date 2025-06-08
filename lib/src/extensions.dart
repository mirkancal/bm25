import 'dart:math' as math;

import 'bm25.dart';
import 'search_result.dart';

extension BM25Advanced on BM25 {
  /// Performs search with relevance feedback using the Rocchio algorithm.
  ///
  /// This method enhances search results by incorporating terms from documents
  /// marked as relevant. The algorithm expands the original query with weighted
  /// terms that frequently appear in relevant documents.
  ///
  /// Parameters:
  /// - [query]: The original search query
  /// - [relevantDocIds]: List of document IDs marked as relevant
  /// - [alpha]: Weight for original query terms (default: 1.0)
  /// - [beta]: Weight for terms from relevant documents (default: 0.75)
  /// - [limit]: Maximum number of results to return
  ///
  /// Returns a list of [SearchResult] objects with improved relevance.
  /// If no relevant documents are found, performs a regular search.
  Future<List<SearchResult>> searchWithFeedback(
    String query, {
    List<int> relevantDocIds = const [],
    double alpha = 1.0,
    double beta = 0.75,
    int? limit,
  }) async {
    final effectiveLimit = limit ?? 10;

    // If no relevant documents specified, perform regular search
    if (relevantDocIds.isEmpty) {
      return search(query, limit: effectiveLimit);
    }

    // Convert to Set for O(1) lookup
    final relevantIdSet = relevantDocIds.toSet();
    final termFrequencies = <String, double>{};
    var foundCount = 0;

    // Access documents directly and find relevant ones
    for (final doc in documents) {
      if (!relevantIdSet.contains(doc.id)) continue;
      foundCount++;

      // Normalize by document length to avoid bias towards long documents
      final lengthNorm = doc.terms.isEmpty ? 0 : 1.0 / doc.terms.length;

      for (final term in doc.terms) {
        termFrequencies.update(
          term,
          (value) => value + lengthNorm,
          ifAbsent: () => lengthNorm.toDouble(),
        );
      }

      // Early exit if all relevant documents found
      if (foundCount == relevantIdSet.length) break;
    }

    // If no relevant documents found, fall back to regular search
    if (foundCount == 0) {
      return search(query, limit: effectiveLimit);
    }

    // Tokenize query properly (filter stop words and short terms)
    final queryTokens = query
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((term) => term.length >= 2)
        .toList();

    // Build weighted term map using Rocchio algorithm
    final weightedTerms = <String, double>{};

    // Add original query terms with alpha weight
    for (final term in queryTokens) {
      weightedTerms[term] = alpha;
    }

    // Add terms from relevant documents with beta weight
    // Normalize by number of relevant documents found
    final docNorm = 1.0 / foundCount;
    for (final entry in termFrequencies.entries) {
      final normalizedWeight = beta * entry.value * docNorm;
      weightedTerms.update(
        entry.key,
        (value) => value + normalizedWeight,
        ifAbsent: () => normalizedWeight,
      );
    }

    // Sort terms by weight and select top terms
    final sortedTerms = weightedTerms.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Take top terms (ensure we don't exceed reasonable query size)
    final maxTerms = 30;
    final selectedTerms = sortedTerms.take(maxTerms).toList();

    // Always include original query terms to preserve user intent
    final requiredTerms = queryTokens.toSet();

    // Build expanded query with term repetition based on weights
    final expandedTerms = <String>[];

    for (final entry in selectedTerms) {
      final term = entry.key;
      final weight = entry.value;

      // Ensure original query terms are always included
      if (requiredTerms.contains(term)) {
        requiredTerms.remove(term);
      }

      // Repeat terms based on their weight using logarithmic scale
      // This provides better representation for highly weighted terms
      final repetitions = weight.isFinite && weight > 1
          ? (1 + math.log(weight)).round().clamp(1, 8).toInt()
          : 1;
      for (int i = 0; i < repetitions; i++) {
        expandedTerms.add(term);
      }
    }

    // Add any remaining original query terms that weren't in selectedTerms
    expandedTerms.addAll(requiredTerms);

    // If no terms selected, fall back to original query
    if (expandedTerms.isEmpty) {
      return search(query, limit: effectiveLimit);
    }

    // Construct expanded query
    final expandedQuery = expandedTerms.join(' ');

    // Search with expanded query
    return search(expandedQuery, limit: effectiveLimit);
  }
}
