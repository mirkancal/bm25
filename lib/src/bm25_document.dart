/// A document in the BM25 search corpus.
///
/// This class represents a searchable document with its text content,
/// pre-computed search terms, and optional metadata for filtering.
///
/// Each document must have:
/// - A unique [id] (assigned automatically during indexing)
/// - The original [text] content
/// - A list of [terms] extracted from the text
/// - Optional [meta] data for filtering
///
/// Example:
/// ```dart
/// final doc = BM25Document(
///   id: 0,
///   text: 'The quick brown fox jumps',
///   terms: ['quick', 'brown', 'fox', 'jumps'],
///   meta: {
///     'author': 'John Doe',
///     'category': 'animals',
///     'tags': ['nature', 'movement']
///   }
/// );
/// ```
class BM25Document {
  /// The unique identifier for this document.
  ///
  /// IDs are automatically assigned during index building, starting from 0.
  /// They remain stable throughout the lifetime of the BM25 instance.
  final int id;

  /// The original text content of the document.
  ///
  /// This is preserved exactly as provided and can be used for display
  /// purposes or snippet generation after search results are returned.
  final String text;

  /// The tokenized and normalized terms extracted from the text.
  ///
  /// These terms are used for BM25 scoring. They are typically:
  /// - Converted to lowercase
  /// - Split on word boundaries
  /// - Filtered to remove stop words (if configured)
  ///
  /// The terms list determines what queries will match this document.
  final List<String> terms;

  /// Optional metadata for filtering and enrichment.
  ///
  /// The map can contain any key-value pairs where values are primitives
  /// (String, num, bool) or Lists of primitives. Only fields that were
  /// specified in `indexFields` during BM25.build() can be used for filtering.
  ///
  /// Example:
  /// ```dart
  /// meta: {
  ///   'filePath': '/docs/guide.pdf',
  ///   'author': 'Jane Smith',
  ///   'year': 2023,
  ///   'tags': ['tutorial', 'beginner']
  /// }
  /// ```
  final Map<String, Object> meta;

  /// Creates a new BM25 document.
  ///
  /// All parameters except [meta] are required:
  /// - [id]: Unique document identifier (usually auto-assigned during indexing)
  /// - [text]: The original document text
  /// - [terms]: Pre-tokenized search terms
  /// - [meta]: Optional metadata for filtering (defaults to empty map)
  const BM25Document({
    required this.id,
    required this.text,
    required this.terms,
    this.meta = const {},
  });
}
