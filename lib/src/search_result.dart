import 'bm25_document.dart';

/// Represents a single search result from a BM25 query.
///
/// Each result contains the matched document and its relevance score.
/// Results are typically returned in descending order by score (highest
/// relevance first).
///
/// The score is calculated using the BM25 algorithm, which considers:
/// - Term frequency in the document
/// - Inverse document frequency across the corpus
/// - Document length normalization
///
/// Higher scores indicate better matches. Score values are not normalized
/// and can vary based on the corpus and query.
///
/// Example:
/// ```dart
/// final results = await bm25.search('query');
/// for (final result in results) {
///   print('Score: ${result.score}');
///   print('Text: ${result.doc.text}');
///   print('Metadata: ${result.doc.meta}');
/// }
/// ```
class SearchResult {
  /// The document that matched the search query.
  ///
  /// This provides access to the full document including its text,
  /// terms, and any metadata that was indexed.
  final BM25Document doc;

  /// The BM25 relevance score for this document.
  ///
  /// Higher scores indicate better matches. The score is calculated
  /// based on:
  /// - How many query terms appear in the document
  /// - How frequently those terms appear
  /// - How rare those terms are across all documents
  /// - The length of the document relative to the average
  ///
  /// Scores are not normalized and their absolute values depend on
  /// the corpus characteristics and query complexity.
  final double score;

  /// Creates a new search result.
  ///
  /// Parameters:
  /// - [doc]: The matched document
  /// - [score]: The BM25 relevance score
  const SearchResult(this.doc, this.score);
}
